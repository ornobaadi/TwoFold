import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:twofold/app/settings.dart';
import 'package:twofold/app/theme.dart';
import 'package:twofold/audio/audio_handler.dart';
import 'package:twofold/audio/chapters.dart';
import 'package:twofold/audio/player_controller.dart';
import 'package:twofold/data/book_repo.dart';
import 'package:twofold/data/db.dart';
import 'package:twofold/data/models.dart';
import 'package:twofold/app/home_shell.dart';
import 'package:twofold/features/find/providers.dart';
import 'package:twofold/features/library/book_details_screen.dart';
import 'package:twofold/find/book_info.dart';
import 'package:twofold/find/book_source.dart';
import 'package:twofold/find/cover_source.dart';
import 'package:twofold/find/find_service.dart';
import 'package:twofold/find/web.dart';
import 'package:twofold/features/listen/listen_screen.dart';
import 'package:twofold/features/reader/reader_screen.dart';
import 'package:twofold/features/settings/settings_screen.dart';

/// Renders the Play Store screenshots with public domain books.
/// Run with SHOTS=1 and --update-goldens; writes to build/shots.
void main() {
  sqfliteFfiInit();

  testWidgets('store screenshots', (tester) async {
    await _loadFonts(tester);
    // Real shadows, not the test renderer's outlines.
    debugDisableShadows = false;
    tester.view.physicalSize = const Size(1080, 2160);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final db = (await tester.runAsync(() =>
        openTwoFoldDb(path: inMemoryDatabasePath, factory: databaseFactoryFfi)))!;
    final repo = BookRepo(db);
    const titles = [
      ('alice', 'Alice in Wonderland', 'Lewis Carroll', 9),
      ('pride', 'Pride and Prejudice', 'Jane Austen', 8),
      ('dracula', 'Dracula', 'Bram Stoker', 7),
      ('moby', 'Moby-Dick', 'Herman Melville', 6),
      ('frank', 'Frankenstein', 'Mary Shelley', 5),
      ('holmes', 'Sherlock Holmes', 'Arthur Conan Doyle', 4),
    ];
    Book book(String id, String title, String author, int opened) => Book(
        id: id,
        title: title,
        author: author,
        format: 'epub',
        filePath: 'test/fixtures/alice.epub',
        addedAt: 1793000000000,
        lastOpened: opened);
    final alice = book('alice', 'Alice in Wonderland', 'Lewis Carroll', 9);
    await tester.runAsync(() async {
      for (final t in titles) {
        await repo.insertBook(book(t.$1, t.$2, t.$3, t.$4));
      }
      await repo.setTracks('alice', const [
        AudioTrack(
            id: 't',
            bookId: 'alice',
            filePath: 'x',
            position: 0,
            durationMs: 11100000,
            title: 'Alice'),
      ]);
      await repo.saveAudio('alice', trackIndex: 0, audioMs: 3100000, speed: 1);
      await repo.saveReading('alice', location: '120:0', percent: 0.28);
      await repo.saveReading('pride', location: '1:0', percent: 0.64);
      await repo.saveReading('dracula', location: '1:0', percent: 0.12);
      for (final (i, label) in const ['12 / 257', '47 / 257'].indexed) {
        await repo.addMark(PlaceMark(
            id: 'm$i',
            bookId: 'alice',
            location: '100:0',
            percent: 0.2,
            pageLabel: label,
            audioMs: 1500000 + i * 1600000,
            createdAt: 1793000000000 + i * 90000000));
      }
    });
    final handler = _ShotHandler(repo);
    handler.chapters.value = const [
      AudioChapter('Down the Rabbit Hole', Duration.zero),
      AudioChapter('The Pool of Tears', Duration(minutes: 20)),
      AudioChapter('A Caucus-Race', Duration(minutes: 41)),
      AudioChapter('The Rabbit Sends in a Little Bill', Duration(minutes: 62)),
    ];
    handler.mediaItem.add(MediaItem(
        id: 'alice',
        title: 'Alice in Wonderland',
        duration: const Duration(hours: 3, minutes: 5)));

    final findService = FindService(
        web: Web(),
        sources: [_ShotSource()],
        info: _ShotInfo(),
        covers: CoverService(Web()));
    await tester.runAsync(() => repo.saveDetails(BookDetails(
          bookId: 'pride',
          source: 'Project Gutenberg',
          description:
              'Elizabeth Bennet, the second of five sisters, meets the proud Mr Darcy. '
              'First impressions, family pressure and money shape a story about '
              'judging too quickly and changing your mind.',
          subjects: const ['Courtship', 'Sisters', 'England', 'Classics'],
          rating: 4.2,
          ratingCount: 416,
          wantToRead: 6813,
          firstYear: 1813,
          pages: 351,
          olWork: '/works/OL66554W',
          updatedAt: 1,
        )));

    Future<void> wait([int n = 15]) async {
      for (var i = 0; i < n; i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 100)));
        await tester.pump(const Duration(milliseconds: 60));
      }
    }

    Future<void> open(Widget home, ReaderTheme theme, AppPalette palette) async {
      await tester.pumpWidget(ProviderScope(
        key: UniqueKey(),
        overrides: [
          bookRepoProvider.overrideWithValue(repo),
          audioHandlerProvider.overrideWithValue(handler),
          initialSettingsProvider.overrideWithValue(
              AppSettings(theme: theme, palette: palette, hintShown: true)),
          findServiceProvider.overrideWithValue(findService),
        ],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildTheme(theme, palette),
          home: home,
        ),
      ));
      await wait();
    }

    Future<void> shot(String name) async {
      if (Platform.environment['SHOTS'] == '1') {
        await expectLater(find.byType(MaterialApp),
            matchesGoldenFile('../build/shots/$name.png'));
      }
    }

    await open(const HomeShell(), ReaderTheme.paper, AppPalette.indigo);
    await shot('library');

    await open(const HomeShell(initialTab: 1), ReaderTheme.paper, AppPalette.indigo);
    await shot('find');

    await open(const BookDetailsScreen(bookId: 'pride'), ReaderTheme.sepia,
        AppPalette.indigo);
    await shot('details');

    await open(ReaderScreen(book: alice), ReaderTheme.paper, AppPalette.indigo);
    await wait(25);
    await shot('reader');

    await tester.tap(find.text('My places'));
    await tester.pump(const Duration(milliseconds: 500));
    await wait(5);
    await shot('places');
    await open(ListenScreen(book: alice), ReaderTheme.night, AppPalette.clay);
    await shot('listen');

    await open(const SettingsScreen(), ReaderTheme.night, AppPalette.forest);
    await shot('colours');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 6));
    debugDisableShadows = true;
    await tester.runAsync(() => db.close());
  });
}

