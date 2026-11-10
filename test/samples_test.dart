import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:twofold/data/book_repo.dart';
import 'package:twofold/data/db.dart';
import 'package:twofold/features/reader/epub_book.dart';
import 'package:twofold/import/importer.dart';
import 'package:twofold/import/samples.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  test('samples arrive once, stay removed, and can be brought back', () async {
    final tmp = Directory.systemTemp.createTempSync('twofold').path;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (_) async => tmp);
    final db = await openTwoFoldDb(
        path: inMemoryDatabasePath, factory: databaseFactoryFfi);
    final repo = BookRepo(db);

    expect(await addSampleBooks(repo), 1);
    expect((await repo.allBooks()).map((b) => b.title),
        sampleBooks.map((s) => s.title));
    for (final s in sampleBooks) {
      final book = (await repo.getBook(s.id))!;
      expect(File(book.coverPath!).existsSync(), isTrue);
      final doc = await loadEpubFile(book.filePath);
      expect(doc.blocks.length, greaterThan(10));
      final tracks = await repo.tracksFor(s.id);
      expect(File(tracks.single.filePath).lengthSync(), greaterThan(1000000));
      expect(tracks.single.durationMs, s.audioMs);
    }

    await Importer(repo).removeBook(sampleBooks.first.id);
    expect(await addSampleBooks(repo), 0, reason: 'a removed sample stays gone');
    expect(await repo.getBook(sampleBooks.first.id), isNull);

    expect(await addSampleBooks(repo, again: true), 1);
    expect(await repo.getBook(sampleBooks.first.id), isNotNull);
    await db.close();
  });
}
