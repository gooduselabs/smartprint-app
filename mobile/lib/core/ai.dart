import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/flutter_gemma.dart' hide CancelToken;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:path_provider/path_provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'errors.dart';
import 'pdf_tools.dart';
import 'providers.dart';

/// On-device LLMs (Google AI Edge / MediaPipe LLM Inference, `.task` bundles).
/// Downloaded once with resume support, then run fully offline.
class AiModel {
  const AiModel(this.label, this.url, this.bytes, this.type, {this.gated = false, this.note = ''});
  final String label, url, note;
  final int bytes;
  final ModelType type;
  final bool gated;
  String get file => Uri.parse(url).pathSegments.last;
  String get size => bytes >= 1 << 30 ? '${(bytes / (1 << 30)).toStringAsFixed(1)} GB' : '${(bytes / (1 << 20)).round()} MB';
}

const _hf = 'https://huggingface.co/litert-community';
const aiModels = [
  // Apache-2.0, ungated: download needs no account/token. Good Vietnamese.
  AiModel('Qwen2.5 1.5B Instruct (q8)', '$_hf/Qwen2.5-1.5B-Instruct/resolve/main/Qwen2.5-1.5B-Instruct_multi-prefill-seq_q8_ekv4096.task', 1598556720, ModelType.qwen,
      note: 'Khuyên dùng · Recommended — tiếng Việt tốt'),
  AiModel('Qwen2.5 0.5B Instruct (q8)', '$_hf/Qwen2.5-0.5B-Instruct/resolve/main/Qwen2.5-0.5B-Instruct_multi-prefill-seq_q8_ekv1280.task', 546660344, ModelType.qwen,
      note: 'Nhẹ, nhanh · Light & fast (máy yếu)'),
  AiModel('Gemma 3 1B (int4)', '$_hf/Gemma3-1B-IT/resolve/main/gemma3-1b-it-int4.task', 554661243, ModelType.gemmaIt, gated: true, note: 'Cần token Hugging Face · Needs HF token'),
];

class AiState {
  const AiState({this.model = 0, this.installed = false, this.received = 0, this.total = 0, this.downloading = false, this.busy = false, this.partial = false, this.error});
  final int model, received, total;
  final bool installed, downloading, busy, partial;
  final String? error;
  double? get progress => total > 0 ? received / total : null;
  AiState copy({int? model, bool? installed, int? received, int? total, bool? downloading, bool? busy, bool? partial, String? error}) => AiState(
      model: model ?? this.model,
      installed: installed ?? this.installed,
      received: received ?? this.received,
      total: total ?? this.total,
      downloading: downloading ?? this.downloading,
      busy: busy ?? this.busy,
      partial: partial ?? this.partial,
      error: error);
}

/// Resumable HTTP download (Range requests) to `<dest>.part`, renamed on completion.
class ResumableDownload {
  CancelToken? _cancel;
  void cancel() => _cancel?.cancel('user');

  Future<void> run(String url, File dest, {String? token, required void Function(int received, int total) onProgress}) async {
    final part = File('${dest.path}.part');
    await part.parent.create(recursive: true);
    var start = await part.exists() ? await part.length() : 0;
    _cancel = CancelToken();
    final dio = Dio(BaseOptions(connectTimeout: const Duration(seconds: 20), receiveTimeout: const Duration(seconds: 60)));
    final res = await dio.get<ResponseBody>(url,
        cancelToken: _cancel,
        options: Options(responseType: ResponseType.stream, headers: {
          if (start > 0) 'Range': 'bytes=$start-',
          if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
        }));
    if (res.statusCode == 416) {
      // already complete
    } else {
      if (res.statusCode != 206) start = 0; // server ignored Range: restart
      final len = int.tryParse(res.headers.value(Headers.contentLengthHeader) ?? '') ?? 0;
      final total = len > 0 ? start + len : 0;
      final sink = part.openWrite(mode: start > 0 ? FileMode.append : FileMode.write);
      var received = start;
      try {
        await for (final chunk in res.data!.stream) {
          sink.add(chunk);
          received += chunk.length;
          onProgress(received, total);
        }
      } finally {
        await sink.flush();
        await sink.close();
      }
      if (total > 0 && received < total) throw const UserMessage('Tải chưa xong, hãy thử lại để tiếp tục · Download interrupted, tap to resume');
    }
    await part.rename(dest.path);
  }
}

class AiController extends Notifier<AiState> {
  bool _initialized = false;
  InferenceModel? _llm;
  String? _activePath;
  ResumableDownload? _dl;

  @override
  AiState build() {
    final m = (ref.read(prefsProvider).getInt('aiModel') ?? 0).clamp(0, aiModels.length - 1);
    Future.microtask(() => _refresh(m));
    return AiState(model: m);
  }

  AiModel get current => aiModels[state.model];
  String? get hfToken => ref.read(prefsProvider).getString('hfToken');
  Future<void> setToken(String t) => ref.read(prefsProvider).setString('hfToken', t.trim());

