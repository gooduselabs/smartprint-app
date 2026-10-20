import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smartprint/core/ipp.dart';
import 'package:smartprint/core/pdf_tools.dart';
import 'package:smartprint/core/providers.dart';
import 'package:smartprint/core/ai.dart';
import 'package:pdf/pdf.dart';

Uint8List _jpg(int w, int h) => img.encodeJpg(img.Image(width: w, height: h)..clear(img.ColorRgb8(200, 100, 50)));

void main() {
  test('IPP Print-Job encoding', () {
    final pdf = Uint8List.fromList('%PDF-1.4'.codeUnits);
    final b = Ipp.buildPrintJob('ipp://10.0.0.5:631/ipp/print', pdf, copies: 2, requestId: 7);
    expect(b.sublist(0, 8), [1, 1, 0, 2, 0, 0, 0, 7]);
    expect(b[8], 0x01);
    expect(String.fromCharCodes(b), contains('printer-uri'));
    expect(String.fromCharCodes(b), contains('application/pdf'));
    expect(String.fromCharCodes(b), contains('copies'));
    expect(b.sublist(b.length - pdf.length), pdf);
    expect(b[b.length - pdf.length - 1], 0x03);
  });

  test('image ops keep dimensions / rotate swaps', () {
    final src = _jpg(40, 20);
    final r = img.decodeImage(ImageOps.rotate(src, 90))!;
    expect([r.width, r.height], [20, 40]);
    for (final f in PhotoFilter.values) {
      expect(img.decodeImage(ImageOps.applyFilter(src, f))!.width, 40);
    }
    expect(img.decodeImage(ImageOps.autoEnhance(src))!.height, 20);
  });

  test('images to PDF with N per sheet', () async {
    final pdf = await PdfTools.imagesToPdf(List.generate(5, (_) => _jpg(30, 30)), perSheet: 4);
    final s = String.fromCharCodes(pdf);
    expect(s.startsWith('%PDF'), isTrue);
    expect(s, contains('/Count 2'));
  });

  test('prompts are clipped', () {
    expect(Prompts.summarize('x' * 10000).length, lessThan(Prompts.maxChars + 300));
    expect(Prompts.translate('hi', 'Vietnamese'), contains('Vietnamese'));
  });

  test('history survives corrupted storage and clears', () async {
    SharedPreferences.setMockInitialValues({'history': '{not json'});
    final prefs = await SharedPreferences.getInstance();
    final c = ProviderContainer(overrides: [prefsProvider.overrideWithValue(prefs)]);
    expect(c.read(historyProvider), isEmpty);
    await c.read(historyProvider.notifier).add(title: 'x', kind: 'scan', pages: 1, printer: 'P', copies: 3);
    expect(c.read(historyProvider).single.copies, 3);
    await c.read(historyProvider.notifier).clear();
    expect(c.read(historyProvider), isEmpty);
  });

  test('photo layouts: 9 per sheet, landscape, fill', () async {
    final pdf = await PdfTools.imagesToPdf(List.generate(10, (_) => _jpg(30, 40)), perSheet: 9, fill: true, format: PdfPageFormat.a4.landscape);
    expect(PdfTools.pageCount(pdf), 2);
    expect(PdfTools.pageCount(await PdfTools.imagesToPdf([], perSheet: 6)), 1);
  });

  test('prepare downsizes huge images', () {
    final big = img.encodeJpg(img.Image(width: 5000, height: 1000));
    final out = img.decodeImage(ImageOps.prepare(big))!;
    expect(out.width, ImageOps.maxSide);
    expect(() => ImageOps.prepare(Uint8List.fromList([1, 2, 3])), throwsA(anything));
  });

  test('history persists and counts today', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final c = ProviderContainer(overrides: [prefsProvider.overrideWithValue(prefs)]);
    await c.read(historyProvider.notifier).add(title: 'a.pdf', kind: 'document', pages: 2, printer: 'X');
    expect(c.read(historyProvider).length, 1);
    final c2 = ProviderContainer(overrides: [prefsProvider.overrideWithValue(prefs)]);
    expect(c2.read(historyProvider).single.title, 'a.pdf');
  });
}
