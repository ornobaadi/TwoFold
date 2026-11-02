import 'package:twofold/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('app shell shows the given home screen', (tester) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('twofold/permissions'), (_) async => null);
    await tester.pumpWidget(const ProviderScope(
      child: TwoFoldApp(home: Scaffold(body: Text('Library'))),
    ));
    expect(find.text('Library'), findsOneWidget);
  });
}
