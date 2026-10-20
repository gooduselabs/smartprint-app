import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:xml/xml.dart';

import 'fonts.dart';

/// Best-effort, fully offline Office -> PDF.
/// DOCX: paragraphs, headings, bold/italic/underline/size/colour, alignment, lists, tables, inline images, page breaks.
/// XLSX: every sheet as a table (values / shared strings / cached formula results).
/// PPTX: each slide as a page, shapes positioned by their EMU frame; text + pictures.
/// CSV / TXT handled too. Not supported: legacy .doc/.xls/.ppt, charts, SmartArt, EMF/WMF, exact fonts.
class OfficeConverter {
  OfficeConverter(this.fonts);
  final PdfFonts fonts;

  static const supported = ['docx', 'xlsx', 'pptx', 'csv', 'txt'];

  Future<Uint8List> convert(String ext, Uint8List bytes, {String title = 'Document'}) {
    switch (ext.toLowerCase()) {
      case 'docx':
        return docx(bytes);
      case 'xlsx':
        return xlsx(bytes);
      case 'pptx':
        return pptx(bytes);
      case 'csv':
        return csv(utf8.decode(bytes, allowMalformed: true), title: title);
      case 'txt':
        return text(utf8.decode(bytes, allowMalformed: true));
    }
    throw UnsupportedError('.$ext is not supported offline. Save it as DOCX/XLSX/PPTX or PDF.');
  }

  // ---------- helpers ----------
  static Archive _zip(Uint8List b) {
    try {
      return ZipDecoder().decodeBytes(b);
    } catch (_) {
      throw const FormatException('Not a valid Office (OOXML) file');
    }
  }

  static Uint8List? _file(Archive a, String path) {
    final f = a.findFile(path);
    return f == null ? null : Uint8List.fromList(f.content as List<int>);
  }

  static XmlDocument? _xml(Archive a, String path) {
    final b = _file(a, path);
    return b == null ? null : XmlDocument.parse(utf8.decode(b, allowMalformed: true));
  }

  /// Relationship id -> absolute zip path.
  static Map<String, String> _rels(Archive a, String partPath) {
    final dir = partPath.substring(0, partPath.lastIndexOf('/'));
    final name = partPath.substring(partPath.lastIndexOf('/') + 1);
    final doc = _xml(a, '$dir/_rels/$name.rels');
    if (doc == null) return {};
    return {
      for (final r in doc.findAllElements('Relationship'))
        r.getAttribute('Id')!: _resolve(dir, r.getAttribute('Target')!),
    };
  }

  static String _resolve(String dir, String target) {
    if (target.startsWith('/')) return target.substring(1);
    final parts = [...dir.split('/'), ...target.split('/')];
    final out = <String>[];
    for (final p in parts) {
      if (p == '..') {
        if (out.isNotEmpty) out.removeLast();
      } else if (p.isNotEmpty && p != '.') {
        out.add(p);
      }
    }
    return out.join('/');
  }

  static pw.ImageProvider? _image(Uint8List? b) {
    if (b == null || b.length < 4) return null;
    final png = b[0] == 0x89 && b[1] == 0x50, jpg = b[0] == 0xFF && b[1] == 0xD8;
    return png || jpg ? pw.MemoryImage(b) : null; // EMF/WMF/SVG skipped
  }

  static String? _attr(XmlElement? e, String local) {
    if (e == null) return null;
    for (final a in e.attributes) {
      if (a.name.local == local) return a.value;
    }
    return null;
  }

  /// Relationship reference (r:id), distinct from a plain numeric `id`.
  static String? _rid(XmlElement e) => e.attributes.where((a) => a.name.local == 'id' && a.name.prefix != null).firstOrNull?.value;

  static XmlElement? _child(XmlElement? e, String local) => e?.childElements.where((c) => c.name.local == local).firstOrNull;
  static Iterable<XmlElement> _desc(XmlNode e, String local) => e.descendants.whereType<XmlElement>().where((c) => c.name.local == local);

  static PdfColor? _color(String? hex) => (hex != null && RegExp(r'^[0-9A-Fa-f]{6}$').hasMatch(hex)) ? PdfColor.fromHex(hex) : null;

