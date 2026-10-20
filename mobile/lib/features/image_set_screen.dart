import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:path_provider/path_provider.dart';

import '../core/ai.dart';
import '../core/pdf_tools.dart';
import 'widgets.dart';

/// Shared editor for photos and scanned pages: reorder, crop, rotate, filters,
/// auto-enhance, N-per-sheet layouts, fit/fill, margins, OCR.
class ImageSetScreen extends StatefulWidget {
  const ImageSetScreen({super.key, required this.title, required this.kind, required this.addLabel, required this.addIcon, required this.source, this.defaultMargin = 18});
  final String title, kind, addLabel;
  final IconData addIcon;
  final double defaultMargin;

  /// Returns raw image bytes to add (camera / gallery / scanner).
  final Future<List<Uint8List>> Function(BuildContext) source;

  @override
  State<ImageSetScreen> createState() => _ImageSetScreenState();
}

class _ImageSetScreenState extends State<ImageSetScreen> {
  final List<Uint8List> _items = [];
  final List<List<Uint8List>> _undo = [];
  int _current = 0;
  int _perSheet = 1;
  bool _fill = false;
  late double _margin = widget.defaultMargin;
  bool _busy = false;

  Future<void> _add() async {
    try {
      final raw = await widget.source(context);
      if (raw.isEmpty) return;
      setState(() => _busy = true);
      for (final b in raw) {
        try {
          _items.add(await compute(ImageOps.prepare, b));
        } catch (_) {
          _snack('Skipped an unsupported image');
        }
      }
      _current = _items.isEmpty ? 0 : _items.length - 1;
    } catch (e) {
      _snack('$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String m) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _edit(Future<Uint8List?> Function(Uint8List) op, {bool all = false}) async {
    setState(() => _busy = true);
    try {
      _undo.add([..._items]);
      if (_undo.length > 10) _undo.removeAt(0);
      final idx = all ? List.generate(_items.length, (i) => i) : [_current];
      for (final i in idx) {
        final out = await op(_items[i]);
        if (out != null) _items[i] = out;
      }
    } catch (e) {
      _snack('Edit failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<Uint8List?> _crop(Uint8List bytes) async {
    final tmp = File('${(await getTemporaryDirectory()).path}/crop_${DateTime.now().microsecondsSinceEpoch}.jpg');
    await tmp.writeAsBytes(bytes);
    try {
      final c = await ImageCropper().cropImage(sourcePath: tmp.path, compressQuality: 92, uiSettings: [AndroidUiSettings(toolbarTitle: 'Crop', lockAspectRatio: false), IOSUiSettings(title: 'Crop')]);
      return await c?.readAsBytes();
    } finally {
      tmp.delete().ignore();
    }
  }

  Future<void> _ocr() async {
    final dir = await getTemporaryDirectory();
    if (!mounted) return;
    final text = await withProgress(context, () async {
      final parts = <String>[];
      for (var i = 0; i < _items.length; i++) {
        final f = File('${dir.path}/ocr_$i.jpg');
        await f.writeAsBytes(_items[i]);
        parts.add(await recognizeText(f.path));
        f.delete().ignore();
      }
      return parts.join('\n\n').trim();
    }, label: 'Recognizing text on device…');
    if (!mounted || text == null) return;
    if (text.isEmpty) return _snack('No text found');
    context.push('/ai', extra: text);
  }

  void _preview() {
    final items = List<Uint8List>.from(_items);
    final (perSheet, fill, margin) = (_perSheet, _fill, _margin);
    openPreview(context, build: (fmt) => PdfTools.imagesToPdf(items, format: fmt, perSheet: perSheet, fill: fill, margin: margin), title: '${widget.title} ${DateTime.now().toString().substring(0, 16)}', kind: widget.kind);
  }

  @override
  Widget build(BuildContext context) {
    final has = _items.isNotEmpty;
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(widget.title), actions: [
        if (_undo.isNotEmpty) IconButton(tooltip: 'Undo', onPressed: _busy ? null : () => setState(() => _items..clear()..addAll(_undo.removeLast())), icon: const Icon(Icons.undo)),
        if (has) IconButton(tooltip: 'Extract text (OCR) → AI', onPressed: _busy ? null : _ocr, icon: const Icon(Icons.text_snippet_outlined)),
        IconButton(tooltip: widget.addLabel, onPressed: _busy ? null : _add, icon: const Icon(Icons.add)),
      ]),
      body: !has
          ? Center(child: _busy ? const CircularProgressIndicator() : FilledButton.icon(onPressed: _add, icon: Icon(widget.addIcon), label: Text(widget.addLabel)))
          : Column(children: [
              Expanded(child: Stack(alignment: Alignment.center, children: [
                Padding(padding: const EdgeInsets.all(12), child: Image.memory(_items[_current.clamp(0, _items.length - 1)], fit: BoxFit.contain, gaplessPlayback: true)),
                if (_busy) const CircularProgressIndicator(),
              ])),
              SizedBox(
                height: 84,
                child: ReorderableListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  itemCount: _items.length,
                  onReorderItem: (a, b) => setState(() {
                    _items.insert(b, _items.removeAt(a));
                    _current = b;
                  }),
                  itemBuilder: (_, i) => GestureDetector(
                    key: ObjectKey(_items[i]),
                    onTap: () => setState(() => _current = i),
                    child: Container(
                      margin: const EdgeInsets.all(4),
                      decoration: BoxDecoration(border: Border.all(width: 2, color: i == _current ? cs.primary : Colors.transparent), borderRadius: BorderRadius.circular(6)),
                      child: Stack(children: [
                        Image.memory(_items[i], width: 56, height: 72, fit: BoxFit.cover, gaplessPlayback: true),
                        Positioned(left: 2, bottom: 2, child: CircleAvatar(radius: 9, child: Text('${i + 1}', style: const TextStyle(fontSize: 10)))),
                      ]),
                    ),
                  ),
                ),
              ),
              Wrap(alignment: WrapAlignment.center, children: [
                IconButton(tooltip: 'Crop', onPressed: _busy ? null : () => _edit(_crop), icon: const Icon(Icons.crop)),
                IconButton(tooltip: 'Rotate', onPressed: _busy ? null : () => _edit((b) => compute((x) => ImageOps.rotate(x, 90), b)), icon: const Icon(Icons.rotate_right)),
                IconButton(tooltip: 'Auto-enhance', onPressed: _busy ? null : () => _edit((b) => compute(ImageOps.autoEnhance, b)), icon: const Icon(Icons.auto_fix_high)),
                PopupMenuButton<(PhotoFilter, bool)>(
                  icon: const Icon(Icons.filter),
                  tooltip: 'Filters',
                  enabled: !_busy,
                  onSelected: (v) => _edit((b) => compute((x) => ImageOps.applyFilter(x, v.$1), b), all: v.$2),
                  itemBuilder: (_) => [
                    for (final f in PhotoFilter.values.skip(1)) PopupMenuItem(value: (f, false), child: Text(f.name)),
                    const PopupMenuDivider(),
                    for (final f in [PhotoFilter.document, PhotoFilter.grayscale]) PopupMenuItem(value: (f, true), child: Text('${f.name} (all pages)')),
                  ],
                ),
                IconButton(
                  tooltip: 'Delete',
                  onPressed: _busy
                      ? null
                      : () => setState(() {
                            _undo.add([..._items]);
                            _items.removeAt(_current);
                            _current = (_current - 1).clamp(0, _items.isEmpty ? 0 : _items.length - 1);
                          }),
                  icon: const Icon(Icons.delete_outline),
                ),
              ]),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                child: Row(children: [
                  const Text('Per sheet'),
                  const SizedBox(width: 8),
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: SegmentedButton<int>(
                        showSelectedIcon: false,
                        segments: [for (final n in photoLayouts.keys) ButtonSegment(value: n, label: Text('$n'))],
                        selected: {_perSheet},
                        onSelectionChanged: (s) => setState(() => _perSheet = s.first),
                      ),
                    ),
                  ),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: Row(children: [
                  FilterChip(label: const Text('Fill cell'), selected: _fill, onSelected: (v) => setState(() => _fill = v)),
                  const SizedBox(width: 8),
                  FilterChip(label: const Text('No margins'), selected: _margin == 0, onSelected: (v) => setState(() => _margin = v ? 0 : widget.defaultMargin)),
                  const Spacer(),
                  FilledButton.icon(onPressed: _busy ? null : _preview, icon: const Icon(Icons.print), label: Text('Preview (${_items.length})')),
                ]),
              ),
            ]),
    );
  }
}
