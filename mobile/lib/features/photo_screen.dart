import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../core/pdf_tools.dart';
import 'widgets.dart';

class PhotoScreen extends StatefulWidget {
  const PhotoScreen({super.key});
  @override
  State<PhotoScreen> createState() => _PhotoScreenState();
}

class _PhotoScreenState extends State<PhotoScreen> {
  final List<Uint8List> _photos = [];
  int _current = 0;
  int _perSheet = 1;
  bool _busy = false;

  Future<void> _pick() async {
    final files = await ImagePicker().pickMultiImage(imageQuality: 95);
    for (final f in files) {
      _photos.add(await f.readAsBytes());
    }
    setState(() {});
  }

  Future<void> _edit(Future<Uint8List?> Function(Uint8List) op) async {
    setState(() => _busy = true);
    final out = await op(_photos[_current]);
    setState(() {
      if (out != null) _photos[_current] = out;
      _busy = false;
    });
  }

  Future<Uint8List?> _crop(Uint8List bytes) async {
    final tmp = File('${(await getTemporaryDirectory()).path}/crop_${DateTime.now().microsecondsSinceEpoch}.jpg');
    await tmp.writeAsBytes(bytes);
    final c = await ImageCropper().cropImage(sourcePath: tmp.path, uiSettings: [AndroidUiSettings(toolbarTitle: 'Crop'), IOSUiSettings(title: 'Crop')]);
    return c?.readAsBytes();
  }

  @override
  Widget build(BuildContext context) {
    final has = _photos.isNotEmpty;
    return Scaffold(
      appBar: AppBar(title: const Text('Print photos'), actions: [IconButton(onPressed: _pick, icon: const Icon(Icons.add_photo_alternate))]),
      body: !has
          ? Center(child: FilledButton.icon(onPressed: _pick, icon: const Icon(Icons.photo_library), label: const Text('Choose photos')))
          : Column(children: [
              Expanded(child: Stack(alignment: Alignment.center, children: [
                Padding(padding: const EdgeInsets.all(12), child: Image.memory(_photos[_current], fit: BoxFit.contain)),
                if (_busy) const CircularProgressIndicator(),
              ])),
              SizedBox(
                height: 72,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: _photos.length,
                  itemBuilder: (_, i) => GestureDetector(
                    onTap: () => setState(() => _current = i),
                    onLongPress: () => setState(() {
                      _photos.removeAt(i);
                      _current = 0;
                    }),
                    child: Container(
                      margin: const EdgeInsets.all(4),
                      decoration: BoxDecoration(border: Border.all(width: 2, color: i == _current ? Theme.of(context).colorScheme.primary : Colors.transparent)),
                      child: Image.memory(_photos[i], width: 60, fit: BoxFit.cover),
                    ),
                  ),
                ),
              ),
              Wrap(spacing: 4, alignment: WrapAlignment.center, children: [
                IconButton(tooltip: 'Crop', onPressed: _busy ? null : () => _edit(_crop), icon: const Icon(Icons.crop)),
                IconButton(tooltip: 'Rotate', onPressed: _busy ? null : () => _edit((b) => compute((x) => ImageOps.rotate(x, 90), b)), icon: const Icon(Icons.rotate_right)),
                IconButton(tooltip: 'Auto-enhance', onPressed: _busy ? null : () => _edit((b) => compute(ImageOps.autoEnhance, b)), icon: const Icon(Icons.auto_fix_high)),
                PopupMenuButton<PhotoFilter>(
                  icon: const Icon(Icons.filter),
                  tooltip: 'Filters',
                  onSelected: (f) => _edit((b) => compute((x) => ImageOps.applyFilter(x, f), b)),
                  itemBuilder: (_) => [for (final f in PhotoFilter.values.skip(1)) PopupMenuItem(value: f, child: Text(f.name))],
                ),
              ]),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Row(children: [
                  const Text('Per sheet'),
                  const SizedBox(width: 8),
                  SegmentedButton<int>(
                    segments: const [ButtonSegment(value: 1, label: Text('1')), ButtonSegment(value: 2, label: Text('2')), ButtonSegment(value: 4, label: Text('4'))],
                    selected: {_perSheet},
                    onSelectionChanged: (s) => setState(() => _perSheet = s.first),
                  ),
                  const Spacer(),
                  FilledButton.icon(
                    onPressed: () async {
                      final pdf = await PdfTools.imagesToPdf(_photos, perSheet: _perSheet);
                      if (context.mounted) openPreview(context, pdf, title: 'Photos', kind: 'photo', pages: (_photos.length / _perSheet).ceil());
                    },
                    icon: const Icon(Icons.print),
                    label: const Text('Preview'),
                  ),
                ]),
              ),
            ]),
    );
  }
}