  Future<File> _fileFor(AiModel m) async => File('${(await getApplicationSupportDirectory()).path}/models/${m.file}');

  Future<void> _refresh(int m) async {
    final f = await _fileFor(aiModels[m]);
    final part = File('${f.path}.part');
    state = state.copy(installed: await f.exists(), partial: await part.exists(), received: await part.exists() ? await part.length() : 0, total: aiModels[m].bytes);
  }

  Future<void> selectModel(int m) async {
    if (state.downloading) return;
    await ref.read(prefsProvider).setInt('aiModel', m);
    await _llm?.close().catchError((_) {});
    _llm = null;
    _activePath = null;
    state = AiState(model: m);
    await _refresh(m);
  }

  Future<void> download() async {
    final m = current;
    if (m.gated && (hfToken?.isEmpty ?? true)) {
      state = state.copy(error: 'Gemma cần token Hugging Face (nút chìa khoá). Hoặc chọn Qwen — miễn phí, không cần token.');
      return;
    }
    final dest = await _fileFor(m);
    _dl = ResumableDownload();
    state = state.copy(downloading: true, error: null);
    WakelockPlus.enable().ignore();
    var lastPct = -1;
    try {
      await _dl!.run(m.url, dest, token: m.gated ? hfToken : null, onProgress: (r, t) {
        final pct = t > 0 ? r * 1000 ~/ t : r >> 22;
        if (pct != lastPct) {
          lastPct = pct;
          state = state.copy(received: r, total: t > 0 ? t : m.bytes, downloading: true);
        }
      });
      state = state.copy(installed: true, partial: false, downloading: false);
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      state = state.copy(
          downloading: false,
          partial: true,
          error: e.type == DioExceptionType.cancel
              ? 'Đã tạm dừng · Paused — bấm Tiếp tục để tải tiếp'
              : (code == 401 || code == 403)
                  ? 'Model này yêu cầu token / chấp nhận giấy phép trên Hugging Face ($code). Hãy chọn Qwen (miễn phí).'
                  : friendlyError(e));
    } catch (e) {
      state = state.copy(downloading: false, partial: true, error: friendlyError(e));
    } finally {
      WakelockPlus.disable().ignore();
      _dl = null;
      await _refresh(state.model);
    }
  }

  void cancelDownload() => _dl?.cancel();

  Future<void> deleteModel() async {
    final f = await _fileFor(current);
    await _llm?.close().catchError((_) {});
    _llm = null;
    _activePath = null;
    for (final x in [f, File('${f.path}.part')]) {
      if (await x.exists()) await x.delete();
    }
    await _refresh(state.model);
  }

  Future<String> generate(String prompt) async {
    state = state.copy(busy: true, error: null);
    try {
      final m = current;
      final f = await _fileFor(m);
      if (!await f.exists()) throw const UserMessage('Hãy tải model trước · Download the model first');
      if (!_initialized) {
        await FlutterGemma.initialize();
        _initialized = true;
      }
      if (_llm == null || _activePath != f.path) {
        await FlutterGemma.installModel(modelType: m.type).fromFile(f.path).install();
        _llm = await FlutterGemma.getActiveModel(maxTokens: m.file.contains('1280') ? 1280 : 2048, preferredBackend: PreferredBackend.cpu);
        _activePath = f.path;
      }
      final session = await _llm!.createSession(temperature: 0.3, topK: 40);
      try {
        await session.addQueryChunk(Message.text(text: prompt, isUser: true));
        final out = (await session.getResponse()).trim();
        return out.replaceAll(RegExp(r'<think>.*?</think>', dotAll: true), '').trim();
      } finally {
        await session.close();
      }
    } catch (e) {
      _llm = null;
      throw UserMessage(e is UserMessage ? e.message : 'AI lỗi: ${friendlyError(e)}');
    } finally {
      state = state.copy(busy: false);
    }
  }

  Future<String> summarize(String text) => generate(Prompts.summarize(text, maxChars: current.file.contains('1280') ? 2500 : Prompts.maxChars));
  Future<String> translate(String text, String lang) => generate(Prompts.translate(text, lang, maxChars: current.file.contains('1280') ? 2500 : Prompts.maxChars));
}

final aiProvider = NotifierProvider<AiController, AiState>(AiController.new);

class Prompts {
  static const maxChars = 5000; // keeps prompt within the KV window
  static String _clip(String t, int n) => t.length > n ? t.substring(0, n) : t;
  static String summarize(String t, {int maxChars = maxChars}) =>
      'Summarize the following scanned document in 3-6 concise bullet points, in the same language as the document.\n\n"""\n${_clip(t, maxChars)}\n"""';
  static String translate(String t, String lang, {int maxChars = maxChars}) => 'Translate the following text into $lang. Output only the translation.\n\n"""\n${_clip(t, maxChars)}\n"""';
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

Future<Uint8List> autoEnhanceFile(String path) async => compute(autoEnhanceJob, await File(path).readAsBytes());
