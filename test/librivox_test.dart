import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:twofold/audio/audio_handler.dart';
import 'package:twofold/audio/downloads.dart';
import 'package:twofold/data/book_repo.dart';
import 'package:twofold/data/db.dart';
import 'package:twofold/data/models.dart';
import 'package:twofold/find/librivox.dart';

List<LibrivoxBook> _pride() => parseLibrivoxFeed(
      jsonDecode(File('test/fixtures/find/librivox_pride.json').readAsStringSync())
          as Map<String, dynamic>,
    );

/// Android's downloader, played by the test.
class _FakeChannel implements DownloadChannel {
  _FakeChannel(this.dir);

  final String dir;
  final enqueued = <int, ({String url, String path, bool wifiOnly})>{};
  final states = <int, DownloadState>{};
  final removed = <int>[];
  var _next = 1;

  @override
  Future<int> enqueue({
    required String url,
    required String path,
    required String title,
    required bool wifiOnly,
  }) async {
    final id = _next++;
    enqueued[id] = (url: url, path: path, wifiOnly: wifiOnly);
    states[id] = DownloadState(id, 'running');
    return id;
  }

  /// Android finishes [id], writing [bytes] where it was asked to.
  void finish(int id, List<int> bytes) {
    final f = File('$dir/${enqueued[id]!.path}')..createSync(recursive: true);
    f.writeAsBytesSync(bytes);
    states[id] = DownloadState(id, 'done', bytes: bytes.length, total: bytes.length, file: f.path);
  }

  @override
  Future<List<DownloadState>> status(List<int> ids) async =>
      [for (final id in ids) states[id] ?? DownloadState(id, 'gone')];

  @override
  Future<void> remove(List<int> ids) async => removed.addAll(ids);

  @override
  Future<String> folder() async => dir;
}

