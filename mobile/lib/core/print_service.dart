import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:go_router/go_router.dart';
import 'package:printing/printing.dart';

import 'ipp.dart';
import 'providers.dart';

final selectedIppPrinterProvider = StateProvider<IppPrinter?>((_) => null);

/// Prints via the Android print framework (covers Mopria/IPP/vendor plugins),
/// or straight to a discovered IPP printer when one is selected.
Future<void> printPdf(BuildContext context, WidgetRef ref, Uint8List pdf, {required String title, required String kind, int pages = 1}) async {
  final history = ref.read(historyProvider.notifier);
  if (!ref.read(premiumProvider) && history.todayCount >= freePrintsPerDay) {
    context.push('/premium');
    return;
  }
  final ipp = ref.read(selectedIppPrinterProvider);
  final messenger = ScaffoldMessenger.of(context);
  try {
    bool ok;
    String printer;
    if (ipp != null) {
      final status = await Ipp.printPdf(ipp, pdf, jobName: title);
      ok = status < 0x0100;
      printer = ipp.name;
      if (!ok) messenger.showSnackBar(SnackBar(content: Text('Printer error 0x${status.toRadixString(16)}')));
    } else {
      ok = await Printing.layoutPdf(onLayout: (_) async => pdf, name: title);
      printer = 'System printer';
    }
    if (ok) {
      await history.add(title: title, kind: kind, pages: pages, printer: printer);
      messenger.showSnackBar(SnackBar(content: Text('Sent "$title" to $printer')));
    }
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('Print failed: $e')));
  }
}
