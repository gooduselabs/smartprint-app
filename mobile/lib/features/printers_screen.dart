import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/ipp.dart';
import '../core/print_service.dart';

class PrintersScreen extends ConsumerStatefulWidget {
  const PrintersScreen({super.key});
  @override
  ConsumerState<PrintersScreen> createState() => _PrintersScreenState();
}

class _PrintersScreenState extends ConsumerState<PrintersScreen> {
  List<IppPrinter> _found = [];
  bool _scanning = false;

  Future<void> _discover() async {
    setState(() => _scanning = true);
    try {
      _found = await Ipp.discover();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Discovery failed: $e')));
    }
    if (mounted) setState(() => _scanning = false);
  }

  @override
  void initState() {
    super.initState();
    _discover();
  }

  @override
  Widget build(BuildContext context) {
    final sel = ref.watch(selectedIppPrinterProvider);
    void pick(IppPrinter? p) {
      ref.read(selectedIppPrinterProvider.notifier).state = p;
      Navigator.pop(context);
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Printers'), actions: [IconButton(onPressed: _scanning ? null : _discover, icon: const Icon(Icons.refresh))]),
      body: ListView(children: [
        ListTile(
          leading: const Icon(Icons.android),
          title: const Text('System print service (recommended)'),
          subtitle: const Text('Android print framework: Mopria, HP, Canon, Epson… plugins'),
          trailing: sel == null ? const Icon(Icons.check) : null,
          onTap: () => pick(null),
        ),
        const Divider(),
        ListTile(title: Text('Direct IPP printers on this WiFi'), trailing: _scanning ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : null),
        if (!_scanning && _found.isEmpty) const ListTile(subtitle: Text('None found. Make sure the phone and printer are on the same WiFi.')),
        for (final p in _found)
          ListTile(
            leading: const Icon(Icons.print),
            title: Text(p.name),
            subtitle: Text(p.uri),
            trailing: sel?.uri == p.uri ? const Icon(Icons.check) : null,
            onTap: () => pick(p),
          ),
      ]),
    );
  }
}
