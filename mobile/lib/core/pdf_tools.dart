import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

enum PhotoFilter { none, grayscale, sepia, vivid, document }

/// Pure-Dart image ops (unit-testable, run in an isolate by callers).
class ImageOps {
  static Uint8List rotate(Uint8List bytes, int degrees) {
    final im = img.decodeImage(bytes)!;
    return img.encodeJpg(img.copyRotate(im, angle: degrees), quality: 92);
  }

  static Uint8List applyFilter(Uint8List bytes, PhotoFilter f) {
    var im = img.decodeImage(bytes)!;
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
        im = img.adjustColor(img.grayscale(im), contrast: 1.6, brightness: 1.1);
    }
    return img.encodeJpg(im, quality: 92);
  }

  /// Auto-enhance: stretch the histogram (normalize), slight sharpen.
  static Uint8List autoEnhance(Uint8List bytes) {
    var im = img.decodeImage(bytes)!;
    im = img.normalize(im, min: 0, max: 255);
    im = img.adjustColor(im, saturation: 1.1);
    im = img.convolution(im, filter: [0, -1, 0, -1, 5, -1, 0, -1, 0]);
    return img.encodeJpg(im, quality: 92);
  }
}

class PdfTools {
  /// One image per page, fitted; [perSheet] > 1 tiles several images on one page.
  static Future<Uint8List> imagesToPdf(List<Uint8List> images, {PdfPageFormat format = PdfPageFormat.a4, int perSheet = 1}) async {
    final doc = pw.Document();
    final cols = perSheet >= 4 ? 2 : 1;
    final rows = perSheet >= 2 ? 2 : 1;
    final per = cols * rows;
    for (var i = 0; i < images.length; i += per) {
      final chunk = images.sublist(i, (i + per).clamp(0, images.length));
      doc.addPage(pw.Page(
        pageFormat: format,
        margin: const pw.EdgeInsets.all(16),
        build: (_) => pw.GridView(
          crossAxisCount: cols,
          childAspectRatio: (format.availableWidth / cols) / (format.availableHeight / rows),
          children: chunk.map((b) => pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Center(child: pw.Image(pw.MemoryImage(b), fit: pw.BoxFit.contain)))).toList(),
        ),
      ));
    }
    return doc.save();
  }

  static Future<Uint8List> textToPdf(String title, String text, {pw.Font? font}) async {
    final doc = pw.Document();
    final style = pw.TextStyle(font: font, fontSize: 11);
    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      build: (_) => [
        pw.Header(level: 1, child: pw.Text(title, style: style.copyWith(fontSize: 16))),
        ...text.split('\n').map((l) => pw.Paragraph(text: l, style: style)),
      ],
    ));
    return doc.save();
  }
}
