import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import 'widgets.dart';

/// Web page -> PDF on device: fetch HTML, render it with Android's WebView print engine.
class WebScreen extends StatefulWidget {
  const WebScreen({super.key});
  @override
  State<WebScreen> createState() => _WebScreenState();
}

class _WebScreenState extends State<WebScreen> {
  final _url = TextEditingController(text: 'https://');

  static Uri? normalize(String raw) {
    var u = raw.trim();
    if (u.isEmpty || u == 'https://') return null;
    if (!u.contains('://')) u = 'https://$u';
    final uri = Uri.tryParse(u);
    return uri != null && (uri.scheme == 'http' || uri.scheme == 'https') && uri.host.contains('.') ? uri : null;
  }

  Future<void> _convert() async {
    final uri = normalize(_url.text);
    if (uri == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter a valid web address')));
      return;
    }
    FocusScope.of(context).unfocus();
    final html = await withProgress<String>(context, () async {
      final r = await Dio(BaseOptions(connectTimeout: const Duration(seconds: 15), receiveTimeout: const Duration(seconds: 30), headers: {'User-Agent': 'Mozilla/5.0 (Linux; Android 14) SmartPrint'}))
          .getUri<String>(uri, options: Options(responseType: ResponseType.plain));
      return r.data ?? '';
    }, label: 'Loading page…');
    if (html == null || !mounted) return;
    openPreview(
      context,
      // ignore: deprecated_member_use
      build: (fmt) async => Uint8List.fromList(await Printing.convertHtml(html: html, baseUrl: uri.toString(), format: fmt)),
      title: uri.host,
      kind: 'web',
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Print web page')),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          TextField(
            controller: _url,
            keyboardType: TextInputType.url,
            autocorrect: false,
            decoration: const InputDecoration(labelText: 'Web address', prefixIcon: Icon(Icons.link), border: OutlineInputBorder()),
            onSubmitted: (_) => _convert(),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(onPressed: _convert, icon: const Icon(Icons.picture_as_pdf), label: const Text('Convert to PDF')),
          const SizedBox(height: 16),
          const Text('Pages that need login or heavy JavaScript may render incomplete.',
              style: TextStyle(fontSize: 13)),
        ]),
      );
}
