import 'package:twofold/data/book_repo.dart';
import 'package:twofold/data/db.dart';
import 'package:twofold/data/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  late Database db;
  late BookRepo repo;

  const book = Book(
    id: 'b1',
    title: 'Dune',
    format: 'epub',
    filePath: '/books/b1/dune.epub',
    addedAt: 1,
  );

  setUp(() async {
    db = await openTwoFoldDb(path: inMemoryDatabasePath, factory: databaseFactoryFfi);
    repo = BookRepo(db);
    await repo.insertBook(book);
  });

  tearDown(() => db.close());

  test('audio save creates the row and restores exactly', () async {
    await repo.saveAudio('b1', trackIndex: 2, audioMs: 123456, speed: 1.25);
    final p = (await repo.getProgress('b1'))!;
    expect(p.trackIndex, 2);
    expect(p.audioMs, 123456);
    expect(p.speed, 1.25);
    expect(p.readLocation, isNull);
  });

  test('a page turn does not overwrite the audio position', () async {
    await repo.saveAudio('b1', trackIndex: 1, audioMs: 5000, speed: 1.5);
    await repo.saveReading('b1', location: 'epubcfi(/6/4)', percent: 0.12);
    final p = (await repo.getProgress('b1'))!;
    expect(p.readLocation, 'epubcfi(/6/4)');
    expect(p.readPercent, 0.12);
    expect(p.trackIndex, 1);
    expect(p.audioMs, 5000);
    expect(p.speed, 1.5);
  });

  test('an audio save does not overwrite the reading position', () async {
    await repo.saveReading('b1', location: '33', percent: 0.08);
    await repo.saveAudio('b1', trackIndex: 0, audioMs: 900, speed: 1.0);
    final p = (await repo.getProgress('b1'))!;
    expect(p.readLocation, '33');
    expect(p.audioMs, 900);
  });

  test('tracks come back in playlist order and setTracks replaces them', () async {
    AudioTrack t(String id, int pos) =>
        AudioTrack(id: id, bookId: 'b1', filePath: '/a/$id.mp3', position: pos);
    await repo.setTracks('b1', [t('c', 2), t('a', 0), t('b', 1)]);
    expect((await repo.tracksFor('b1')).map((e) => e.id), ['a', 'b', 'c']);

    await repo.setTracks('b1', [t('x', 0)]);
    expect((await repo.tracksFor('b1')).map((e) => e.id), ['x']);
  });

  test('deleting a book removes its tracks and progress', () async {
    await repo.setTracks('b1', [
      const AudioTrack(id: 'a', bookId: 'b1', filePath: '/a.mp3', position: 0),
    ]);
    await repo.saveAudio('b1', trackIndex: 0, audioMs: 1, speed: 1.0);
    await repo.deleteBook('b1');
    expect(await repo.tracksFor('b1'), isEmpty);
    expect(await repo.getProgress('b1'), isNull);
  });

  test('settings round trip', () async {
    expect(await repo.getSetting('skip'), isNull);
    await repo.setSetting('skip', '10');
    await repo.setSetting('skip', '15');
    expect(await repo.getSetting('skip'), '15');
  });
}
