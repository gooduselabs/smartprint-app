import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:smartprint/core/ai.dart';
import 'package:smartprint/core/errors.dart';
import 'package:smartprint/core/pdf_tools.dart';

void main() {
  test('isolate jobs only take sendable data', () async {
    final b = img.encodeJpg(img.Image(width: 40, height: 20));
    // Isolate.run fails with "object is unsendable" if a job captures non-sendable state.
    expect(img.decodeImage(await Isolate.run(() => rotateRightJob(b)))!.width, 20);
    expect(await Isolate.run(() => filterJob((b, PhotoFilter.document.index))), isNotEmpty);
    expect(await Isolate.run(() => autoEnhanceJob(b)), isNotEmpty);
    expect(await Isolate.run(() => prepareJob(b)), isNotEmpty);
  });

  test('friendly errors never leak stack traces', () {
    expect(friendlyError(DioException(requestOptions: RequestOptions(), response: Response(requestOptions: RequestOptions(), statusCode: 401))), contains('401'));
    expect(friendlyError(const FormatException('x')), contains('Invalid'));
    expect(friendlyError(const UserMessage('hi')), 'hi');
    expect(friendlyError(Exception('a' * 500)).length, lessThan(200));
  });

  test('models: default is ungated', () {
    expect(aiModels.first.gated, isFalse);
    expect(aiModels.first.url, startsWith('https://huggingface.co/litert-community/Qwen2.5'));
    expect(aiModels.where((m) => m.gated).every((m) => m.label.contains('Gemma')), isTrue);
  });

  test('resumable download: cancel then resume with Range', () async {
    final data = Uint8List.fromList(List.generate(3 << 20, (i) => i % 251));
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var sawRange = false;
    server.listen((req) async {
      final range = req.headers.value('range');
      var start = 0;
      if (range != null) {
        sawRange = true;
        start = int.parse(RegExp(r'bytes=(\d+)-').firstMatch(range)!.group(1)!);
        req.response.statusCode = 206;
      }
      req.response.headers.contentLength = data.length - start;
      for (var i = start; i < data.length; i += 65536) {
        req.response.add(data.sublist(i, (i + 65536).clamp(0, data.length)));
        await req.response.flush();
        await Future<void>.delayed(const Duration(milliseconds: 2));
      }
      await req.response.close();
    });
    final dir = await Directory.systemTemp.createTemp('dl');
    final dest = File('${dir.path}/m.task');
    final url = 'http://127.0.0.1:${server.port}/m.task';

    final d1 = ResumableDownload();
    await expectLater(d1.run(url, dest, onProgress: (r, t) {
      if (r > (1 << 20)) d1.cancel();
    }), throwsA(anything));
    expect(await File('${dest.path}.part').length(), greaterThan(0));

    int? lastTotal;
    await ResumableDownload().run(url, dest, onProgress: (r, t) => lastTotal = t);
    expect(sawRange, isTrue);
    expect(lastTotal, data.length);
    expect(await dest.readAsBytes(), data);
    await server.close(force: true);
  });
}
