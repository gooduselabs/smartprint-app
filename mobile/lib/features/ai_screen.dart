import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../core/ai.dart';
import '../core/errors.dart';
import '../core/fonts.dart';
import '../core/office.dart';
import 'widgets.dart';

const languages = ['Vietnamese', 'English', 'Chinese', 'Japanese', 'Korean', 'French', 'Spanish', 'German'];

class AiScreen extends ConsumerStatefulWidget {
  const AiScreen({super.key, this.initialText});
  final String? initialText;
  @override
  ConsumerState<AiScreen> createState() => _AiScreenState();
}

class _AiScreenState extends ConsumerState<AiScreen> {
  late final _input = TextEditingController(text: widget.initialText ?? '');
  String _result = '';
  String _lang = 'Vietnamese';

  void _snack(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _run(Future<String> Function(AiController) f) async {
    FocusScope.of(context).unfocus();
    if (_input.text.trim().isEmpty) return _snack('Hãy nhập hoặc quét văn bản trước · Enter or scan some text first');
    if (!ref.read(aiProvider).installed) return _snack('Hãy tải model AI trước · Download the AI model first');
    try {
      final r = await f(ref.read(aiProvider.notifier));
      if (mounted) setState(() => _result = r.isEmpty ? '(no output)' : r);
    } catch (e) {
      if (mounted) _snack(friendlyError(e));
    }
  }

  Future<void> _ocr() async {
    final f = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (f == null || !mounted) return;
    final t = await withProgress(context, () => recognizeText(f.path), label: 'Đang nhận dạng chữ… · Recognizing text…');
    if (t != null && mounted) {
      if (t.trim().isEmpty) return _snack('Không tìm thấy chữ · No text found');
      setState(() => _input.text = t);
    }
  }

  Future<void> _tokenDialog() async {
    final c = TextEditingController(text: ref.read(aiProvider.notifier).hfToken);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hugging Face token (Gemma)'),
        content: TextField(controller: c, decoration: const InputDecoration(hintText: 'hf_…', helperText: 'Chỉ cần cho Gemma. Qwen miễn phí, không cần token.', helperMaxLines: 2)),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save'))],
      ),
    );
    if (ok == true) await ref.read(aiProvider.notifier).setToken(c.text);
  }

  Widget _modelCard(AiState ai) {
    final n = ref.read(aiProvider.notifier);
    final m = aiModels[ai.model];
    String mb(int b) => '${(b / (1 << 20)).round()} MB';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.memory),
            const SizedBox(width: 8),
            Expanded(
              child: DropdownButton<int>(
                isExpanded: true,
                value: ai.model,
                items: [for (var i = 0; i < aiModels.length; i++) DropdownMenuItem(value: i, child: Text('${aiModels[i].label} · ${aiModels[i].size}', overflow: TextOverflow.ellipsis))],
                onChanged: ai.downloading ? null : (v) => n.selectModel(v!),
              ),
            ),
            if (m.gated) IconButton(tooltip: 'Token', onPressed: _tokenDialog, icon: const Icon(Icons.key)),
          ]),
          Text(m.note, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 8),
          if (ai.downloading) ...[
            LinearProgressIndicator(value: ai.progress),
            const SizedBox(height: 4),
            Row(children: [
              Expanded(child: Text('${((ai.progress ?? 0) * 100).toStringAsFixed(1)}% · ${mb(ai.received)} / ${mb(ai.total)}')),
              TextButton.icon(onPressed: n.cancelDownload, icon: const Icon(Icons.pause), label: const Text('Tạm dừng · Pause')),
            ]),
          ] else if (ai.installed)
            Row(children: [
              const Icon(Icons.check_circle, color: Colors.green, size: 18),
              const SizedBox(width: 6),
              const Expanded(child: Text('Sẵn sàng, chạy offline · Ready, works offline')),
              IconButton(tooltip: 'Delete model', onPressed: n.deleteModel, icon: const Icon(Icons.delete_outline)),
            ])
          else
            Row(children: [
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: n.download,
                  icon: Icon(ai.partial ? Icons.play_arrow : Icons.download),
                  label: Text(ai.partial ? 'Tiếp tục · Resume (${mb(ai.received)})' : 'Tải model · Download (${m.size}, 1 lần)'),
                ),
              ),
              if (ai.partial) IconButton(tooltip: 'Discard', onPressed: n.deleteModel, icon: const Icon(Icons.close)),
            ]),
          if (ai.error != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(ai.error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ai = ref.watch(aiProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('AI (trên máy · on-device)')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        _modelCard(ai),
        const SizedBox(height: 12),
        TextField(
          controller: _input,
          maxLines: 8,
          minLines: 4,
          decoration: InputDecoration(
              labelText: 'Văn bản · Text (scan / paste)', border: const OutlineInputBorder(), suffixIcon: IconButton(tooltip: 'OCR from image', onPressed: _ocr, icon: const Icon(Icons.image_search))),
        ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: FilledButton.icon(onPressed: ai.busy ? null : () => _run((a) => a.summarize(_input.text)), icon: const Icon(Icons.summarize), label: const Text('Tóm tắt · Summarize'))),
          const SizedBox(width: 8),
          DropdownButton<String>(value: _lang, items: [for (final l in languages) DropdownMenuItem(value: l, child: Text(l))], onChanged: (v) => setState(() => _lang = v!)),
          IconButton.filled(tooltip: 'Translate', onPressed: ai.busy ? null : () => _run((a) => a.translate(_input.text, _lang)), icon: const Icon(Icons.translate)),
        ]),
        if (ai.busy) const Padding(padding: EdgeInsets.all(16), child: Column(children: [CircularProgressIndicator(), SizedBox(height: 8), Text('Đang xử lý trên máy… · Thinking on device…')])),
        if (_result.isNotEmpty) ...[
          const SizedBox(height: 12),
          Card(child: Padding(padding: const EdgeInsets.all(12), child: SelectableText(_result))),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            TextButton.icon(onPressed: () => Clipboard.setData(ClipboardData(text: _result)), icon: const Icon(Icons.copy), label: const Text('Copy')),
            TextButton.icon(
              onPressed: () async {
                final pdf = await OfficeConverter(await PdfFonts.load()).text(_result, title: 'AI result');
                if (context.mounted) openFixedPdf(context, pdf, title: 'AI result', kind: 'document');
              },
              icon: const Icon(Icons.print),
              label: const Text('In · Print'),
            ),
          ]),
        ],
      ]),
    );
  }
}
