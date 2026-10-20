import 'dart:io';

import 'package:cunning_document_scanner/cunning_document_scanner.dart';
import 'package:flutter/material.dart';

import 'image_set_screen.dart';

/// ML Kit Document Scanner: on-device edge detection, perspective correction, multi-page.
class ScanScreen extends StatelessWidget {
  const ScanScreen({super.key});

  @override
  Widget build(BuildContext context) => ImageSetScreen(
        title: 'Scan',
        kind: 'scan',
        addLabel: 'Scan pages',
        addIcon: Icons.document_scanner,
        defaultMargin: 0,
        source: (_) async {
          final paths = await CunningDocumentScanner.getPictures(scannerSource: ScannerSource.cameraAndGallery) ?? [];
          return [for (final p in paths) await File(p).readAsBytes()];
        },
      );
}