/// A loaded book, part-way through, with no real player behind it.
class _ShotHandler extends TwoFoldAudioHandler {
  _ShotHandler(super.repo);

  static const _at = Duration(minutes: 51, seconds: 40);

  @override
  String? get bookId => 'alice';

  @override
  Duration get total => const Duration(hours: 3, minutes: 5);

  @override
  Duration get absolutePosition => _at;

  @override
  Stream<Duration> get positionStream => Stream.value(_at);

  @override
  Future<void> loadBook(Book book, {bool reload = false}) async {}
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
      final sdk =
          File(Platform.resolvedExecutable).parent.parent.parent.parent.parent;
      await load('MaterialIcons',
          '${sdk.path}/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
    });

/// A stand-in library with public domain lists, so no request leaves the test.
class _ShotSource extends BookSource {
  @override
  String get id => 'gutenberg';
  @override
  String get name => 'Project Gutenberg';
  @override
  String get blurb => 'Over 75,000 free ebooks, mostly older than 1930.';

  @override
  Future<List<Shelf>> shelves() async => [
        for (final t in ['Popular', 'Latest', 'Random'])
          Shelf(id: t, title: t, url: Uri.parse('https://example.org/$t')),
      ];

  @override
  Future<FoundPage> browse(Shelf shelf, {int page = 0}) async =>
      const FoundPage([], hasMore: false);

  @override
  Future<FoundPage> search(String query, {int page = 0}) async =>
      const FoundPage([], hasMore: false);

  @override
  Future<List<DownloadTarget>> targets(FoundBook book) async => const [];
}

class _ShotInfo extends BookInfoService {
  _ShotInfo() : super(Web());

  @override
  Future<BookInfo?> lookUp(FoundBook book) async => null;
}
