import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smartprint/app.dart';
import 'package:smartprint/core/providers.dart';
import 'package:go_router/go_router.dart';

Future<void> _font(String family, String file) async {
  final root = Platform.environment['FLUTTER_ROOT'] ?? '/workspace/.tools/flutter';
  final f = File('$root/bin/cache/artifacts/material_fonts/$file');
  if (!f.existsSync()) return;
  final l = FontLoader(family)..addFont(Future.value(ByteData.sublistView(f.readAsBytesSync())));
  await l.load();
}

void main() {
  setUpAll(() async {
    await _font('Roboto', 'Roboto-Regular.ttf');
    await _font('MaterialIcons', 'MaterialIcons-Regular.otf');
  });

  for (final route in ['/', '/premium', '/web', '/account', '/history']) {
    testWidgets('screen $route', (tester) async {
      tester.view.physicalSize = const Size(1080, 2280);
      tester.view.devicePixelRatio = 2.625;
      SharedPreferences.setMockInitialValues({
        'history': '[{"clientId":"1","title":"Invoice-October.pdf","kind":"document","pages":3,"printer":"HP LaserJet","printedAt":"2026-10-20T08:00:00Z","synced":true},'
            '{"clientId":"2","title":"Scan 2026-10-20","kind":"scan","pages":2,"printer":"System printer","printedAt":"2026-10-20T07:00:00Z"}]'
      });
      final prefs = await SharedPreferences.getInstance();
      final c = ProviderContainer(overrides: [prefsProvider.overrideWithValue(prefs)]);
      await tester.pumpWidget(UncontrolledProviderScope(container: c, child: const SmartPrintApp()));
      if (route != '/') c.read(routerProvider).push(route);
      await tester.pumpAndSettle();
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/${route == '/' ? 'home' : route.substring(1)}.png'));
    });
  }
}

// keep import used
// ignore: unused_element
GoRouter? _r;
