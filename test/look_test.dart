import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twofold/app/home_shell.dart';
import 'package:twofold/features/library/book_details_screen.dart';
import 'package:twofold/features/library/cover_picker.dart';
import 'package:twofold/find/cover_source.dart';
import 'package:twofold/find/librivox.dart';
import 'package:twofold/find/librivox_source.dart';
import 'package:twofold/find/everything_source.dart';
import 'package:twofold/features/welcome/welcome_screen.dart';
import 'package:twofold/features/listen/audiobook_sheet.dart';
import 'package:twofold/features/reader/pane.dart';
import 'package:twofold/features/reader/places_sheet.dart';
import 'package:twofold/features/reader/search.dart';
import 'package:twofold/features/reader/search_screen.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:twofold/app/settings.dart';
import 'package:twofold/app/theme.dart';
import 'package:twofold/audio/audio_handler.dart';
import 'package:twofold/audio/player_controller.dart';
import 'package:twofold/data/book_repo.dart';
import 'package:twofold/data/db.dart';
import 'package:twofold/data/models.dart';
import 'package:twofold/features/find/find_screen.dart';
import 'package:twofold/features/find/providers.dart';
import 'package:twofold/find/book_info.dart';
import 'package:twofold/find/book_source.dart';
import 'package:twofold/find/find_service.dart';
import 'package:twofold/find/web.dart';
import 'package:twofold/features/library/book_card.dart';
import 'package:twofold/features/library/library_screen.dart';
import 'package:twofold/features/library/new_book_screen.dart';
import 'package:twofold/features/listen/listen_screen.dart';
import 'package:twofold/features/player/player_bar.dart';
import 'package:twofold/features/reader/reader_screen.dart';
import 'package:twofold/features/settings/settings_screen.dart';
import 'package:twofold/features/settings/settings_sheet.dart';

/// LibriVox's saved Pride and Prejudice answer, for every question.
class _FixtureWeb extends Web {
  @override
  Future<String> getText(Uri url, {int maxBytes = 4 << 20, Duration timeout = const Duration(seconds: 25)}) async =>
      File('test/fixtures/find/librivox_pride.json').readAsStringSync();
}

class _LookAusten extends BookSource {
  @override
  String get id => 'gutenberg';
  @override
  String get name => 'Project Gutenberg';
  @override
  String get blurb => '';
  @override
  Future<FoundPage> search(String query, {int page = 0}) async => const FoundPage([
        FoundBook(source: 'gutenberg', id: '1342', title: 'Pride and Prejudice', author: 'Jane Austen'),
        FoundBook(source: 'gutenberg', id: '946', title: 'Lady Susan', author: 'Jane Austen'),
      ], hasMore: false);
  @override
  Future<List<DownloadTarget>> targets(FoundBook book) async => const [];
}

class _LookSource extends BookSource {
  @override
  String get id => 'gutenberg';
  @override
  String get name => 'Project Gutenberg';
  @override
  String get blurb => 'Free classics, mostly before 1930.';
  @override
  Future<FoundPage> search(String query, {int page = 0}) async => const FoundPage([
        FoundBook(source: 'gutenberg', id: '11', title: "Alice's Adventures in Wonderland", author: 'Lewis Carroll'),
        FoundBook(source: 'gutenberg', id: '12', title: 'Through the Looking-Glass', author: 'Lewis Carroll'),
        FoundBook(source: 'gutenberg', id: '13', title: 'A Rather Long Title That Has to Wrap Around Two Lines', author: 'Some Author', detail: '1901'),
      ], hasMore: true);
  @override
  Future<List<Shelf>> shelves() async => const [
        Shelf(id: 'downloads', title: 'Popular', blurb: 'The most downloaded books.'),
        Shelf(id: 'release_date', title: 'Latest', blurb: 'Newly added to the library.'),
        Shelf(id: 'random', title: 'Random', blurb: 'A fresh handful each time.'),
      ];

  @override
  Future<List<DownloadTarget>> targets(FoundBook book) async => const [];
}

class _LookInfo extends BookInfoService {
  _LookInfo() : super(Web());

