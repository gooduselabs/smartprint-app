import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:smartprint/core/fonts.dart';
import 'package:smartprint/core/office.dart';
import 'package:smartprint/core/pdf_tools.dart';

Uint8List _fx(String n) => File('test/fixtures/$n').readAsBytesSync();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late OfficeConverter conv;
  setUpAll(() async => conv = OfficeConverter(await PdfFonts.load()));

  Future<Uint8List> run(String ext, Uint8List b) async {
    final pdf = await conv.convert(ext, b, title: 'sample.$ext');
    expect(String.fromCharCodes(pdf.sublist(0, 5)), '%PDF-');
    final out = Platform.environment['OFFICE_OUT'];
    if (out != null) File('$out/sample.$ext.pdf').writeAsBytesSync(pdf);
    return pdf;
  }

  test('DOCX: text, styles, list, table, image, page break', () async {
    final pdf = await run('docx', _fx('sample.docx'));
    expect(PdfTools.pageCount(pdf), 2); // explicit page break
  });

  test('XLSX: sheets and cells', () async {
    final sheets = OfficeConverter.readXlsx(_fx('sample.xlsx'));
    expect(sheets.map((s) => s.$1), ['Doanh thu', 'Trống']);
    final g = sheets.first.$2;
    expect(g[0], ['Tháng', 'Số tiền']);
    expect(g[1][1], '1500.5');
    expect(g[2][1], '2000');
    expect(g[4][3], 'xa');
    expect(PdfTools.pageCount(await run('xlsx', _fx('sample.xlsx'))), 2);
  });

  test('PPTX: one page per slide', () async {
    expect(PdfTools.pageCount(await run('pptx', _fx('sample.pptx'))), 2);
  });

  test('CSV with quotes and TXT', () async {
    await run('csv', Uint8List.fromList('a,"b, c","say ""hi"""\n1,2,3'.codeUnits));
    await run('txt', Uint8List.fromList(utf8.encode('Xin chào\n\nthế giới')));
  });

  test('rejects garbage and legacy formats', () async {
    await expectLater(conv.convert('docx', Uint8List.fromList([1, 2, 3])), throwsFormatException);
    await expectLater(() => conv.convert('doc', Uint8List(4)), throwsUnsupportedError);
  });
}
