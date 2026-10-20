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
        IconButton(
          tooltip: 'Sync',
          icon: const Icon(Icons.cloud_sync),
          onPressed: () async {
            final m = ScaffoldMessenger.of(context);
            try {
              final n = await ref.read(historyProvider.notifier).sync();
              m.showSnackBar(SnackBar(content: Text(ref.read(sessionProvider).signedIn ? 'Synced $n job(s)' : 'Sign in to sync history')));
            } catch (e) {
              m.showSnackBar(SnackBar(content: Text('Sync failed: $e')));
            }
          },
        ),
      ]),
      body: jobs.isEmpty
          ? const Center(child: Text('No print jobs yet'))
          : ListView.builder(
              itemCount: jobs.length,
              itemBuilder: (_, i) {
                final j = jobs[i];
                return Dismissible(
                  key: ValueKey(j.id),
                  onDismissed: (_) => ref.read(historyProvider.notifier).remove(j.id),
                  child: ListTile(
                    leading: Icon(kindIcons[j.kind] ?? Icons.print),
                    title: Text(j.title),
                    subtitle: Text('${j.pages} page(s) · ${j.printer} · ${j.printedAt.toString().substring(0, 16)}'),
                    trailing: Icon(j.synced ? Icons.cloud_done : Icons.cloud_off, size: 18),
                  ),
                );
              },
            ),
    );
  }
}