  @override
  Future<BookInfo?> lookUp(FoundBook book) async => const BookInfo(
        workKey: '/works/OL1W',
        rating: 4.1,
        ratingCount: 2381,
        wantToRead: 912,
        firstYear: 1865,
        pages: 192,
        subjects: ['Fantasy fiction', 'Wonderland (Imaginary place)', 'Girls', 'Classics'],
        description: 'Alice follows a white rabbit down a hole into a world where '
            'the rules of logic bend. She shrinks, grows, argues with a caterpillar '
            'and attends the strangest tea party in literature.',
      );
}

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
      ReaderTheme.paper => AppPalette.indigo,
      ReaderTheme.sepia => AppPalette.forest,
      _ => AppPalette.clay,
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
      Widget findHome() => ProviderScope(
          overrides: [
            findServiceProvider.overrideWithValue(
                FindService(web: Web(), sources: [_LookSource()], info: _LookInfo())),
          ],
          child: const FindScreen());
      await shot('find', findHome());
      await shot('find_results', findHome(), () async {
        await tester.enterText(find.byType(TextField), 'alice');
        await tester.tap(find.byTooltip('Search'));
        for (var i = 0; i < 5; i++) {
          await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 60)));
          await tester.pump(const Duration(milliseconds: 100));
        }
      });
      await shot('find_catalog', findHome(), () async {
        await tester.tap(find.text('Add catalog'));
        await tester.pump(const Duration(milliseconds: 400));
        await tester.enterText(find.widgetWithText(TextField, 'Name (optional)'), 'My library');
        await tester.pump(const Duration(milliseconds: 200));
      });
      await shot('find_details', findHome(), () async {
        await tester.enterText(find.byType(TextField), 'alice');
        await tester.tap(find.byTooltip('Search'));
        for (var i = 0; i < 5; i++) {
          await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 60)));
          await tester.pump(const Duration(milliseconds: 100));
        }
        await tester.tap(find.text('Lewis Carroll').first);
        for (var i = 0; i < 6; i++) {
          await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 60)));
          await tester.pump(const Duration(milliseconds: 120));
        }
      });
      await shot('welcome', const WelcomeScreen());
      Widget everything() {
        final lv = LibrivoxSource(_FixtureWeb());
        final g = _LookAusten();
        return ProviderScope(
          overrides: [
            findServiceProvider.overrideWithValue(FindService(
              web: Web(),
              sources: [EverythingSource(gutenberg: g, recordings: lv), g, lv],
              info: _LookInfo(),
            )),
          ],
          child: const FindScreen(),
        );
      }
      await shot('find_everything', everything());
      await shot('find_everything_results', everything(), () async {
        await tester.enterText(find.byType(TextField), 'austen');
        await tester.tap(find.byTooltip('Search'));
        for (var i = 0; i < 6; i++) {
          await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 80)));
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(find.text('Book + audiobook'), findsWidgets);
      });
      await shot('find_everything_details', everything(), () async {
        await tester.enterText(find.byType(TextField), 'austen');
        await tester.tap(find.byTooltip('Search'));
        for (var i = 0; i < 6; i++) {
          await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 80)));
          await tester.pump(const Duration(milliseconds: 100));
        }
        await tester.tap(find.text('Pride and Prejudice').first);
        for (var i = 0; i < 4; i++) {
          await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 80)));
          await tester.pump(const Duration(milliseconds: 120));
        }
        await tester.drag(find.text('Jane Austen').last, const Offset(0, -500));
        for (var i = 0; i < 4; i++) {
          await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 80)));
          await tester.pump(const Duration(milliseconds: 120));
        }
        expect(find.text('Get book and audiobook'), findsOneWidget);
        expect(find.text('Get the book only'), findsOneWidget);
      });
      Widget shell() => ProviderScope(
          overrides: [
            findServiceProvider.overrideWithValue(
                FindService(web: Web(), sources: [_LookSource()], info: _LookInfo())),
          ],
          child: const HomeShell());
      await shot('home', shell());
      await shot('home_settings', shell(), () async {
        await tester.tap(find.bySemanticsLabel('Settings'));
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.text('LOOK'), findsOneWidget);
        await tester.tap(find.bySemanticsLabel('Find'));
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.text('Title or author in Project Gutenberg'), findsOneWidget);
        await tester.tap(find.bySemanticsLabel('Settings'));
        await tester.pump(const Duration(milliseconds: 400));
      });
      await shot('places', Builder(builder: (context) {
        return Scaffold(
            body: Center(
                child: FilledButton(
                    onPressed: () => showModalBottomSheet<void>(
                        context: context,
                        isScrollControlled: true,
                        builder: (_) => PlacesSheet(
                            book: books[0],
                            location: '3:0',
                            percent: 0.2,
                            pageLabel: 'Page 12',
                            actions: null)),
                    child: const Text('open'))));
      }), () async {
        await tester.runAsync(() => repo.addMark(PlaceMark(
            id: 'm1', bookId: 'a', location: '1:0', percent: 0.1,
            pageLabel: 'Page 4', createdAt: DateTime.now().millisecondsSinceEpoch,
            note: 'The letter arrives')));
        await tester.tap(find.text('open'));
        for (var i = 0; i < 4; i++) {
          await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 60)));
          await tester.pump(const Duration(milliseconds: 150));
        }
        expect(find.text('The letter arrives'), findsOneWidget);
      });
      await shot('search', SearchScreen(actions: _LookActions()), () async {
        await tester.enterText(find.byType(TextField), 'rabbit');
        await tester.pump(const Duration(milliseconds: 500));
        for (var i = 0; i < 3; i++) {
          await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 60)));
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(find.byKey(const ValueKey('search-hit-0')), findsOneWidget);
      });
      Widget withCovers(Widget child) => ProviderScope(
          overrides: [
            findServiceProvider.overrideWithValue(FindService(
                web: Web(), sources: [_LookSource()], info: _LookInfo(), covers: _LookCovers(),
                librivox: _LookLibrivox())),
          ],
          child: child);
      await shot('covers', withCovers(Scaffold(body: SafeArea(child: CoverPicker(book: books[1])))), () async {
        for (var i = 0; i < 6; i++) {
          await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 60)));
          await tester.pump(const Duration(milliseconds: 150));
        }
        expect(find.text('Choose a cover'), findsOneWidget);
        expect(find.text('Most used'), findsOneWidget);
      });
      await tester.runAsync(() => repo.saveDetails(BookDetails(
            bookId: 'b',
            source: 'Project Gutenberg',
            summary: 'A girl falls down a rabbit hole.',
            description: 'Alice follows a white rabbit into a world where the rules '
                'of logic bend. She shrinks, grows, and goes to a very odd tea party.',
            subjects: const ['Fantasy fiction', 'Classics', 'Girls'],
            rating: 4.1,
            ratingCount: 2381,
            wantToRead: 912,
            firstYear: 1865,
            pages: 192,
            olWork: '/works/OL1W',
            updatedAt: 1,
          )));
      await shot('details', withCovers(const BookDetailsScreen(bookId: 'b')));
      await shot('details_own', withCovers(const BookDetailsScreen(bookId: 'c')));
      await shot('audiobook', withCovers(Scaffold(body: AudiobookSheet(book: books[1]))), () async {
        for (var i = 0; i < 4; i++) {
          await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 60)));
          await tester.pump(const Duration(milliseconds: 150));
        }
        expect(find.text('Add audiobook'), findsOneWidget);
        expect(find.textContaining('Read by'), findsWidgets);
      });
      await tester.runAsync(() async {
        await repo.setAudiobook(
          const Audiobook(bookId: 'b', source: 'librivox', sourceId: '254',
              reader: 'Annie Coleman Rothenberg', parts: 3, addedAt: 1),
          [
            for (var i = 0; i < 3; i++)
              AudioTrack(
                id: 'lv$i', bookId: 'b',
                filePath: 'https://archive.org/download/x/$i.mp3',
                remoteUrl: 'https://archive.org/download/x/$i.mp3',
                position: i, durationMs: 1200000, title: 'Chapter ${i + 1}'),
          ],
        );
      });
      await shot('details_audio', withCovers(const BookDetailsScreen(bookId: 'b')), () async {
        for (var i = 0; i < 4; i++) {
          await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 60)));
          await tester.pump(const Duration(milliseconds: 150));
        }
        await tester.scrollUntilVisible(find.textContaining('for LibriVox'), 200);
        await tester.pump(const Duration(milliseconds: 200));
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

