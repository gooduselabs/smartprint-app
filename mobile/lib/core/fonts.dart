import 'package:flutter/services.dart';
import 'package:pdf/widgets.dart' as pw;

/// Bundled Roboto (Latin + Vietnamese) so PDF generation never needs the network.
class PdfFonts {
  PdfFonts(this.regular, this.bold, this.italic);
  final pw.Font regular, bold, italic;

  pw.ThemeData get theme => pw.ThemeData.withFont(base: regular, bold: bold, italic: italic, boldItalic: bold);

  static PdfFonts? _cache;
  static Future<PdfFonts> load() async => _cache ??= PdfFonts(
        pw.Font.ttf(await rootBundle.load('assets/fonts/Roboto-Regular.ttf')),
        pw.Font.ttf(await rootBundle.load('assets/fonts/Roboto-Bold.ttf')),
        pw.Font.ttf(await rootBundle.load('assets/fonts/Roboto-Italic.ttf')),
      );
}
