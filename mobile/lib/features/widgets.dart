import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';

import '../core/print_service.dart';

/// PDF preview with share + our print path (system or direct IPP).
class PdfPrintPreview extends ConsumerWidget {
  const PdfPrintPreview({super.key, required this.pdf, required this.title, required this.kind, this.pages = 1});
  final Uint8List pdf;
  final String title, kind;
  final int pages;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
        appBar: AppBar(title: Text(title, overflow: TextOverflow.ellipsis), actions: [
          IconButton(icon: const Icon(Icons.share), onPressed: () => Printing.sharePdf(bytes: pdf, filename: title.endsWith('.pdf') ? title : '$title.pdf')),
        ]),
        body: PdfPreview(build: (_) async => pdf, useActions: false, canChangePageFormat: false),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => printPdf(context, ref, pdf, title: title, kind: kind, pages: pages),
          icon: const Icon(Icons.print),
          label: const Text('Print'),
        ),
      );
}

void openPreview(BuildContext context, Uint8List pdf, {required String title, required String kind, int pages = 1}) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => PdfPrintPreview(pdf: pdf, title: title, kind: kind, pages: pages)));

Future<T?> withProgress<T>(BuildContext context, Future<T> Function() task, {String label = 'Working…'}) async {
  showDialog(context: context, barrierDismissible: false, builder: (_) => AlertDialog(content: Row(children: [const CircularProgressIndicator(), const SizedBox(width: 16), Flexible(child: Text(label))])));
  try {
    return await task();
  } catch (e) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    return null;
  } finally {
    if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
  }
}
