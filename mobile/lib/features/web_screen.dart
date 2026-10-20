import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';

import '../core/providers.dart';
import 'widgets.dart';

class WebScreen extends ConsumerStatefulWidget {
  const WebScreen({super.key});
  @override
  ConsumerState<WebScreen> createState() => _WebScreenState();
}

class _WebScreenState extends ConsumerState<WebScreen> {
  final _url = TextEditingController(text: 'https://');
  bool _server = false;

  Future<void> _convert() async {
    var url = _url.text.trim();
    if (!url.startsWith('http')) url = 'https://$url';
    final pdf = await withProgress<Uint8List>(context, () async {
      if (_server) {
        final r = await ref.read(apiProvider).post<List<int>>('/convert/web', data: {'url': url}, options: Options(responseType: ResponseType.bytes));
        return Uint8List.fromList(r.data!);
      }
      // On-device: Android WebView renders the page to PDF.
      final html = (await Dio().get<String>(url, options: Options(responseType: ResponseType.plain))).data!;
      // ignore: deprecated_member_use
      return Printing.convertHtml(html: html, baseUrl: url);
    }, label: 'Rendering page…');
    if (pdf != null && mounted) openPreview(context, pdf, title: Uri.parse(url).host, kind: 'web');
  }

  @override
  Widget build(BuildContext context) {
    final signedIn = ref.watch(sessionProvider).signedIn;
    return Scaffold(
      appBar: AppBar(title: const Text('Print web page')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        TextField(controller: _url, keyboardType: TextInputType.url, decoration: const InputDecoration(labelText: 'Web address', prefixIcon: Icon(Icons.link), border: OutlineInputBorder()), onSubmitted: (_) => _convert()),
        SwitchListTile(
          value: _server && signedIn,
          onChanged: signedIn ? (v) => setState(() => _server = v) : null,
          title: const Text('High-fidelity (server, headless Chrome)'),
          subtitle: Text(signedIn ? 'Uses the SmartPrint server' : 'Sign in to enable'),
        ),
        const SizedBox(height: 8),
        FilledButton.icon(onPressed: _convert, icon: const Icon(Icons.picture_as_pdf), label: const Text('Convert to PDF')),
      ]),
    );
  }
}
