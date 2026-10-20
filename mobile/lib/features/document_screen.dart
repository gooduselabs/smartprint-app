import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:printing/printing.dart';

import '../core/pdf_tools.dart';
import '../core/providers.dart';
import 'widgets.dart';

const officeExt = ['doc', 'docx', 'odt', 'rtf', 'xls', 'xlsx', 'ods', 'csv', 'ppt', 'pptx', 'odp'];
const imageExt = ['jpg', 'jpeg', 'png', 'webp', 'gif', 'bmp'];

class DocumentScreen extends ConsumerWidget {
  const DocumentScreen({super.key});

  Future<void> _pick(BuildContext context, WidgetRef ref) async {
    final res = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['pdf', 'txt', ...officeExt, ...imageExt]);
    if (res.isEmpty || !context.mounted) return;
    final f = res.single;
    final bytes = await f.readAsBytes();
    if (!context.mounted) return;
    final ext = (f.extension ?? '').toLowerCase();
    final pdf = await withProgress<Uint8List>(context, () async {
      if (ext == 'pdf') return bytes;
      if (imageExt.contains(ext)) return PdfTools.imagesToPdf([bytes]);
      if (ext == 'txt') return PdfTools.textToPdf(f.name, String.fromCharCodes(bytes), font: await PdfGoogleFonts.notoSansRegular());
      // Office files: converted to PDF by the backend (LibreOffice headless).
      if (!ref.read(sessionProvider).signedIn) throw 'Sign in (Account) to convert Office files';
      final r = await ref.read(apiProvider).post<List<int>>('/convert/office',
          data: FormData.fromMap({'file': MultipartFile.fromBytes(bytes, filename: f.name)}), options: Options(responseType: ResponseType.bytes));
      return Uint8List.fromList(r.data!);
    }, label: ext == 'pdf' ? 'Opening…' : 'Converting to PDF…');
    if (pdf != null && context.mounted) {
      var pages = 1;
      await for (final _ in Printing.raster(pdf, dpi: 1)) {
        pages++;
      }
      if (context.mounted) openPreview(context, pdf, title: f.name, kind: 'document', pages: pages - 1);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
        appBar: AppBar(title: const Text('Print documents')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.upload_file, size: 72),
              const SizedBox(height: 12),
              const Text('PDF, images and TXT are handled on-device.\nWord, Excel, PowerPoint are converted by the SmartPrint server.', textAlign: TextAlign.center),
              const SizedBox(height: 24),
              FilledButton.icon(onPressed: () => _pick(context, ref), icon: const Icon(Icons.folder_open), label: const Text('Choose file (device, Drive, email…)')),
              const SizedBox(height: 8),
              if (!ref.watch(sessionProvider).signedIn) TextButton(onPressed: () => context.push('/account'), child: const Text('Sign in for Office conversion')),
            ]),
          ),
        ),
      );
}

