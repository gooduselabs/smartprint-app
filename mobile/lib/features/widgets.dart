import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

import '../core/pdf_tools.dart';
import '../core/print_service.dart';

const paperFormats = {'A4': PdfPageFormat.a4, 'Letter': PdfPageFormat.letter, 'A5': PdfPageFormat.a5, 'Legal': PdfPageFormat.legal, '4x6"': PdfPageFormat(4 * PdfPageFormat.inch, 6 * PdfPageFormat.inch)};

/// Preview with paper size / orientation (when the content can re-layout), share, and print.
class PrintPreviewScreen extends ConsumerStatefulWidget {
  const PrintPreviewScreen({super.key, required this.build, required this.title, required this.kind, this.adjustable = true});
  final PdfBuilder build;
  final String title, kind;
  final bool adjustable;
  @override
  ConsumerState<PrintPreviewScreen> createState() => _PrintPreviewScreenState();
}

class _PrintPreviewScreenState extends ConsumerState<PrintPreviewScreen> {
  int _copies = 1;
  Uint8List? _last;

  Future<Uint8List> _build(PdfPageFormat f) async => _last = await widget.build(f);

  String get _file => widget.title.toLowerCase().endsWith('.pdf') ? widget.title : '${widget.title}.pdf';

  @override
  Widget build(BuildContext context) {
    final ipp = ref.watch(selectedIppPrinterProvider);
    return Scaffold(
      appBar: AppBar(title: Text(widget.title, overflow: TextOverflow.ellipsis)),
      body: PdfPreview(
        build: _build,
        allowPrinting: false,
        allowSharing: false,
        canDebug: false,
        canChangePageFormat: widget.adjustable,
        canChangeOrientation: widget.adjustable,
        pageFormats: paperFormats,
        pdfFileName: _file,
        loadingWidget: const CircularProgressIndicator(),
        onError: (_, e) => Padding(padding: const EdgeInsets.all(24), child: Text('Could not render this file:\n$e', textAlign: TextAlign.center)),
        actions: [
          PdfPreviewAction(icon: const Icon(Icons.share), onPressed: (_, build, fmt) async => Printing.sharePdf(bytes: await build(fmt), filename: _file)),
          if (ipp != null)
            Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(onPressed: _copies > 1 ? () => setState(() => _copies--) : null, icon: const Icon(Icons.remove, color: Colors.white)),
              Text('$_copies×', style: const TextStyle(color: Colors.white)),
              IconButton(onPressed: _copies < 99 ? () => setState(() => _copies++) : null, icon: const Icon(Icons.add, color: Colors.white)),
            ]),
          PdfPreviewAction(
            icon: const Icon(Icons.print),
            onPressed: (ctx, build, fmt) async {
              final pdf = _last ?? await build(fmt);
              if (!context.mounted) return;
              await printDocument(context, ref, (f) async => widget.adjustable ? build(f) : pdf,
                  title: widget.title, kind: widget.kind, pages: PdfTools.pageCount(pdf), copies: _copies, format: fmt);
            },
          ),
        ],
      ),
    );
  }
}

void openPreview(BuildContext context, {required PdfBuilder build, required String title, required String kind, bool adjustable = true}) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => PrintPreviewScreen(build: build, title: title, kind: kind, adjustable: adjustable)));

void openFixedPdf(BuildContext context, Uint8List pdf, {required String title, required String kind}) =>
    openPreview(context, build: (_) async => pdf, title: title, kind: kind, adjustable: false);

Future<T?> withProgress<T>(BuildContext context, Future<T> Function() task, {String label = 'Working…'}) async {
  showDialog(context: context, barrierDismissible: false, builder: (_) => PopScope(canPop: false, child: AlertDialog(content: Row(children: [const CircularProgressIndicator(), const SizedBox(width: 16), Flexible(child: Text(label))]))));
  try {
    return await task();
  } catch (e) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    return null;
  } finally {
    if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
  }
}
