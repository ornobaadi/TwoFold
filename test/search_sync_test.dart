import 'package:twofold/data/book_repo.dart';
import 'package:twofold/data/db.dart';
import 'package:twofold/data/models.dart';
import 'package:twofold/features/reader/epub_book.dart';
import 'package:twofold/features/reader/search.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  group('search', () {
    test('ignores case, curly quotes and extra space', () {
      final m = findMatches('He said: “Never  Stop\ndreaming” today', '"never stop dreaming"');
      expect(m.length, 1);
      expect(m.single.$1, 9);
    });

    test('finds words split by a hyphen at a line break', () {
      expect(findMatches('the pro-\nject began', 'project').length, 1);
    });

    test('finds every match and returns original offsets', () {
      const text = 'Café  one, CAFÉ two';
      final m = findMatches(text, 'café');
      expect(m.map((e) => text.substring(e.$1, e.$1 + e.$2).toLowerCase()), ['café', 'café']);
    });

    test('an empty query finds nothing', () {
      expect(findMatches('abc', '   '), isEmpty);
    });

    test('snippet marks the match', () {
      final hit = makeHit('${'a' * 100} needle ${'b' * 100}', (101, 6),
          pageLabel: 'Page 1', location: '0:101', fraction: 0);
      expect(hit.snippet.substring(hit.matchStart, hit.matchStart + hit.matchLength), 'needle');
      expect(hit.snippet, startsWith('…'));
      expect(hit.snippet, endsWith('…'));
    });

    test('real book: search finds Alice text', () async {
      final doc = await loadEpubFile('test/fixtures/alice.epub');
      final all = doc.blocks.map((b) => b.runs.map((r) => r.text).join()).join('\n');
      expect(findMatches(all, 'white rabbit'), isNotEmpty);
    });
  });

  test('marks are saved per book, newest first, and deleted with it', () async {
    final db = await openTwoFoldDb(path: inMemoryDatabasePath, factory: databaseFactoryFfi);
    final repo = BookRepo(db);
    await repo.insertBook(const Book(id: 'b', title: 'T', format: 'pdf', filePath: 'x', addedAt: 1));
    PlaceMark mark(String id, int at) => PlaceMark(
        id: id, bookId: 'b', location: '3', percent: 0.1, pageLabel: '3 / 30',
        audioMs: 5000, createdAt: at, synced: id == 'new');
    await repo.addMark(mark('old', 1));
    await repo.addMark(mark('new', 2));
    final got = await repo.marksFor('b');
    expect(got.map((m) => m.id), ['new', 'old']);
    expect(got.first.synced, isTrue);
    expect(got.last.audioMs, 5000);
    await repo.deleteMark('old');
    expect((await repo.marksFor('b')).length, 1);
    await repo.deleteBook('b');
    expect(await repo.marksFor('b'), isEmpty);
    await db.close();
  });
}
