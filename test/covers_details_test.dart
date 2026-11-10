import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:twofold/data/book_repo.dart';
import 'package:twofold/data/db.dart';
import 'package:twofold/data/models.dart';
import 'package:twofold/features/find/keep_details.dart';
import 'package:twofold/find/book_info.dart';
import 'package:twofold/find/book_source.dart';
import 'package:twofold/find/cover_source.dart';
import 'package:twofold/find/opds_source.dart';
import 'package:twofold/find/web.dart';
import 'package:twofold/import/importer.dart';

Map<String, dynamic> _json(String name) =>
    jsonDecode(File('test/fixtures/find/$name').readAsStringSync())
        as Map<String, dynamic>;

/// A JPEG-looking picture big enough to count as a cover.
Uint8List _jpeg() => Uint8List.fromList([0xFF, 0xD8, ...List.filled(4000, 7)]);

class _Covers extends CoverService {
  _Covers() : super(Web());
  final asked = <Uri>[];

  @override
  Future<Uint8List?> image(Uri url) async {
    asked.add(url);
    return _jpeg();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  group('covers', () {
    test('work search gives the work and its main cover', () {
      final r = parseWorkSearch({
        'docs': [
          {'key': '/works/OL66554W', 'cover_i': 14348537},
        ],
      });
      expect(r.work, '/works/OL66554W');
      expect(r.cover, 14348537);
      expect(parseWorkSearch({'docs': []}).work, isNull);
    });

    test('real editions page: each cover once, main cover first, labelled', () {
      final list = parseEditionCovers(
        _json('ol_editions.json'),
        first: 15043406,
      );
      expect(list.first.id, 15043406);
      expect(list.first.label, 'Most used');
      expect(list.map((c) => c.id).toSet().length, list.length);
      expect(list.length, greaterThan(15));
      expect(list.every((c) => c.id > 0), isTrue);
      expect(list.any((c) => c.label?.contains('1960') ?? false), isTrue);
      expect(list[1].thumb.toString(), endsWith('-M.jpg'));
      expect(list[1].full.host, 'covers.openlibrary.org');
    });

    test('missing covers (negative ids) are skipped', () {
      final list = parseEditionCovers({
        'entries': [
          {
            'covers': [-1, 5, 5],
            'publish_date': 'May 2001',
          },
        ],
      });
      expect(list.map((c) => c.id), [5]);
      expect(list.single.label, '2001');
    });

    test('only real pictures count as covers', () {
      expect(looksLikeCover(_jpeg()), isTrue);
      expect(looksLikeCover(Uint8List.fromList([0xFF, 0xD8, 1, 2])), isFalse,
          reason: 'the blank placeholder is tiny');
      expect(looksLikeCover(Uint8List.fromList(List.filled(4000, 60))), isFalse,
          reason: 'not an image');
    });
  });

  test('Unglue.it feed: free EPUBs with open-access links', () {
    final feed = parseOpdsFeed(
      File('test/fixtures/find/unglue_epub.xml').readAsStringSync(),
      Uri.parse('https://unglue.it/api/opds/epub/'),
      source: 'unglue',
    );
    expect(feed.books, isNotEmpty);
    final b = feed.books.first;
    expect(b.title, isNotEmpty);
    expect(b.downloads, isNotEmpty);
    expect(b.downloads.first.format, BookFormat.epub);
    expect(b.downloads.first.url.host, 'unglue.it');
  });

  group('kept details', () {
    late BookRepo repo;
    late Importer importer;
    late Directory tmp;
    const book = Book(
      id: 'b1',
      title: 'Pride and Prejudice',
      author: 'Jane Austen',
      format: 'epub',
      filePath: '/x.epub',
      addedAt: 1,
    );
    const found = FoundBook(
      source: 'gutenberg',
      id: '1342',
      title: 'Pride and Prejudice',
      author: 'Jane Austen',
      summary: 'A novel.',
    );
    const info = BookInfo(
      workKey: '/works/OL66554W',
      rating: 4.2,
      ratingCount: 416,
      wantToRead: 6813,
      firstYear: 1813,
      pages: 351,
      subjects: ['Courtship', 'Families'],
      description: 'Elizabeth Bennet and Mr Darcy.',
      coverId: 14348537,
    );

    setUp(() async {
      tmp = Directory.systemTemp.createTempSync('twofold');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (_) async => tmp.path,
          );
      final db = await openTwoFoldDb(
        path: inMemoryDatabasePath,
        factory: databaseFactoryFfi,
      );
      repo = BookRepo(db);
      importer = Importer(repo);
      await repo.insertBook(book);
    });

    test('saved with the book, read back, and removed with it', () async {
      await repo.saveDetails(
        detailsFrom(book.id, info, found: found, sourceName: 'Project Gutenberg'),
      );
      final d = (await repo.detailsFor(book.id))!;
      expect(d.source, 'Project Gutenberg');
      expect(d.sourceUrl, 'https://www.gutenberg.org/ebooks/1342');
      expect(d.summary, 'A novel.');
      expect(d.rating, 4.2);
      expect(d.subjects, ['Courtship', 'Families']);
      expect(d.firstYear, 1813);
      expect(d.lookedUp, isTrue);

      await importer.removeBook(book.id);
      expect(await repo.detailsFor(book.id), isNull);
    });

    test('a Gutenberg download gets details and the Open Library cover', () async {
      final covers = _Covers();
      final changed = await keepFindDetails(
        repo: repo,
        importer: importer,
        covers: covers,
        book: book,
        found: found,
        sourceName: 'Project Gutenberg',
        info: Future.value(info),
      );
      expect(changed, isTrue);
      expect(covers.asked.single.toString(), contains('14348537-L.jpg'));
      final saved = (await repo.getBook(book.id))!;
      expect(File(saved.coverPath!).lengthSync(), greaterThan(2000));
      expect((await repo.detailsFor(book.id))!.ratingCount, 416);
    });

    test('a failed lookup still keeps what the source said', () async {
      final changed = await keepFindDetails(
        repo: repo,
        importer: importer,
        covers: _Covers(),
        book: book,
        found: found,
        sourceName: 'Project Gutenberg',
        info: Future.error(const WebError('offline')),
      );
      expect(changed, isFalse);
      final d = (await repo.detailsFor(book.id))!;
      expect(d.summary, 'A novel.');
      expect(d.lookedUp, isFalse);
    });
  });
}
