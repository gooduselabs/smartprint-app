import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import 'pdf_tools.dart';
import 'providers.dart';

/// On-device models (Google AI Edge / MediaPipe LLM Inference). Downloaded on first use.
class AiModel {
  const AiModel(this.label, this.url, this.sizeMb);
  final String label, url;
  final int sizeMb;
  String get file => url.split('/').last;
}

const aiModels = [
  AiModel('Gemma 3 1B (int4)', 'https://huggingface.co/litert-community/Gemma3-1B-IT/resolve/main/gemma3-1b-it-int4.task', 555),
  AiModel('Gemma 3n E2B (int4)', 'https://huggingface.co/google/gemma-3n-E2B-it-litert-preview/resolve/main/gemma-3n-E2B-it-int4.task', 3100),
];

class AiState {
  const AiState({this.model = 0, this.installed = false, this.progress, this.busy = false, this.error});
  final int model;
  final bool installed, busy;
  final int? progress;
  final String? error;
  AiState copy({int? model, bool? installed, int? progress, bool clearProgress = false, bool? busy, String? error}) =>
      AiState(model: model ?? this.model, installed: installed ?? this.installed, progress: clearProgress ? null : progress ?? this.progress, busy: busy ?? this.busy, error: error);
}

class AiController extends Notifier<AiState> {
  bool _initialized = false;
  InferenceModel? _llm;

  @override
  AiState build() {
    final m = ref.read(prefsProvider).getInt('aiModel') ?? 0;
    _check(m);
    return AiState(model: m);
  }

  String? get hfToken => ref.read(prefsProvider).getString('hfToken');

  Future<void> setToken(String t) => ref.read(prefsProvider).setString('hfToken', t.trim());

  Future<void> _init() async {
    if (_initialized) return;
    await FlutterGemma.initialize(huggingFaceToken: (hfToken?.isEmpty ?? true) ? null : hfToken);
    _initialized = true;
  }

  Future<void> _check(int m) async {
    try {
      await _init();
      final ok = await FlutterGemma.isModelInstalled(aiModels[m].file);
      state = state.copy(installed: ok);
    } catch (_) {}
  }

  Future<void> selectModel(int m) async {
    await ref.read(prefsProvider).setInt('aiModel', m);
    await _llm?.close();
    _llm = null;
    state = AiState(model: m);
    await _check(m);
  }

  /// Downloads (first time) and activates the model.
  Future<void> install() async {
    final m = aiModels[state.model];
    state = state.copy(progress: 0, error: null);
    try {
      await _init();
      await FlutterGemma.installModel(modelType: ModelType.gemmaIt)
          .fromNetwork(m.url, token: (hfToken?.isEmpty ?? true) ? null : hfToken)
          .withProgress((p) => state = state.copy(progress: p))
          .install();
      state = state.copy(installed: true, clearProgress: true);
    } catch (e) {
      state = state.copy(clearProgress: true, error: 'Download failed (Gemma models are gated: accept the license on Hugging Face and set a token). $e');
    }
  }

  Future<String> generate(String prompt) async {
    state = state.copy(busy: true, error: null);
    try {
      if (_llm == null) {
        await install(); // no-op download when already on disk; re-activates after restart
        _llm = await FlutterGemma.getActiveModel(maxTokens: 2048, preferredBackend: PreferredBackend.gpu);
      }
      final session = await _llm!.createSession(temperature: 0.3, topK: 40);
      try {
        await session.addQueryChunk(Message.text(text: prompt, isUser: true));
        return (await session.getResponse()).trim();
      } finally {
        await session.close();
      }
    } finally {
      state = state.copy(busy: false);
    }
  }

  Future<String> summarize(String text) => generate(Prompts.summarize(text));
  Future<String> translate(String text, String lang) => generate(Prompts.translate(text, lang));
}

final aiProvider = NotifierProvider<AiController, AiState>(AiController.new);

class Prompts {
  static const maxChars = 6000; // keeps prompt within the 2048-token window for 1B models
  static String _clip(String t) => t.length > maxChars ? t.substring(0, maxChars) : t;
  static String summarize(String t) => 'Summarize the following scanned document in 3-6 concise bullet points, in the same language as the document.\n\n"""\n${_clip(t)}\n"""';
  static String translate(String t, String lang) => 'Translate the following text into $lang. Output only the translation.\n\n"""\n${_clip(t)}\n"""';
}

/// ML Kit on-device OCR (Latin script; covers Vietnamese diacritics).
Future<String> recognizeText(String imagePath) async {
  final r = TextRecognizer(script: TextRecognitionScript.latin);
  try {
    return (await r.processImage(InputImage.fromFilePath(imagePath))).text;
  } finally {
    await r.close();
  }
}

Future<Uint8List> autoEnhanceFile(String path) async {
  final bytes = await File(path).readAsBytes();
  return compute(ImageOps.autoEnhance, bytes);
}