class _LookActions implements ReaderActions {
  @override
  Stream<SearchHit> search(String query) => Stream.fromIterable([
        for (final (i, f) in [(0, 0.08), (1, 0.4), (2, 0.86)].indexed)
          makeHit(
            'Alice saw the White Rabbit hurry past, muttering about the time, '
            'and she ran across the field after it.',
            (20, 6),
            pageLabel: 'Page ${12 + i * 40}',
            location: '$i:0',
            fraction: f.$2,
          ),
      ]);
  @override
  void goTo(String location, {int highlightLength = 0}) {}
  @override
  void goToFraction(double fraction) {}
  @override
  void clearHighlight() {}
}

class _LookCovers extends CoverService {
  _LookCovers() : super(Web());

  @override
  Future<List<CoverCandidate>> search(String title, String? author) async => [
        const CoverCandidate(id: 1, label: 'Most used'),
        for (var i = 2; i < 8; i++)
          CoverCandidate(id: i, label: '${1890 + i * 13} · Macmillan'),
      ];

  @override
  Future<Uint8List?> image(Uri url) async =>
      File('assets/samples/story-of-an-hour.png').readAsBytesSync();
}

class _LookLibrivox extends LibrivoxService {
  _LookLibrivox() : super(Web());

  @override
  Future<List<LibrivoxBook>> find(String title, {String? author, String? gutenbergId}) async =>
      rankRecordings(
        parseLibrivoxFeed(jsonDecode(
            File('test/fixtures/find/librivox_pride.json').readAsStringSync())),
        author: 'Jane Austen',
        gutenbergId: '1342',
      ).take(4).toList();
}