/// 200 KB that start like an MP3.
List<int> _mp3() => [0x49, 0x44, 0x33, ...List.filled(200 * 1024, 0)];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  group('feed', () {
    test('real answer: finished recordings with parts, readers and Gutenberg id', () {
      final list = _pride();
      // Eight in the answer; the one still being recorded (no length) is left out.
      expect(list.length, 7);
      final first = list.first;
      expect(first.title, 'Pride and Prejudice');
      expect(first.gutenbergId, '1342');
      expect(first.parts.length, 37);
      expect(first.parts.first.title, 'Chapters 1-3');
      expect(first.parts.first.url.toString(),
          startsWith('https://archive.org/download/pride_and_prejudice_librivox/'));
      expect(first.parts.first.duration, const Duration(seconds: 1132));
      expect(first.readers.length, 13);
      expect(first.readerLine, '13 readers');
      expect(list[1].readerLine, 'Annie Coleman Rothenberg');
      expect(first.bytes, greaterThan(300 * 1000 * 1000));
    });

    test('Gutenberg ids from either kind of link', () {
      expect(gutenbergIdIn('https://www.gutenberg.org/etext/1342'), '1342');
      expect(gutenbergIdIn('http://www.gutenberg.org/ebooks/84'), '84');
      expect(gutenbergIdIn('https://en.wikisource.org/wiki/X'), isNull);
    });

    test('only archive.org files, always over https', () {
      expect(archiveUrl('http://www.archive.org/download/a/b.mp3').toString(),
          'https://archive.org/download/a/b.mp3');
      expect(archiveUrl('https://example.org/b.mp3'), isNull);
    });

    test('ranking: same edition, one reader, not dramatic, other books last', () {
      final ranked = rankRecordings(_pride(), author: 'Jane Austen', gutenbergId: '1342');
      expect(ranked.first.gutenbergId, '1342');
      expect(ranked.first.solo, isTrue);
      // The play adaptation is a different Gutenberg book: after all real matches.
      expect(ranked.last.title, contains('A Play'));
      final dramatic = ranked.indexWhere((b) => b.dramatic);
      final group = ranked.indexWhere((b) => !b.solo && !b.dramatic && b.gutenbergId == '1342');
      expect(dramatic, greaterThan(group));
    });
  });

  group('playing', () {
    const remote = AudioTrack(
      id: 't',
      bookId: 'b',
      filePath: '/gone/001.mp3',
      position: 0,
      remoteUrl: 'https://archive.org/download/x/1.mp3',
    );

    test('a saved part plays from the phone, a missing one from online', () {
      expect(playablePath(remote, exists: (_) => true), '/gone/001.mp3');
      expect(playablePath(remote, exists: (_) => false), remote.remoteUrl);
    });

    test('own audio is untouched', () {
      const own = AudioTrack(id: 'o', bookId: 'b', filePath: 'content://x/1', position: 0);
      expect(playablePath(own, exists: (_) => false), 'content://x/1');
    });

    test('mp3 signature', () {
      expect(looksLikeMp3([0x49, 0x44, 0x33, 4]), isTrue);
      expect(looksLikeMp3([0xFF, 0xFB, 0x90]), isTrue);
      expect(looksLikeMp3([0x3C, 0x68, 0x74]), isFalse, reason: 'an HTML error page');
    });
  });

  group('saving for offline', () {
    late BookRepo repo;
    late Directory dir;
    late _FakeChannel channel;
    late AudiobookDownloads downloads;
    const book = Book(
      id: 'b',
      title: 'Pride and Prejudice',
      author: 'Jane Austen',
      format: 'epub',
      filePath: '/x.epub',
      addedAt: 1,
    );

    setUp(() async {
      dir = Directory.systemTemp.createTempSync('twofold_dl');
      final db = await openTwoFoldDb(path: inMemoryDatabasePath, factory: databaseFactoryFfi);
      repo = BookRepo(db);
      channel = _FakeChannel(dir.path);
      downloads = AudiobookDownloads(repo, channel, atOnce: 2);
      await repo.insertBook(book);
      await repo.setAudiobook(
        const Audiobook(bookId: 'b', source: 'librivox', sourceId: '254', reader: 'Annie', parts: 3, addedAt: 1),
        [
          for (var i = 0; i < 3; i++)
            AudioTrack(
              id: 't$i',
              bookId: 'b',
              filePath: 'https://archive.org/download/x/$i.mp3',
              remoteUrl: 'https://archive.org/download/x/$i.mp3',
              position: i,
              durationMs: 60000,
              title: 'Chapter ${i + 1}',
            ),
        ],
      );
    });

    test('a book with a recording keeps who reads it', () async {
      final a = (await repo.audiobookFor('b'))!;
      expect(a.reader, 'Annie');
      expect((await repo.tracksFor('b')).every((t) => t.isRemote), isTrue);
    });

    test('parts are saved in order, a few at a time, and then played locally', () async {
      await downloads.saveAll('b');
      expect(channel.enqueued.length, 2, reason: 'two at once');
      expect(channel.enqueued[1]!.url, endsWith('/0.mp3'), reason: 'first part first');
      expect(channel.enqueued[1]!.wifiOnly, isTrue);

      channel.finish(1, _mp3());
      await downloads.refresh();
      var tracks = await repo.tracksFor('b');
      expect(tracks[0].isRemote, isFalse);
      expect(File(tracks[0].filePath).existsSync(), isTrue);
      expect(channel.enqueued.length, 3, reason: 'the next part is queued');

      channel.finish(2, _mp3());
      channel.finish(3, _mp3());
      await downloads.refresh();
      tracks = await repo.tracksFor('b');
      expect(tracks.every((t) => !t.isRemote), isTrue);
      final p = await downloads.progress('b');
      expect(p.complete, isTrue);
      expect(p.saving, isFalse);
    });

    test('a page that is not audio is thrown away, tried once more, then left', () async {
      await downloads.saveAll('b');
      final page = utf8.encode('<html>${'x' * 200000}</html>');
      channel.finish(1, page);
      await downloads.refresh();
      var t = (await repo.tracksFor('b')).first;
      expect(t.isRemote, isTrue, reason: 'still streams');
      expect(File('${dir.path}/b/001.mp3').existsSync(), isFalse);
      expect(t.downloadId, isNotNull, reason: 'one more try');

      channel.finish(t.downloadId!, page);
      await downloads.refresh();
      t = (await repo.tracksFor('b')).first;
      expect(t.downloadId, isNull);
      expect(await downloads.wantsSaving('b'), isFalse, reason: 'no endless retries');
    });

    test('pause keeps saved parts; remove makes them stream again', () async {
      await downloads.saveAll('b');
      channel.finish(1, _mp3());
      await downloads.refresh();
      await downloads.pause('b');
      expect(channel.removed, isNotEmpty);
      expect(await downloads.wantsSaving('b'), isFalse);
      expect((await repo.tracksFor('b')).first.isRemote, isFalse);

      await downloads.removeSaved('b');
      final tracks = await repo.tracksFor('b');
      expect(tracks.every((t) => t.isRemote), isTrue);
    });

    test('removing the book removes its recording too', () async {
      await repo.deleteBook('b');
      expect(await repo.audiobookFor('b'), isNull);
    });
  });
}
