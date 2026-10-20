import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

enum PhotoFilter { none, grayscale, sepia, vivid, document }

/// Pure-Dart image ops (unit-testable; callers run them via compute()).
class ImageOps {
  static const maxSide = 2400; // ~300 dpi on A4 short side; keeps PDFs small and memory low

  static img.Image _decode(Uint8List b) => img.decodeImage(b) ?? (throw const FormatException('Unsupported image'));
  static Uint8List _enc(img.Image i) => img.encodeJpg(i, quality: 90);

  /// Applies EXIF orientation and downsizes huge photos.
  static Uint8List prepare(Uint8List bytes) {
    var im = img.bakeOrientation(_decode(bytes));
    if (im.width > maxSide || im.height > maxSide) {
      im = im.width >= im.height ? img.copyResize(im, width: maxSide) : img.copyResize(im, height: maxSide);
    }
    return _enc(im);
  }

  static Uint8List rotate(Uint8List bytes, int degrees) => _enc(img.copyRotate(_decode(bytes), angle: degrees));

  static Uint8List applyFilter(Uint8List bytes, PhotoFilter f) {
    var im = _decode(bytes);
    switch (f) {
      case PhotoFilter.none:
        return bytes;
      case PhotoFilter.grayscale:
        im = img.grayscale(im);
      case PhotoFilter.sepia:
        im = img.sepia(im);
      case PhotoFilter.vivid:
        im = img.adjustColor(im, saturation: 1.35, contrast: 1.1);
      case PhotoFilter.document:
        im = img.adjustColor(img.grayscale(img.normalize(im, min: 0, max: 255)), contrast: 1.6, brightness: 1.1);
    }
    return _enc(im);
  }

  /// Auto-enhance: histogram stretch, light saturation, sharpen.
  static Uint8List autoEnhance(Uint8List bytes) {
    var im = img.normalize(_decode(bytes), min: 0, max: 255);
    im = img.adjustColor(im, saturation: 1.1);
    im = img.convolution(im, filter: [0, -1, 0, -1, 5, -1, 0, -1, 0]);
    return _enc(im);
  }
}

/// Photos-per-sheet layouts: (columns, rows) on a portrait page.
const photoLayouts = {1: (1, 1), 2: (1, 2), 4: (2, 2), 6: (2, 3), 9: (3, 3)};

class PdfTools {
  static Future<Uint8List> imagesToPdf(
    List<Uint8List> images, {
    PdfPageFormat format = PdfPageFormat.a4,
    int perSheet = 1,
    bool fill = false,
    double margin = 18,
    double gap = 6,
  }) async {
    final doc = pw.Document();
    var (cols, rows) = photoLayouts[perSheet] ?? (1, 1);
    if (format.width > format.height) (cols, rows) = (rows, cols);
    final per = cols * rows;
    final cellW = (format.width - 2 * margin - (cols - 1) * gap) / cols;
    final cellH = (format.height - 2 * margin - (rows - 1) * gap) / rows;
    for (var i = 0; i < images.length; i += per) {
      final chunk = images.sublist(i, (i + per).clamp(0, images.length));
      doc.addPage(pw.Page(
        pageFormat: format,
        margin: pw.EdgeInsets.all(margin),
        build: (_) => pw.Wrap(spacing: gap, runSpacing: gap, children: [
          for (final b in chunk)
            pw.SizedBox(width: cellW, height: cellH, child: pw.ClipRect(child: pw.Image(pw.MemoryImage(b), fit: fill ? pw.BoxFit.cover : pw.BoxFit.contain))),
        ]),
      ));
    }
    if (images.isEmpty) doc.addPage(pw.Page(pageFormat: format, build: (_) => pw.SizedBox()));
    return doc.save();
  }

  /// Page count without rasterizing (works for our PDFs and most uncompressed page trees).
  static int pageCount(Uint8List pdf) {
    final s = String.fromCharCodes(pdf.length > 4000000 ? pdf.sublist(pdf.length - 4000000) : pdf);
    final counts = RegExp(r'/Count\s+(\d+)').allMatches(s).map((m) => int.parse(m.group(1)!));
    if (counts.isNotEmpty) return counts.reduce((a, b) => a > b ? a : b);
    final pages = RegExp(r'/Type\s*/Page[^s]').allMatches(s).length;
    return pages == 0 ? 1 : pages;
  }
}
