import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers.dart';

const kindIcons = {'document': Icons.description, 'photo': Icons.photo, 'web': Icons.language, 'scan': Icons.document_scanner};

class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final jobs = ref.watch(historyProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Print history'), actions: [
        if (jobs.isNotEmpty)
          IconButton(
            tooltip: 'Clear all',
            icon: const Icon(Icons.delete_sweep_outlined),
            onPressed: () async {
              final ok = await showDialog<bool>(context: context, builder: (c) => AlertDialog(title: const Text('Clear print history?'), actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Clear'))]));
              if (ok == true) await ref.read(historyProvider.notifier).clear();
            },
          ),
      ]),
      body: jobs.isEmpty
          ? const Center(child: Text('No print jobs yet'))
          : ListView.builder(
              itemCount: jobs.length,
              itemBuilder: (_, i) {
                // swipe to delete
                final j = jobs[i];
                return Dismissible(
                  key: ValueKey(j.id),
                  onDismissed: (_) => ref.read(historyProvider.notifier).remove(j.id),
                  child: ListTile(
                    leading: Icon(kindIcons[j.kind] ?? Icons.print),
                    title: Text(j.title),
                    subtitle: Text('${j.pages} page(s)${j.copies > 1 ? ' × ${j.copies}' : ''} · ${j.printer} · ${j.printedAt.toString().substring(0, 16)}'),
                  ),
                );
              },
            ),
    );
  }
}
