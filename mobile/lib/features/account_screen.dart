import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers.dart';

class AccountScreen extends ConsumerStatefulWidget {
  const AccountScreen({super.key});
  @override
  ConsumerState<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends ConsumerState<AccountScreen> {
  final _email = TextEditingController();
  final _pass = TextEditingController();
  late final _api = TextEditingController(text: ref.read(sessionProvider).apiUrl);
  bool _busy = false;
  Map<String, dynamic>? _sub;

  Future<void> _auth(bool register) async {
    setState(() => _busy = true);
    try {
      await ref.read(sessionProvider.notifier).setApiUrl(_api.text.trim());
      await ref.read(sessionProvider.notifier).authenticate(_email.text.trim(), _pass.text, register: register);
      await ref.read(historyProvider.notifier).sync();
      await _loadSub();
    } on DioException catch (e) {
      _snack(e.response?.data is Map ? '${e.response!.data['message']}' : 'Server unreachable');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _loadSub() async {
    try {
      final r = await ref.read(apiProvider).get('/subscription');
      if (mounted) setState(() => _sub = r.data);
    } catch (_) {}
  }

  void _snack(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  @override
  void initState() {
    super.initState();
    if (ref.read(sessionProvider).signedIn) _loadSub();
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(sessionProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Account')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        if (s.signedIn) ...[
          ListTile(leading: const Icon(Icons.person), title: Text(s.email ?? ''), subtitle: Text('Plan: ${_sub?['plan'] ?? '…'} · history sync on')),
          OutlinedButton(onPressed: () => ref.read(sessionProvider.notifier).signOut(), child: const Text('Sign out')),
        ] else ...[
          const Text('Sign in to sync print history, store documents in the cloud and convert Office files. Everything else works offline.'),
          const SizedBox(height: 12),
          TextField(controller: _email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Email')),
          TextField(controller: _pass, obscureText: true, decoration: const InputDecoration(labelText: 'Password (min 8)')),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: FilledButton(onPressed: _busy ? null : () => _auth(false), child: const Text('Sign in'))),
            const SizedBox(width: 8),
            Expanded(child: OutlinedButton(onPressed: _busy ? null : () => _auth(true), child: const Text('Create account'))),
          ]),
        ],
        const Divider(height: 32),
        TextField(controller: _api, decoration: const InputDecoration(labelText: 'Server URL'), onSubmitted: (v) => ref.read(sessionProvider.notifier).setApiUrl(v.trim())),
      ]),
    );
  }
}
