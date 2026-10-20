import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/fonts.dart';
import '../core/office.dart';
import '../core/pdf_tools.dart';
import 'widgets.dart';

const imageExt = ['jpg', 'jpeg', 'png', 'webp', 'gif', 'bmp'];

class DocumentScreen extends StatelessWidget {
  const DocumentScreen({super.key});

  Future<void> _pick(BuildContext context) async {
    final res = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['pdf', ...OfficeConverter.supported, ...imageExt]);
    if (res.isEmpty || !context.mounted) return;
    final f = res.single;
    final ext = (f.extension ?? '').toLowerCase().replaceFirst('.', '');
    final name = f.name;
    final bytes = await withProgress(context, f.readAsBytes, label: 'Opening…');
    if (bytes == null || !context.mounted) return;
    if (ext == 'pdf') {
      if (bytes.length < 5 || String.fromCharCodes(bytes.sublist(0, 5)) != '%PDF-') {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('This file is not a valid PDF')));
        return;
      }
      openFixedPdf(context, bytes, title: name, kind: 'document');
    } else if (imageExt.contains(ext)) {
      final img = await withProgress(context, () => compute(ImageOps.prepare, bytes), label: 'Preparing image…');
      if (img != null && context.mounted) openPreview(context, build: (fmt) => PdfTools.imagesToPdf([img], format: fmt), title: name, kind: 'photo');
    } else {
      // On-device Office/CSV/TXT conversion (A4 pages, or the slide size for PPTX).
      final fonts = await PdfFonts.load();
      if (!context.mounted) return;
      final pdf = await withProgress(context, () => OfficeConverter(fonts).convert(ext, bytes, title: name), label: 'Converting $ext to PDF on device…');
      if (pdf != null && context.mounted) openFixedPdf(context, pdf, title: name, kind: 'document');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Print documents')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.upload_file, size: 72),
              const SizedBox(height: 12),
              const Text('PDF · Word (DOCX) · Excel (XLSX) · PowerPoint (PPTX) · CSV · TXT · images', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              const Text('Everything is converted on this phone, nothing is uploaded. Office layouts are approximated — for pixel-perfect output export to PDF first.',
                  textAlign: TextAlign.center, style: TextStyle(fontSize: 13)),
              const SizedBox(height: 24),
              FilledButton.icon(onPressed: () => _pick(context), icon: const Icon(Icons.folder_open), label: const Text('Choose file (device, Drive, email…)')),
            ]),
          ),
        ),
      );
}
