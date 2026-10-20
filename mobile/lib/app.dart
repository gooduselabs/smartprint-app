import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'features/account_screen.dart';
import 'features/ai_screen.dart';
import 'features/document_screen.dart';
import 'features/history_screen.dart';
import 'features/home_screen.dart';
import 'features/paywall_screen.dart';
import 'features/photo_screen.dart';
import 'features/printers_screen.dart';
import 'features/scan_screen.dart';
import 'features/web_screen.dart';

final routerProvider = Provider<GoRouter>((ref) => GoRouter(routes: [
      GoRoute(path: '/', builder: (_, _) => const HomeScreen()),
      GoRoute(path: '/document', builder: (_, _) => const DocumentScreen()),
      GoRoute(path: '/photo', builder: (_, _) => const PhotoScreen()),
      GoRoute(path: '/web', builder: (_, _) => const WebScreen()),
      GoRoute(path: '/scan', builder: (_, _) => const ScanScreen()),
      GoRoute(path: '/ai', builder: (_, s) => AiScreen(initialText: s.extra as String?)),
      GoRoute(path: '/history', builder: (_, _) => const HistoryScreen()),
      GoRoute(path: '/printers', builder: (_, _) => const PrintersScreen()),
      GoRoute(path: '/account', builder: (_, _) => const AccountScreen()),
      GoRoute(path: '/premium', builder: (_, _) => const PaywallScreen()),
    ]));

class SmartPrintApp extends ConsumerWidget {
  const SmartPrintApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = ColorScheme.fromSeed(seedColor: const Color(0xFF2962FF));
    return MaterialApp.router(
      title: 'SmartPrint',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorScheme: scheme, fontFamily: 'Roboto', useMaterial3: true, cardTheme: const CardThemeData(elevation: 0)),
      routerConfig: ref.watch(routerProvider),
    );
  }
}
