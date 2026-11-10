import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:twofold/app/theme.dart';
import 'package:twofold/audio/player_controller.dart';
import 'package:twofold/data/book_repo.dart';
import 'package:twofold/data/db.dart';
import 'package:twofold/features/find/find_screen.dart';
import 'package:twofold/features/find/providers.dart';
import 'package:twofold/find/book_info.dart';
import 'package:twofold/find/book_source.dart';
import 'package:twofold/find/find_service.dart';
import 'package:twofold/find/web.dart';

class _Source extends BookSource {
  _Source(this.id, this.name, this.books);

  @override
  final String id;
  @override
  final String name;
  final List<FoundBook> books;
  final queries = <String>[];

  @override
  String get blurb => 'Blurb of $name.';

  /// Lists offered to browse; none unless a test sets them.
  List<Shelf> lists = const [];
  final browsed = <String>[];

  @override
  Future<List<Shelf>> shelves() async => lists;

  @override
  Future<FoundPage> browse(Shelf shelf, {int page = 0}) async {
    browsed.add(shelf.id);
    return FoundPage(books, hasMore: false);
  }

  @override
  Future<FoundPage> search(String query, {int page = 0}) async {
    queries.add(query);
    if (query == 'offline') throw const WebError(offlineMessage);
    return FoundPage(query == 'nothing' ? const [] : books, hasMore: false);
  }

  @override
  Future<List<DownloadTarget>> targets(FoundBook book) async => const [];
}

/// Open Library's answer for one book, without going online.
class _Info extends BookInfoService {
  _Info() : super(Web());

  @override
  Future<BookInfo?> lookUp(FoundBook book) async => book.id == '7'
      ? const BookInfo(
          workKey: '/works/OL1W',
          rating: 4.5,
          ratingCount: 1234,
          wantToRead: 56,
          firstYear: 1894,
          pages: 25,
          subjects: ['Short stories', 'Freedom'],
          description: 'A long description from Open Library.',
        )
      : null;
}

/// Hands out a real EPUB instead of going to the internet.
class _Service extends FindService {
  _Service(List<BookSource> sources, this.failing, this.tmp)
      : super(web: Web(), sources: sources, info: _Info());

  final Set<String> failing;
  final Directory tmp;
  final downloaded = <String>[];

  @override
  Future<(File, BookFormat)> download(
    FoundBook book, {
    void Function(int received, int? total)? onProgress,
  }) async {
    downloaded.add(book.key);
    if (failing.contains(book.id)) {
      throw const WebError('The site is busy right now. Try again in a minute.');
    }
    onProgress?.call(512, 1024);
    final copy = File('${tmp.path}/${book.id}.epub');
    await File('test/fixtures/alice.epub').copy(copy.path);
    return (copy, BookFormat.epub);
  }
}

