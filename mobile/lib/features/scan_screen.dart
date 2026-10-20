import 'dart:io';
import 'dart:typed_data';

import 'package:cunning_document_scanner/cunning_document_scanner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/ai.dart';
import '../core/pdf_tools.dart';
import 'widgets.dart';

/// ML Kit Document Scanner (on-device edge detection, perspective crop, multi-page).
class ScanScreen extends ConsumerStatefulWidget {
  const ScanScreen({super.key});
  @override
  ConsumerState<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends ConsumerState<ScanScreen> {
  final List<String> _pages = [];
  final Map<String, Uint8List> _enhanced = {};

  Future<void> _scan() async {
    try {
      final pics = await CunningDocumentScanner.getPictures(scannerSource: ScannerSource.cameraAndGallery);
      if (pics != null) setState(() => _pages.addAll(pics));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Scanner: $e')));
    }
  }

  Future<List<Uint8List>> _bytes() async => [for (final p in _pages) _enhanced[p] ?? await File(p).readAsBytes()];

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Document scanner'), actions: [
          if (_pages.isNotEmpty)
            IconButton(
              tooltip: 'Auto-enhance',
              icon: const Icon(Icons.auto_fix_high),
              onPressed: () => withProgress(context, () async {
                for (final p in _pages) {
                  _enhanced[p] = await autoEnhanceFile(p);
                }
                setState(() {});
              }, label: 'Enhancing…'),
            ),
          if (_pages.isNotEmpty)
            IconButton(
              tooltip: 'Extract text (OCR) & AI',
              icon: const Icon(Icons.text_snippet_outlined),
              onPressed: () async {
                final text = await withProgress(context, () async => [for (final p in _pages) await recognizeText(p)].join('\n\n'), label: 'Recognizing text…');
                if (text != null && context.mounted) context.push('/ai', extra: text);
              },
            ),
        ]),
        body: _pages.isEmpty
            ? Center(child: FilledButton.icon(onPressed: _scan, icon: const Icon(Icons.document_scanner), label: const Text('Start scanning')))
            : GridView.builder(
                padding: const EdgeInsets.all(12),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, childAspectRatio: .7, mainAxisSpacing: 8, crossAxisSpacing: 8),
                itemCount: _pages.length + 1,
                itemBuilder: (_, i) => i == _pages.length
                    ? OutlinedButton(onPressed: _scan, child: const Icon(Icons.add))
                    : Stack(fit: StackFit.expand, children: [
                        _enhanced[_pages[i]] != null ? Image.memory(_enhanced[_pages[i]]!, fit: BoxFit.cover) : Image.file(File(_pages[i]), fit: BoxFit.cover),
                        Positioned(right: 0, top: 0, child: IconButton.filledTonal(iconSize: 16, onPressed: () => setState(() => _pages.removeAt(i)), icon: const Icon(Icons.close))),
                        Positioned(left: 6, bottom: 6, child: CircleAvatar(radius: 12, child: Text('${i + 1}', style: const TextStyle(fontSize: 12)))),
                      ]),
              ),
        floatingActionButton: _pages.isEmpty
            ? null
            : FloatingActionButton.extended(
                onPressed: () async {
                  final pdf = await PdfTools.imagesToPdf(await _bytes());
                  if (context.mounted) openPreview(context, pdf, title: 'Scan ${DateTime.now().toString().substring(0, 16)}', kind: 'scan', pages: _pages.length);
                },
                icon: const Icon(Icons.picture_as_pdf),
                label: Text('PDF (${_pages.length})'),
              ),
      );
}
