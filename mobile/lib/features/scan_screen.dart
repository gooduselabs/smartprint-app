import 'dart:io';

import 'package:cunning_document_scanner/cunning_document_scanner.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_document_scanner/google_mlkit_document_scanner.dart';

import '../core/permissions.dart';
import 'image_set_screen.dart';

/// Primary: Google ML Kit Document Scanner (Play services UI; edge detection, perspective
/// crop, filters, multi-page; needs NO camera permission). Fallback for phones without the
/// Play services module: camera permission + cunning_document_scanner's built-in cropper.
Future<List<Uint8List>> scanPages(BuildContext context) async {
  try {
    final scanner = DocumentScanner(options: DocumentScannerOptions(pageLimit: 50, isGalleryImport: true, mode: ScannerMode.full, documentFormats: const {DocumentFormat.jpeg}));
    try {
      final r = await scanner.scanDocument();
      return [for (final p in r.images ?? const <String>[]) await File(p).readAsBytes()];
    } finally {
      scanner.close();
    }
  } catch (e) {
    final msg = e.toString().toLowerCase();
    if (msg.contains('cancel')) return [];
    debugPrint('ML Kit scanner unavailable, falling back: $e');
  }
  if (!context.mounted || !await ensureCamera(context)) return [];
  final paths = await CunningDocumentScanner.getPictures(scannerSource: ScannerSource.cameraAndGallery) ?? [];
  return [for (final p in paths) await File(p).readAsBytes()];
}

class ScanScreen extends StatelessWidget {
  const ScanScreen({super.key});

  @override
  Widget build(BuildContext context) => const ImageSetScreen(
        title: 'Quét · Scan',
        kind: 'scan',
        addLabel: 'Quét tài liệu · Scan pages',
        addIcon: Icons.document_scanner,
        defaultMargin: 0,
        source: scanPages,
      );
}
