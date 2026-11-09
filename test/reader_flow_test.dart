import 'dart:io';

import 'package:twofold/app/theme.dart';
import 'package:twofold/audio/audio_handler.dart';
import 'package:twofold/audio/player_controller.dart';
import 'package:twofold/data/book_repo.dart';
import 'package:twofold/data/db.dart';
import 'package:twofold/data/models.dart';
import 'package:twofold/features/reader/epub_book.dart';
import 'package:twofold/features/reader/epub_view.dart';
import 'package:twofold/features/reader/pane.dart';
import 'package:twofold/features/reader/pdf_view.dart';
import 'package:twofold/features/reader/reader_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _alice = 'test/fixtures/alice.epub';
const _pdf = 'test/fixtures/sample.pdf';

Book _book(String format, String path) => Book(
    id: 'b', title: 'Test', format: format, filePath: path, addedAt: 1);

class _Log {
  String label = '';
  String location = '';
  int centerTaps = 0;
  bool ready = false;
  String? error;
  List<TocItem> contents = const [];

  PaneCallbacks get callbacks => PaneCallbacks(
        onCenterTap: () => centerTaps++,
        onLocation: (l, loc, _) {
          label = l;
          location = loc;
        },
        onContents: (c) => contents = c,
        onReady: () => ready = true,
        onError: (e) => error = e,
      );
}

Widget _host(Widget child) => ProviderScope(
      child: MaterialApp(
        theme: buildTheme(ReaderTheme.paper),
        home: Scaffold(body: child),
      ),
    );