Future<void> _settle(WidgetTester tester, bool Function() done) async {
  for (var i = 0; i < 100 && !done(); i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump(const Duration(milliseconds: 50));
  }
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  sqfliteFfiInit();

  testWidgets('search, get a book into the library, and see it owned next time',
      (tester) async {
    final tmp = Directory.systemTemp.createTempSync('twofold-screen');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => tmp.path,
    );
    final db = (await tester.runAsync(() => openTwoFoldDb(
        path: inMemoryDatabasePath, factory: databaseFactoryFfi)))!;
    final repo = BookRepo(db);

    final gutenberg = _Source('gutenberg', 'Project Gutenberg', const [
      FoundBook(source: 'gutenberg', id: '11', title: 'Alice Story', author: 'Lewis Carroll'),
      FoundBook(source: 'gutenberg', id: '12', title: 'Another Tale', author: 'A. Writer'),
    ]);
    final archive = _Source('archive', 'Internet Archive', const [
      FoundBook(source: 'archive', id: 'abc', title: 'Archive Find', detail: '1901'),
    ]);
    final service = _Service([gutenberg, archive], {'12'}, tmp);

    Widget app() => ProviderScope(
          overrides: [
            bookRepoProvider.overrideWithValue(repo),
            findServiceProvider.overrideWithValue(service),
          ],
          child: MaterialApp(theme: buildTheme(ReaderTheme.paper), home: const FindScreen()),
        );

    await tester.pumpWidget(app());
    expect(find.textContaining('only place TwoFold uses the internet'), findsOneWidget);
    expect(find.text('Blurb of Project Gutenberg.'), findsOneWidget);

    // An empty search does nothing.
    await tester.tap(find.byTooltip('Search'));
    await tester.pump();
    expect(gutenberg.queries, isEmpty);

    await tester.enterText(find.byType(TextField), 'alice');
    await tester.tap(find.byTooltip('Search'));
    await _settle(tester, () => find.text('Alice Story').evaluate().isNotEmpty);
    expect(gutenberg.queries, ['alice']);
    expect(find.text('Lewis Carroll'), findsOneWidget);
    expect(find.text('Get'), findsNWidgets(2));

    // Getting a book puts it in the library and offers to open it.
    await tester.tap(find.text('Get').first);
    await _settle(tester, () => find.text('Open').evaluate().length == 2);
    expect(find.text('Open'), findsNWidgets(2), reason: 'in the row and in the tray');
    expect(find.text('Lewis Carroll · In your library'), findsOneWidget);
    expect(find.text('In your library'), findsOneWidget);
    final books = (await tester.runAsync(() => repo.allBooks()))!;
    expect(books.single.title, 'Alice Story');
    expect(books.single.author, 'Lewis Carroll');
    expect(File(books.single.filePath).existsSync(), isTrue);
    expect(tmp.listSync().whereType<File>().where((f) => f.path.endsWith('11.epub')),
        isEmpty, reason: 'the download is deleted once it is imported');

    // A failure is said in words and can be retried.
    await tester.tap(find.text('Get'));
    await _settle(tester, () => find.text('Try again').evaluate().isNotEmpty);
    expect(find.textContaining('busy right now'), findsNWidgets(2), reason: 'in the row and in the tray');
    expect((await tester.runAsync(() => repo.allBooks()))!.length, 1);

    // Another site gives its own results.
    await tester.tap(find.text('Internet Archive'));
    await _settle(tester, () => find.text('Archive Find').evaluate().isNotEmpty);
    expect(archive.queries, ['alice']);
    expect(find.text('Alice Story'), findsOneWidget, reason: 'only in the tray now');
    expect(find.text('Search Internet Archive'), findsOneWidget);

    // Nothing found and no connection both explain themselves.
    await tester.enterText(find.byType(TextField), 'nothing');
    await tester.tap(find.byTooltip('Search'));
    await _settle(tester, () => find.textContaining('No results').evaluate().isNotEmpty);
    expect(find.textContaining('No results for "nothing"'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'offline');
    await tester.tap(find.byTooltip('Search'));
    await _settle(tester, () => find.text(offlineMessage).evaluate().isNotEmpty);
    expect(find.text('Try again'), findsOneWidget);

    // A fresh screen knows what is already in the library.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(app());
    await tester.enterText(find.byType(TextField), 'alice');
    await tester.tap(find.byTooltip('Search'));
    await _settle(tester, () => find.text('In your library').evaluate().isNotEmpty);
    expect(find.text('Open'), findsOneWidget);
    expect(find.text('Get'), findsOneWidget);
    expect(service.downloaded, ['gutenberg:11', 'gutenberg:12']);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
    await tester.runAsync(() => db.close());
  });

  testWidgets('browse a list, see a book in detail, get it from there', (tester) async {
    final tmp = Directory.systemTemp.createTempSync('twofold-browse');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => tmp.path,
    );
    final db = (await tester.runAsync(() => openTwoFoldDb(
        path: inMemoryDatabasePath, factory: databaseFactoryFfi)))!;
    final repo = BookRepo(db);
    final source = _Source('gutenberg', 'Project Gutenberg', const [
      FoundBook(
        source: 'gutenberg',
        id: '7',
        title: 'Popular Pick',
        author: 'An Author',
        summary: 'A story about a pick that is popular.',
      ),
    ])
      ..lists = const [
        Shelf(id: 'downloads', title: 'Popular', blurb: 'The most downloaded books.'),
        Shelf(id: 'random', title: 'Random'),
      ];
    final service = _Service([source], const {}, tmp);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        bookRepoProvider.overrideWithValue(repo),
        findServiceProvider.overrideWithValue(service),
      ],
      child: MaterialApp(theme: buildTheme(ReaderTheme.paper), home: const FindScreen()),
    ));
    await _settle(tester, () => find.text('Popular').evaluate().isNotEmpty);
    expect(find.text('BROWSE'), findsOneWidget);
    expect(find.text('The most downloaded books.'), findsOneWidget);

    await tester.tap(find.text('Popular'));
    await _settle(tester, () => find.text('Popular Pick').evaluate().isNotEmpty);
    expect(source.browsed, ['downloads']);
    expect(find.text('An Author'), findsOneWidget);

    // The row opens the details, which has one clear button.
    await tester.tap(find.text('Popular Pick').last);
    await _settle(tester, () => find.text('Get book').evaluate().isNotEmpty);
    await tester.dragUntilVisible(
      find.text('A long description from Open Library.'),
      find.byType(ListView).last,
      const Offset(0, -150),
    );
    expect(find.text('A long description from Open Library.'), findsOneWidget);
    expect(find.text('4.5'), findsOneWidget);
    expect(find.text('(1,234)'), findsOneWidget);
    expect(find.text('56 want to read it'), findsOneWidget);
    expect(find.text('1894'), findsOneWidget);
    expect(find.text('Short stories', skipOffstage: false), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('Rated 4.5 out of 5')), findsOneWidget);
    expect(find.text('Project Gutenberg'), findsWidgets);
    await tester.dragUntilVisible(find.text('Get book'), find.byType(ListView).last, const Offset(0, 150));
    await tester.tap(find.text('Get book'));
    await _settle(tester, () => find.text('Open in reader').evaluate().isNotEmpty);
    expect(find.text('Open in reader'), findsOneWidget);
    // The tray under the list says the book is in, and offers to open it.
    expect(find.textContaining('In your library'), findsWidgets);
    expect((await tester.runAsync(() => repo.allBooks()))!.single.title, 'Popular Pick');

    // Closing the sheet and going back shows the lists again.
    await tester.tapAt(const Offset(20, 20));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.byTooltip('Back to lists'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Random'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
    await tester.runAsync(() => db.close());
  });

  testWidgets('a catalog is added by its link and remembered', (tester) async {
    final tmp = Directory.systemTemp.createTempSync('twofold-catalog');
    final db = (await tester.runAsync(() => openTwoFoldDb(
        path: inMemoryDatabasePath, factory: databaseFactoryFfi)))!;
    final repo = BookRepo(db);
    final service = _Service([_Source('gutenberg', 'Project Gutenberg', const [])], const {}, tmp);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        bookRepoProvider.overrideWithValue(repo),
        findServiceProvider.overrideWithValue(service),
      ],
      child: MaterialApp(theme: buildTheme(ReaderTheme.paper), home: const FindScreen()),
    ));
    await tester.pump();

    await tester.tap(find.text('Add catalog'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.enterText(find.widgetWithText(TextField, 'Catalog link'), 'http://example.org/opds');
    await tester.tap(find.text('Add'));
    await tester.pump();
    expect(find.text('Only secure links (https) can be added.'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextField, 'Name (optional)'), 'My Shelf');
    await tester.enterText(find.widgetWithText(TextField, 'Catalog link'), 'example.org/opds');
    await tester.tap(find.text('Add'));
    await tester.pump(const Duration(milliseconds: 400));
    await _settle(tester, () => find.text('My Shelf').evaluate().isNotEmpty);
    expect(find.text('My Shelf'), findsOneWidget);
    expect(service.catalogs.single.root.toString(), 'https://example.org/opds');
    expect(service.web.hosts, contains('example.org'));
    final saved = (await tester.runAsync(() => repo.getSetting(catalogsKey)))!;
    expect(saved, contains('https://example.org/opds'));

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
    service.web.close();
    await tester.runAsync(() => db.close());
  });

  test('catalog links must be secure and real', () {
    expect(catalogLink('example.org/opds').toString(), 'https://example.org/opds');
    expect(catalogLink('https://a.b/c?x=1').toString(), 'https://a.b/c?x=1');
    expect(catalogLink('http://a.b/c'), isNull);
    expect(catalogLink('  '), isNull);
  });

  test('file names from titles are safe', () {
    expect(safeFileName('What? A "Book": Part 1/2'), 'What A Book Part 1 2');
    expect(safeFileName('???'), 'Book');
    expect(safeFileName('x' * 200).length, 80);
  });
}
