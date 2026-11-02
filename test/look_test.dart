import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:twofold/app/settings.dart';
import 'package:twofold/app/theme.dart';
import 'package:twofold/audio/audio_handler.dart';
import 'package:twofold/audio/player_controller.dart';
import 'package:twofold/data/book_repo.dart';
import 'package:twofold/data/db.dart';
import 'package:twofold/data/models.dart';
import 'package:twofold/features/library/book_card.dart';
import 'package:twofold/features/library/library_screen.dart';
import 'package:twofold/features/library/new_book_screen.dart';
import 'package:twofold/features/listen/listen_screen.dart';
import 'package:twofold/features/player/player_bar.dart';
import 'package:twofold/features/reader/reader_screen.dart';
import 'package:twofold/features/settings/settings_screen.dart';
import 'package:twofold/features/settings/settings_sheet.dart';

Book _b(String id, String title, [String? author, int? opened]) => Book(
    id: id,
    title: title,
    author: author,
    format: 'epub',
    filePath: 'x',
    addedAt: 1,
    lastOpened: opened);

LibraryEntry _e(String id, String title, String? author) =>
    LibraryEntry(_b(id, title, author), null, const []);

void main() {
  sqfliteFfiInit();

  test('library search and sort', () {
    final all = [
      _e('1', 'Zebra', 'Adams'),
      _e('2', 'Apple', 'Young'),
      _e('3', 'Mango', null),
    ];
    List<String> ids(String q, LibrarySort s) =>
        arrangeLibrary(all, q, s).map((e) => e.book.id).toList();
    expect(ids('', LibrarySort.recent), ['1', '2', '3']);
    expect(ids('', LibrarySort.title), ['2', '3', '1']);
    expect(ids('', LibrarySort.author), ['1', '2', '3']);
    expect(ids('YOUNG', LibrarySort.recent), ['2']);
    expect(ids('zzz', LibrarySort.recent), isEmpty);
  });

  // Every screen, in every theme, at a small phone size: nothing may overflow.
  // Set LOOK=1 to also write PNGs to build/look for review.
  for (final theme in [ReaderTheme.paper, ReaderTheme.sepia, ReaderTheme.night]) {
    final palette = switch (theme) {
      ReaderTheme.paper => AppPalette.blueberry,
      ReaderTheme.sepia => AppPalette.forest,
      _ => AppPalette.rose,
    };
    testWidgets('screens lay out in ${theme.name}', (tester) async {
      await _loadFonts(tester);
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      final db = (await tester.runAsync(() =>
          openTwoFoldDb(path: inMemoryDatabasePath, factory: databaseFactoryFfi)))!;
      final repo = BookRepo(db);
      final books = [
        _b('a', 'The Left Hand of Darkness', 'Ursula K. Le Guin', 5),
        _b('b', 'Alice in Wonderland', 'Lewis Carroll', 4),
        _b('c', 'Dune', 'Frank Herbert', 3),
        _b('d', 'A Rather Long Title That Has to Wrap Around', null, 2),
      ];
      await tester.runAsync(() async {
        for (final b in books) {
          await repo.insertBook(b);
        }
        await repo.saveReading('a', location: '0:0', percent: 0.42);
      });
      final handler = TwoFoldAudioHandler(repo);

      Future<void> shot(String name, Widget home,
          [Future<void> Function()? then]) async {
        await tester.pumpWidget(ProviderScope(
          key: UniqueKey(),
          overrides: [
            bookRepoProvider.overrideWithValue(repo),
            audioHandlerProvider.overrideWithValue(handler),
            initialSettingsProvider.overrideWithValue(AppSettings(theme: theme, palette: palette)),
          ],
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: buildTheme(theme, palette),
            home: home,
          ),
        ));
        for (var i = 0; i < 6; i++) {
          await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 60)));
          await tester.pump(const Duration(milliseconds: 100));
        }
        await then?.call();
        await tester.pump(const Duration(milliseconds: 400));
        if (Platform.environment['LOOK'] == '1') {
          await expectLater(find.byType(MaterialApp),
              matchesGoldenFile('../build/look/${theme.name}_$name.png'));
        }
        expect(tester.takeException(), isNull, reason: name);
      }

      await shot('library', const LibraryScreen());
      await shot('options', const LibraryScreen(), () async {
        await tester.tap(find.bySemanticsLabel('Options for Dune'));
        await tester.pump(const Duration(milliseconds: 500));
        expect(find.text('Edit book'), findsOneWidget);
        expect(find.text('Remove from library'), findsOneWidget);
        expect(find.text('Change title or author'), findsNothing);
      });
      await shot('add', const NewBookScreen());
      await shot('edit', NewBookScreen(editing: books[2]));
      await shot('settings', const SettingsScreen());
      await shot('text', Builder(builder: (context) {
        return Scaffold(
            body: Center(
                child: FilledButton(
                    onPressed: () => showSettingsSheet(context),
                    child: const Text('open'))));
      }), () async {
        await tester.tap(find.text('open'));
        await tester.pump(const Duration(milliseconds: 500));
      });
      await shot('listen', ListenScreen(book: books[0]));
      await shot(
          'player',
          const Scaffold(
              body: Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(padding: EdgeInsets.all(12), child: PlayerBar()))));

      await shot(
          'reader',
          ReaderScreen(
              book: Book(
                  id: 'a',
                  title: 'Alice in Wonderland',
                  format: 'epub',
                  filePath: 'test/fixtures/alice.epub',
                  addedAt: 1)), () async {
        for (var i = 0; i < 40 && find.text('Got it').evaluate().isEmpty; i++) {
          await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 100)));
          await tester.pump(const Duration(milliseconds: 50));
        }
        await tester.tap(find.text('Got it'));
        for (var i = 0; i < 20; i++) {
          await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 100)));
          await tester.pump(const Duration(milliseconds: 50));
        }
        expect(find.text('Play audio from about here'), findsNothing);
      });

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 6));
      await tester.runAsync(() => db.close());
    });
  }
}

Future<void> _loadFonts(WidgetTester tester) => tester.runAsync(() async {
      Future<void> load(String family, String path) async {
        final bytes = File(path).readAsBytesSync();
        final loader = FontLoader(family)
          ..addFont(Future.value(ByteData.sublistView(bytes)));
        await loader.load();
      }

      await load('Inter', 'assets/fonts/Inter.ttf');
      await load('Literata', 'assets/fonts/Literata.ttf');
      final sdk = File(Platform.resolvedExecutable).parent.parent.parent.parent.parent;
      final icons = File(
          '${sdk.path}/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
      if (icons.existsSync()) await load('MaterialIcons', icons.path);
    });
