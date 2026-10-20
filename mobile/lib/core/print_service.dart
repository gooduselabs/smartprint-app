import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

import 'errors.dart';
import 'ipp.dart';
import 'providers.dart';

final selectedIppPrinterProvider = StateProvider<IppPrinter?>((_) => null);

typedef PdfBuilder = Future<Uint8List> Function(PdfPageFormat format);

/// Prints via the Android print framework (Mopria / IPP / vendor plugins; paper, copies,
/// pages and colour are chosen in the system dialog) or straight to a discovered IPP printer.
Future<bool> printDocument(BuildContext context, WidgetRef ref, PdfBuilder build, {required String title, required String kind, int pages = 1, int copies = 1, PdfPageFormat format = PdfPageFormat.a4}) async {
  final ipp = ref.read(selectedIppPrinterProvider);
  final messenger = ScaffoldMessenger.of(context);
  try {
    var ok = false;
    String printer;
    if (ipp != null) {
      final status = await Ipp.printPdf(ipp, await build(format), jobName: title, copies: copies);
      ok = status < 0x0100;
      printer = ipp.name;
      if (!ok) messenger.showSnackBar(SnackBar(content: Text('Printer refused the job (IPP 0x${status.toRadixString(16)})')));
    } else {
      ok = await Printing.layoutPdf(onLayout: build, name: title, format: format);
      printer = 'System printer';
    }
    if (ok) {
      await ref.read(historyProvider.notifier).add(title: title, kind: kind, pages: pages, printer: printer, copies: copies);
      messenger.showSnackBar(SnackBar(content: Text('Sent "$title" to $printer')));
    }
    return ok;
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(ipp != null ? 'Không kết nối được ${ipp.name} · ${friendlyError(e)}' : 'In thất bại · Print failed: ${friendlyError(e)}')));
    return false;
  }
}
