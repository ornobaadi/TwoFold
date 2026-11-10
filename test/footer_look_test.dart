import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twofold/app/theme.dart';
import 'package:twofold/features/settings/settings_screen.dart';

/// The Settings sign-off in each background. LOOK=1 writes PNGs.
void main() {
  for (final theme in [ReaderTheme.paper, ReaderTheme.night]) {
    testWidgets('signature footer, ${theme.name}', (tester) async {
      await tester.runAsync(() async {
        for (final (family, path) in [
          ('Inter', 'assets/fonts/Inter.ttf'),
          ('Literata', 'assets/fonts/Literata.ttf'),
        ]) {
          final bytes = File(path).readAsBytesSync();
          await (FontLoader(family)
                ..addFont(Future.value(ByteData.sublistView(bytes))))
              .load();
        }
      });
      tester.view.physicalSize = const Size(1080, 1100);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildTheme(theme, AppPalette.indigo),
        home: const Scaffold(body: Center(child: MadeBy())),
      ));
      await tester.runAsync(() => precacheImage(
          const AssetImage('assets/brand/signature.png'),
          tester.element(find.byType(MadeBy))));
      await tester.pump();
      expect(find.text('HANDCRAFTED BY'), findsOneWidget);
      expect(find.text('TWOFOLD  •  VERSION $appVersion'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('Handcrafted by Ornob Aadi')),
          findsOneWidget);
      if (Platform.environment['LOOK'] == '1') {
        await expectLater(find.byType(MaterialApp),
            matchesGoldenFile('../build/look/${theme.name}_footer.png'));
      }
    });
  }
}
