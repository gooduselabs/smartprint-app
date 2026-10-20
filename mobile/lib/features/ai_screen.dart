import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../core/ai.dart';
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

  Future<void> _run(Future<String> Function(AiController) f) async {
    if (_input.text.trim().isEmpty) return;
    try {
      final r = await f(ref.read(aiProvider.notifier));
      setState(() => _result = r);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('AI error: $e')));
    }
  }

  Future<void> _ocr() async {
    final f = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (f == null || !mounted) return;
    final t = await withProgress(context, () => recognizeText(f.path), label: 'Recognizing text…');
    if (t != null) setState(() => _input.text = t);
  }

  Future<void> _tokenDialog() async {
    final c = TextEditingController(text: ref.read(aiProvider.notifier).hfToken);
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Hugging Face token'),
        content: TextField(controller: c, decoration: const InputDecoration(hintText: 'hf_…', helperText: 'Gemma is gated: accept its license on huggingface.co first.')),
        actions: [TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save'))],
      ),
    );
    if (ok == true) await ref.read(aiProvider.notifier).setToken(c.text);
  }

  @override
  Widget build(BuildContext context) {
    final ai = ref.watch(aiProvider);
    final model = aiModels[ai.model];
    return Scaffold(
      appBar: AppBar(title: const Text('AI tools (on-device)'), actions: [IconButton(tooltip: 'Model token', onPressed: _tokenDialog, icon: const Icon(Icons.key))]),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Card(
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
                    items: [for (var i = 0; i < aiModels.length; i++) DropdownMenuItem(value: i, child: Text('${aiModels[i].label} · ${aiModels[i].sizeMb} MB'))],
                    onChanged: ai.progress != null ? null : (v) => ref.read(aiProvider.notifier).selectModel(v!),
                  ),
                ),
              ]),
              if (ai.progress != null) ...[LinearProgressIndicator(value: ai.progress! / 100), Text('Downloading ${model.label}: ${ai.progress}%')]
              else if (!ai.installed)
                FilledButton.tonalIcon(onPressed: () => ref.read(aiProvider.notifier).install(), icon: const Icon(Icons.download), label: Text('Download model (${model.sizeMb} MB, once)'))
              else
                const Text('✓ Model ready — runs fully offline (Google AI Edge / MediaPipe)'),
              if (ai.error != null) Text(ai.error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ]),
          ),
        ),
        const SizedBox(height: 12),
        TextField(controller: _input, maxLines: 8, decoration: InputDecoration(labelText: 'Text (from scan or paste)', border: const OutlineInputBorder(), suffixIcon: IconButton(tooltip: 'OCR from image', onPressed: _ocr, icon: const Icon(Icons.image_search)))),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: FilledButton.icon(onPressed: ai.busy ? null : () => _run((a) => a.summarize(_input.text)), icon: const Icon(Icons.summarize), label: const Text('Summarize'))),
          const SizedBox(width: 8),
          DropdownButton<String>(value: _lang, items: [for (final l in languages) DropdownMenuItem(value: l, child: Text(l))], onChanged: (v) => setState(() => _lang = v!)),
          IconButton.filled(tooltip: 'Translate', onPressed: ai.busy ? null : () => _run((a) => a.translate(_input.text, _lang)), icon: const Icon(Icons.translate)),
        ]),
        if (ai.busy) const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator())),
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
              label: const Text('Print'),
            ),
          ]),
        ],
      ]),
    );
  }
}
