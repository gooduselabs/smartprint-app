import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/print_service.dart';
import '../core/providers.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  static const tiles = [
    (Icons.description_outlined, 'Documents', 'PDF, Word, Excel, TXT', '/document', Color(0xFF2962FF)),
    (Icons.photo_outlined, 'Photos', 'Crop, rotate, filters', '/photo', Color(0xFF00897B)),
    (Icons.document_scanner_outlined, 'Scanner', 'Camera to PDF', '/scan', Color(0xFFF4511E)),
    (Icons.language, 'Web pages', 'Any URL to PDF', '/web', Color(0xFF8E24AA)),
    (Icons.auto_awesome, 'AI tools', 'OCR, summarize, translate', '/ai', Color(0xFFD81B60)),
    (Icons.history, 'History', 'Past print jobs', '/history', Color(0xFF546E7A)),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final premium = ref.watch(premiumProvider);
    final ipp = ref.watch(selectedIppPrinterProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('SmartPrint', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          if (!premium) TextButton.icon(onPressed: () => context.push('/premium'), icon: const Icon(Icons.workspace_premium, color: Colors.amber), label: const Text('PRO')),
          IconButton(onPressed: () => context.push('/account'), icon: const Icon(Icons.account_circle_outlined)),
        ],
      ),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Card(
          color: Theme.of(context).colorScheme.primaryContainer,
          child: ListTile(
            leading: const Icon(Icons.print),
            title: Text(ipp?.name ?? 'System print service'),
            subtitle: Text(ipp == null ? 'WiFi / Mopria / IPP printers via Android' : 'Direct IPP · ${ipp.host}'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/printers'),
          ),
        ),
        const SizedBox(height: 12),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.15,
          children: [
            for (final (icon, title, sub, route, color) in tiles)
              InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => context.push(route),
                child: Ink(
                  decoration: BoxDecoration(color: color.withValues(alpha: .1), borderRadius: BorderRadius.circular(16)),
                  padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    CircleAvatar(backgroundColor: color, foregroundColor: Colors.white, child: Icon(icon)),
                    const Spacer(),
                    Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    Text(sub, style: Theme.of(context).textTheme.bodySmall),
                  ]),
                ),
              ),
          ],
        ),
      ]),
    );
  }
}
