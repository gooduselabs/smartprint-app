import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers.dart';

/// Placeholder paywall: no real billing. "Subscribe" just flips a local flag.
class PaywallScreen extends ConsumerWidget {
  const PaywallScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final premium = ref.watch(premiumProvider);
    Widget plan(String title, String price, String note) => Card(
          child: ListTile(
            title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text(note),
            trailing: Text(price, style: Theme.of(context).textTheme.titleMedium),
            onTap: () async {
              await ref.read(premiumProvider.notifier).set(true);
              if (context.mounted) Navigator.pop(context);
            },
          ),
        );
    return Scaffold(
      appBar: AppBar(title: const Text('SmartPrint PRO')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const Icon(Icons.workspace_premium, size: 72, color: Colors.amber),
        const SizedBox(height: 8),
        for (final f in ['Unlimited printing (free: $freePrintsPerDay/day)', 'On-device AI: summarize & translate scans', 'Multi-photo layouts', 'Cloud documents & history sync'])
          ListTile(dense: true, leading: const Icon(Icons.check_circle, color: Colors.green), title: Text(f)),
        const SizedBox(height: 8),
        plan('Weekly', '\$4.99', '3-day free trial · cancel anytime'),
        plan('Yearly', '\$29.99', 'Best value'),
        const SizedBox(height: 8),
        const Text('Demo build: no payment is taken.', textAlign: TextAlign.center),
        if (premium) TextButton(onPressed: () => ref.read(premiumProvider.notifier).set(false), child: const Text('Reset to free (demo)')),
      ]),
    );
  }
}