Future<void> _settle(WidgetTester tester, bool Function() done) async {
  for (var i = 0; i < 100 && !done(); i++) {
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump(const Duration(milliseconds: 50));
  }
  await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)));
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  sqfliteFfiInit();

  test('a real EPUB loads through the background isolate', () async {
    final doc = await loadEpubFile(_alice);
    expect(doc.blocks.length, greaterThan(100));
    expect(doc.toc, isNotEmpty);
    final all = doc.blocks.expand((b) => b.runs).map((r) => r.text).join();
    expect(all, contains('Alice'));
  });

  testWidgets('real EPUB: opens, swipes, taps, restores', (tester) async {
    final log = _Log();
    await tester.pumpWidget(_host(EpubPane(
        book: _book('epub', _alice), saved: null, callbacks: log.callbacks)));
    await _settle(tester, () => log.ready);

    expect(log.error, isNull);
    expect(log.ready, isTrue);
    expect(log.label, startsWith('1 / '));
    await tester.drag(find.byType(PageView), const Offset(-500, 0));
    await tester.pumpAndSettle();
    expect(log.label, startsWith('2 / '));
    expect(find.byType(RichText), findsWidgets);

    final width = tester.getSize(find.byType(PageView)).width;
    await tester.tapAt(Offset(width * 0.9, 300));
    await tester.pumpAndSettle();
    expect(log.label, startsWith('3 / '));

    await tester.tapAt(Offset(width * 0.1, 300));
    await tester.pumpAndSettle();
    expect(log.label, startsWith('2 / '));

    await tester.tapAt(Offset(width * 0.5, 300));
    await tester.pump();
    expect(log.centerTaps, 1);
    expect(log.label, startsWith('2 / '), reason: 'centre tap keeps the page');

    final saved = log.location;
    final label = log.label;
    await tester.pumpWidget(const SizedBox());
    final again = _Log();
    await tester.pumpWidget(_host(EpubPane(
      book: _book('epub', _alice),
      saved: Progress(bookId: 'b', readLocation: saved, updatedAt: 1),
      callbacks: again.callbacks,
    )));
    await _settle(tester, () => again.ready);
    expect(again.label, label);
  });

  testWidgets('real EPUB: drawn text never overlaps or leaves the page',
      (tester) async {
    final log = _Log();
    await tester.pumpWidget(_host(EpubPane(
        book: _book('epub', _alice), saved: null, callbacks: log.callbacks)));
    await _settle(tester, () => log.ready);

    for (var turn = 0; turn < 60; turn++) {
      final page = find.byType(EpubPage);
      final view = tester.getRect(find.byType(PageView));
      final rects = [
        for (final e in find
            .descendant(of: page, matching: find.byType(RichText))
            .evaluate())
          tester.getRect(find.byWidget(e.widget)),
      ]..sort((a, b) => a.top.compareTo(b.top));
      for (var i = 0; i < rects.length; i++) {
        // The page's text area stops 8 dp above the view.
        expect(rects[i].bottom, lessThanOrEqualTo(view.bottom - 8),
            reason: 'turn $turn: leaves the page');
        if (i > 0) {
          expect(rects[i].top, greaterThanOrEqualTo(rects[i - 1].bottom - 0.5),
              reason: 'turn $turn: lines overlap');
        }
      }
      await tester.drag(find.byType(PageView), const Offset(-500, 0));
      await tester.pumpAndSettle();
    }
  });

  testWidgets('real PDF: opens and centre tap works', (tester) async {
    final tmp = Directory.systemTemp.createTempSync('twofold').path;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (_) async => tmp);
    final log = _Log();
    await tester.pumpWidget(_host(PdfPane(
        book: _book('pdf', _pdf), saved: null, callbacks: log.callbacks)));
    await _settle(tester, () => log.ready || log.error != null);
    expect(log.error, isNull);
    expect(log.label, '1 / 1');

    final width = tester.getSize(find.byType(PageView)).width;
    await tester.tapAt(Offset(width * 0.5, 300));
    await tester.pump();
    expect(log.centerTaps, 1);
    await tester.pumpWidget(const SizedBox());

    // Page turns, on a longer document, restored at a saved page.
    final many = _Log();
    await tester.pumpWidget(_host(PdfPane(
      book: _book('pdf', 'test/fixtures/five_pages.pdf'),
      saved: const Progress(bookId: 'b', readLocation: '2', updatedAt: 1),
      callbacks: many.callbacks,
    )));
    await _settle(tester, () => many.ready || many.error != null);
    expect(many.error, isNull);
    expect(many.label, '2 / 5');

    await tester.drag(find.byType(PageView), const Offset(-500, 0));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(many.label, '3 / 5');
    expect(find.byType(PdfPageView), findsWidgets, reason: 'pages stay on screen');
    // Let the swipe finish settling before the next touch.
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)));
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    await tester.tapAt(Offset(width * 0.9, 300));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(many.label, '4 / 5');

    await tester.tapAt(Offset(width * 0.1, 300));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(many.label, '3 / 5');

    await tester.tapAt(Offset(width * 0.5, 300));
    await tester.pump();
    expect(many.centerTaps, 1);
    expect(many.label, '3 / 5');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('reader screen: controls show on open, footer is full width',
      (tester) async {
    final db = (await tester.runAsync(() => openTwoFoldDb(
        path: inMemoryDatabasePath, factory: databaseFactoryFfi)))!;
    final repo = BookRepo(db);
    final book = _book('epub', _alice);
    await tester.runAsync(() => repo.insertBook(book));
    await tester.pumpWidget(ProviderScope(
      overrides: [
        bookRepoProvider.overrideWithValue(repo),
        audioHandlerProvider.overrideWithValue(_handler(repo)),
      ],
      child: MaterialApp(
        theme: buildTheme(ReaderTheme.paper),
        home: ReaderScreen(book: book),
      ),
    ));
    await _settle(tester, () => find.textContaining(' / ').evaluate().isNotEmpty);

    expect(find.text('This file could not be read. You can still listen to its audio.'),
        findsNothing);
    expect(find.text('Add audio'), findsOneWidget, reason: 'player visible at open');

    final screen = tester.getSize(find.byType(ReaderScreen));
    final footerY = screen.height - 28;

    double opacity() => tester
        .widget<AnimatedOpacity>(find
            .ancestor(
                of: find.text('Add audio'),
                matching: find.byType(AnimatedOpacity))
            .first)
        .opacity;
    expect(opacity(), 1);

    // Every tool is labelled, and the first-time help dismisses.
    for (final label in ['Search', 'My places', 'Text']) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.text('How to use this page'), findsOneWidget);
    await tester.tap(find.text('Got it'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('How to use this page'), findsNothing);

    // The page's centre hides the controls; the footer's far corner, which the
    // bug made untappable, brings them back.
    await tester.tapAt(Offset(screen.width / 2, 300));
    await tester.pump(const Duration(milliseconds: 300));
    expect(opacity(), 0);
    expect(find.textContaining(' / '), findsWidgets, reason: 'page indicator');
    await tester.tapAt(Offset(screen.width / 2 - 200, footerY));
    await tester.pump(const Duration(milliseconds: 300));
    expect(opacity(), 1);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
    await tester.runAsync(() => db.close());
  });

  testWidgets('search: a result opens its page and survives a re-layout',
      (tester) async {
    ReaderActions? actions;
    final log = _Log();
    Widget pane(double height) => _host(_TallPage(
          height,
          EpubPane(
            book: _book('epub', _alice),
            saved: null,
            callbacks: PaneCallbacks(
              onCenterTap: () {},
              onLocation: log.callbacks.onLocation,
              onContents: (_) {},
              onReady: () => log.ready = true,
              onError: (e) => log.error = e,
              onActions: (a) => actions = a,
            ),
          ),
        ));
    await tester.pumpWidget(pane(600));
    await _settle(tester, () => log.ready);
    expect(log.label, startsWith('1 / '));

    final hits = (await tester.runAsync(
        () => actions!.search('mock turtle').toList()))!;
    expect(hits.length, greaterThan(3));
    final hit = hits.last;
    final page = hit.pageLabel.replaceFirst('Page ', '');

    // Height changes first, as when a keyboard closes, while the jump lands.
    actions!.goTo(hit.location, highlightLength: hit.sourceLength);
    await tester.pump();
    expect(log.label, startsWith('$page / '));
    final highlighted = find.byWidgetPredicate((w) =>
        w is RichText &&
        w.text.toPlainText().toLowerCase().contains('mock turtle'));
    expect(highlighted, findsWidgets);

    await tester.pumpWidget(pane(400));
    await _settle(tester, () => false);
    expect(log.label, isNot(startsWith('1 / ')));
    expect(highlighted, findsWidgets, reason: 'still on the matching line');
    await tester.pumpWidget(pane(600));
    await _settle(tester, () => false);
    expect(log.label, startsWith('$page / '));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('search screen: tapping a result moves the real reader',
      (tester) async {
    final db = (await tester.runAsync(() => openTwoFoldDb(
        path: inMemoryDatabasePath, factory: databaseFactoryFfi)))!;
    final repo = BookRepo(db);
    final book = _book('epub', _alice);
    await tester.runAsync(() => repo.insertBook(book));
    await tester.pumpWidget(ProviderScope(
      overrides: [
        bookRepoProvider.overrideWithValue(repo),
        audioHandlerProvider.overrideWithValue(_handler(repo)),
      ],
      child: MaterialApp(
        theme: buildTheme(ReaderTheme.paper),
        home: ReaderScreen(book: book),
      ),
    ));
    await _settle(tester, () => find.textContaining(' / ').evaluate().isNotEmpty);
    await _settle(tester, () => false);
    await tester.tap(find.text('Got it'));
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.text('Search'));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.enterText(find.byType(TextField), 'mock turtle');
    await tester.pump(const Duration(milliseconds: 500));
    await _settle(tester, () => find.byType(Card).evaluate().isNotEmpty);
    await _settle(tester, () => false);

    final firstLabel = tester
        .widget<Text>(find.descendant(
            of: find.byType(Card).first, matching: find.byType(Text)).first)
        .data!;
    final expected = firstLabel.replaceFirst('Page ', '');
    await tester.tap(find.byType(Card).first);
    await tester.pump(const Duration(milliseconds: 400));
    await _settle(tester, () => false);

    expect(find.text('$expected / 257').evaluate().isNotEmpty ||
        find.textContaining('$expected / ').evaluate().isNotEmpty, isTrue);
    expect(find.textContaining(' of '), findsWidgets, reason: 'result bar');

    // The bar steps forward without reopening search.
    await tester.tap(find.byTooltip('Next result'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('2 of '), findsOneWidget);

    await tester.tap(find.byTooltip('End search'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byTooltip('Next result'), findsNothing);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
    await tester.runAsync(() => db.close());
  });
}

class _TallPage extends StatelessWidget {
  const _TallPage(this.height, this.child);

  final double height;
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      Align(alignment: Alignment.topCenter, child: SizedBox(height: height, child: child));
}

TwoFoldAudioHandler _handler(BookRepo repo) => TwoFoldAudioHandler(repo);