  pw.Document _doc() => pw.Document(theme: fonts.theme);

  // ---------- DOCX ----------
  Future<Uint8List> docx(Uint8List bytes) async {
    final a = _zip(bytes);
    final doc = _xml(a, 'word/document.xml') ?? (throw const FormatException('word/document.xml missing'));
    final rels = _rels(a, 'word/document.xml');
    final body = _desc(doc, 'body').first;
    final pages = <List<pw.Widget>>[[]];

    for (final el in body.childElements) {
      if (el.name.local == 'p') {
        final (w, pageBreak) = _docxPara(el, a, rels);
        pages.last.addAll(w);
        if (pageBreak) pages.add([]);
      } else if (el.name.local == 'tbl') {
        pages.last.add(_docxTable(el, a, rels));
      }
    }
    final pdf = _doc();
    for (final p in pages.where((p) => p.isNotEmpty)) {
      pdf.addPage(pw.MultiPage(pageFormat: PdfPageFormat.a4, margin: const pw.EdgeInsets.all(56), build: (_) => p, maxPages: 500));
    }
    if (pages.every((p) => p.isEmpty)) pdf.addPage(pw.Page(build: (_) => pw.SizedBox()));
    return pdf.save();
  }

  (List<pw.Widget>, bool) _docxPara(XmlElement p, Archive a, Map<String, String> rels) {
    final ppr = _child(p, 'pPr');
    final style = _attr(_child(ppr, 'pStyle'), 'val')?.toLowerCase() ?? '';
    final isList = _child(ppr, 'numPr') != null || style.contains('list');
    final jc = _attr(_child(ppr, 'jc'), 'val');
    double base = 11;
    var boldAll = false;
    final h = RegExp(r'heading(\d)').firstMatch(style);
    if (style == 'title') {
      base = 24;
      boldAll = true;
    } else if (h != null) {
      base = [20.0, 16.0, 13.0, 12.0][(int.parse(h.group(1)!) - 1).clamp(0, 3)];
      boldAll = true;
    }
    final spans = <pw.InlineSpan>[];
    final images = <pw.Widget>[];
    var pageBreak = false;
    for (final r in _desc(p, 'r')) {
      final rpr = _child(r, 'rPr');
      final sz = double.tryParse(_attr(_child(rpr, 'sz'), 'val') ?? '');
      bool on(String n) {
        final e = _child(rpr, n);
        return e != null && !['0', 'false'].contains(_attr(e, 'val'));
      }

      final st = pw.TextStyle(
        fontSize: sz != null ? sz / 2 : base,
        fontWeight: (boldAll || on('b')) ? pw.FontWeight.bold : null,
        fontStyle: on('i') ? pw.FontStyle.italic : null,
        decoration: _child(rpr, 'u') != null && _attr(_child(rpr, 'u'), 'val') != 'none' ? pw.TextDecoration.underline : null,
        color: _color(_attr(_child(rpr, 'color'), 'val')),
      );
      for (final c in r.childElements) {
        switch (c.name.local) {
          case 't':
            spans.add(pw.TextSpan(text: c.innerText, style: st));
          case 'tab':
            spans.add(pw.TextSpan(text: '    ', style: st));
          case 'br':
            if (_attr(c, 'type') == 'page') {
              pageBreak = true;
            } else {
              spans.add(pw.TextSpan(text: '\n', style: st));
            }
          case 'drawing':
            for (final blip in _desc(c, 'blip')) {
              final img = _image(_file(a, rels[_attr(blip, 'embed')] ?? ''));
              final ext = _desc(c, 'extent').firstOrNull;
              final w = (double.tryParse(_attr(ext, 'cx') ?? '') ?? 0) / 12700; // EMU -> pt
              if (img != null) images.add(pw.Padding(padding: const pw.EdgeInsets.symmetric(vertical: 4), child: pw.Image(img, width: w > 0 ? w.clamp(20, 480) : 300)));
            }
        }
      }
    }
    final align = switch (jc) { 'center' => pw.TextAlign.center, 'right' || 'end' => pw.TextAlign.right, 'both' => pw.TextAlign.justify, _ => pw.TextAlign.left };
    final out = <pw.Widget>[];
    if (spans.isNotEmpty) {
      final txt = pw.RichText(text: pw.TextSpan(children: spans), textAlign: align);
      out.add(pw.Padding(
        padding: pw.EdgeInsets.only(bottom: boldAll ? 6 : 4, top: boldAll ? 8 : 0),
        child: isList ? pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [pw.SizedBox(width: 14, child: pw.Text('•')), pw.Expanded(child: txt)]) : txt,
      ));
    } else if (images.isEmpty && !pageBreak) {
      out.add(pw.SizedBox(height: base * .8));
    }
    out.addAll(images.map((i) => pw.Align(alignment: jc == 'center' ? pw.Alignment.center : pw.Alignment.centerLeft, child: i)));
    return (out, pageBreak);
  }

  pw.Widget _docxTable(XmlElement tbl, Archive a, Map<String, String> rels) {
    final rows = tbl.childElements.where((e) => e.name.local == 'tr').map((tr) => tr.childElements.where((e) => e.name.local == 'tc').map<pw.Widget>((tc) {
          final ws = <pw.Widget>[];
          for (final p in tc.childElements.where((e) => e.name.local == 'p')) {
            ws.addAll(_docxPara(p, a, rels).$1);
          }
          return pw.Padding(padding: const pw.EdgeInsets.all(3), child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: ws));
        }).toList()).where((r) => r.isNotEmpty).toList();
    if (rows.isEmpty) return pw.SizedBox();
    final cols = rows.map((r) => r.length).reduce((x, y) => x > y ? x : y);
    for (final r in rows) {
      while (r.length < cols) {
        r.add(pw.SizedBox());
      }
    }
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 6),
      child: pw.Table(border: pw.TableBorder.all(width: .5, color: PdfColors.grey600), children: rows.map((r) => pw.TableRow(children: r)).toList()),
    );
  }

  // ---------- XLSX ----------
  static int _colIndex(String ref) {
    var n = 0;
    for (final c in ref.codeUnits) {
      if (c < 65 || c > 90) break;
      n = n * 26 + (c - 64);
    }
    return n - 1;
  }

  static const maxRows = 3000, maxCols = 40;

  /// Parsed sheets: name -> grid of strings (exposed for tests).
  static List<(String, List<List<String>>)> readXlsx(Uint8List bytes) {
    final a = _zip(bytes);
    final wb = _xml(a, 'xl/workbook.xml') ?? (throw const FormatException('xl/workbook.xml missing'));
    final rels = _rels(a, 'xl/workbook.xml');
    final shared = <String>[
      for (final si in _desc(_xml(a, 'xl/sharedStrings.xml') ?? XmlDocument.parse('<sst/>'), 'si')) _desc(si, 't').map((t) => t.innerText).join(),
    ];
    final out = <(String, List<List<String>>)>[];
    for (final s in _desc(wb, 'sheet')) {
      final path = rels[_rid(s)];
      final sheet = path == null ? null : _xml(a, path);
      if (sheet == null) continue;
      final grid = <List<String>>[];
      for (final row in _desc(sheet, 'row')) {
        if (grid.length >= maxRows) break;
        final r = (int.tryParse(_attr(row, 'r') ?? '') ?? grid.length + 1) - 1;
        if (r >= maxRows) break;
        while (grid.length <= r) {
          grid.add([]);
        }
        var auto = 0;
        for (final c in row.childElements.where((e) => e.name.local == 'c')) {
          final ref = _attr(c, 'r');
          final ci = ref != null ? _colIndex(ref) : auto;
          auto = ci + 1;
          if (ci >= maxCols || ci < 0) continue;
          final t = _attr(c, 't');
          final v = _child(c, 'v')?.innerText ?? '';
          final val = switch (t) {
            's' => (int.tryParse(v) ?? -1) >= 0 && int.parse(v) < shared.length ? shared[int.parse(v)] : '',
            'inlineStr' => _desc(c, 't').map((e) => e.innerText).join(),
            'b' => v == '1' ? 'TRUE' : 'FALSE',
            _ => _fmtNum(v),
          };
          final line = grid[r];
          while (line.length <= ci) {
            line.add('');
          }
          line[ci] = val;
        }
      }
      while (grid.isNotEmpty && grid.last.every((e) => e.isEmpty)) {
        grid.removeLast();
      }
      out.add((_attr(s, 'name') ?? 'Sheet', grid));
    }
    return out;
  }

  static String _fmtNum(String v) {
    final d = double.tryParse(v);
    if (d == null) return v;
    if (d == d.roundToDouble() && d.abs() < 1e15) return d.toInt().toString();
    return double.parse(d.toStringAsPrecision(10)).toString();
  }

  Future<Uint8List> xlsx(Uint8List bytes) async {
    final pdf = _doc();
    final sheets = readXlsx(bytes);
    for (final (name, grid) in sheets) {
      pdf.addPage(_tablePage(name, grid));
    }
    if (sheets.isEmpty) pdf.addPage(pw.Page(build: (_) => pw.Center(child: pw.Text('Empty workbook'))));
    return pdf.save();
  }

  pw.MultiPage _tablePage(String name, List<List<String>> grid) {
    final cols = grid.fold<int>(0, (m, r) => r.length > m ? r.length : m);
    final rows = [for (final r in grid) [...r, for (var i = r.length; i < cols; i++) '']];
    final fs = cols > 14 ? 6.0 : cols > 8 ? 7.5 : 9.0;
    return pw.MultiPage(
      pageFormat: cols > 6 ? PdfPageFormat.a4.landscape : PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(24),
      maxPages: 500,
      header: (_) => pw.Padding(padding: const pw.EdgeInsets.only(bottom: 6), child: pw.Text(name, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12))),
      build: (_) => rows.isEmpty || cols == 0
          ? [pw.Text('(empty sheet)')]
          : [
              pw.TableHelper.fromTextArray(
                data: rows,
                headerCount: 0,
                cellStyle: pw.TextStyle(fontSize: fs),
                cellPadding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 2),
                border: pw.TableBorder.all(width: .3, color: PdfColors.grey500),
                cellAlignment: pw.Alignment.centerLeft,
              ),
            ],
    );
  }

  Future<Uint8List> csv(String data, {String title = 'CSV'}) async {
    final delim = data.split('\n').first.contains(';') && !data.split('\n').first.contains(',') ? ';' : ',';
    final grid = <List<String>>[];
    for (final line in const LineSplitter().convert(data).take(maxRows)) {
      final row = <String>[];
      final sb = StringBuffer();
      var q = false;
      for (var i = 0; i < line.length; i++) {
        final ch = line[i];
        if (ch == '"') {
          if (q && i + 1 < line.length && line[i + 1] == '"') {
            sb.write('"');
            i++;
          } else {
            q = !q;
          }
        } else if (ch == delim && !q) {
          row.add(sb.toString());
          sb.clear();
        } else {
          sb.write(ch);
        }
      }
      row.add(sb.toString());
      grid.add(row.take(maxCols).toList());
    }
    final pdf = _doc()..addPage(_tablePage(title, grid));
    return pdf.save();
  }

  Future<Uint8List> text(String data, {String? title}) async {
    final pdf = _doc();
    pdf.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(48),
      maxPages: 1000,
      build: (_) => [
        if (title != null) pw.Header(level: 1, child: pw.Text(title, style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold))),
        for (final l in const LineSplitter().convert(data)) pw.Paragraph(text: l.isEmpty ? ' ' : l, style: const pw.TextStyle(fontSize: 11), margin: const pw.EdgeInsets.only(bottom: 2)),
      ],
    ));
    return pdf.save();
  }

  // ---------- PPTX ----------
  Future<Uint8List> pptx(Uint8List bytes) async {
    final a = _zip(bytes);
    final pres = _xml(a, 'ppt/presentation.xml') ?? (throw const FormatException('ppt/presentation.xml missing'));
    final rels = _rels(a, 'ppt/presentation.xml');
    final sz = _desc(pres, 'sldSz').firstOrNull;
    final cx = double.tryParse(_attr(sz, 'cx') ?? '') ?? 9144000, cy = double.tryParse(_attr(sz, 'cy') ?? '') ?? 5143500;
    final format = PdfPageFormat(cx / 12700, cy / 12700); // EMU -> pt, 1:1
    final pdf = _doc();
    var slides = 0;
    for (final id in _desc(pres, 'sldId')) {
      final path = rels[_rid(id)];
      final slide = path == null ? null : _xml(a, path);
      if (slide == null) continue;
      final srels = _rels(a, path!);
      slides++;
      final children = <pw.Widget>[];
      final tree = _desc(slide, 'spTree').firstOrNull;
      if (tree != null) _pptxShapes(tree, a, srels, children);
      pdf.addPage(pw.Page(
        pageFormat: format,
        margin: pw.EdgeInsets.zero,
        build: (_) => pw.Container(color: PdfColors.white, child: pw.Stack(children: children)),
      ));
    }
    if (slides == 0) pdf.addPage(pw.Page(build: (_) => pw.Center(child: pw.Text('No slides'))));
    return pdf.save();
  }

  void _pptxShapes(XmlElement tree, Archive a, Map<String, String> rels, List<pw.Widget> out) {
    var fallbackTop = 30.0;
    for (final sh in tree.childElements) {
      final kind = sh.name.local;
      if (kind == 'grpSp') {
        _pptxShapes(sh, a, rels, out); // group offsets ignored (approximation)
        continue;
      }
      if (kind != 'sp' && kind != 'pic') continue;
      final xfrm = _desc(sh, 'xfrm').firstOrNull;
      final off = _child(xfrm, 'off'), ext = _child(xfrm, 'ext');
      double emu(XmlElement? e, String n) => (double.tryParse(_attr(e, n) ?? '') ?? 0) / 12700;
      var x = emu(off, 'x'), y = emu(off, 'y'), w = emu(ext, 'cx'), h = emu(ext, 'cy');
      final isTitle = _desc(sh, 'ph').any((p) => (_attr(p, 'type') ?? '').contains('itle'));
      if (w <= 0) {
        // placeholder inheriting layout geometry: stack vertically
        x = 40;
        y = fallbackTop;
        w = 640;
        h = isTitle ? 60 : 300;
      }
      fallbackTop = y + h + 10;
      pw.Widget? child;
      if (kind == 'pic') {
        final img = _image(_file(a, rels[_attr(_desc(sh, 'blip').firstOrNull, 'embed')] ?? ''));
        if (img != null) child = pw.Image(img, fit: pw.BoxFit.contain);
      } else {
        final paras = <pw.Widget>[];
        for (final p in _desc(sh, 'p')) {
          final runs = _desc(p, 'r').toList();
          if (runs.isEmpty) continue;
          final lvl = int.tryParse(_attr(_child(p, 'pPr'), 'lvl') ?? '') ?? 0;
          final spans = runs.map((r) {
            final rpr = _child(r, 'rPr');
            final s = double.tryParse(_attr(rpr, 'sz') ?? '');
            final fill = _attr(_desc(rpr ?? r, 'srgbClr').firstOrNull, 'val');
            return pw.TextSpan(
              text: _child(r, 't')?.innerText ?? '',
              style: pw.TextStyle(
                fontSize: s != null ? s / 100 : (isTitle ? 32 : 18),
                fontWeight: isTitle || _attr(rpr, 'b') == '1' ? pw.FontWeight.bold : null,
                fontStyle: _attr(rpr, 'i') == '1' ? pw.FontStyle.italic : null,
                color: _color(fill),
              ),
            );
          }).toList();
          final bullet = !isTitle && _child(_child(p, 'pPr'), 'buNone') == null && _desc(sh, 'ph').isNotEmpty;
          paras.add(pw.Padding(
            padding: pw.EdgeInsets.only(left: lvl * 18.0, bottom: 4),
            child: pw.RichText(text: pw.TextSpan(children: [if (bullet) const pw.TextSpan(text: '•  '), ...spans])),
          ));
        }
        if (paras.isNotEmpty) child = pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: paras);
      }
      if (child != null) {
        out.add(pw.Positioned(left: x, top: y, child: pw.SizedBox(width: w, height: h, child: pw.ClipRect(child: pw.FittedBox(fit: pw.BoxFit.scaleDown, alignment: pw.Alignment.topLeft, child: pw.SizedBox(width: w, child: child))))));
      }
    }
  }
}
