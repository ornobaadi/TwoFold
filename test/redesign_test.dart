import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:twofold/data/book_repo.dart';
import 'package:twofold/data/db.dart';
import 'package:twofold/data/models.dart';
import 'package:twofold/features/library/book_card.dart';
import 'package:twofold/features/library/library_screen.dart';
import 'package:twofold/features/welcome/welcome_screen.dart';
import 'package:twofold/find/book_source.dart';
import 'package:twofold/find/everything_source.dart';
import 'package:twofold/find/librivox_source.dart';
import 'package:twofold/find/web.dart';

class _Web extends Web {
  @override
  Future<String> getText(Uri url, {int maxBytes = 4 << 20, Duration timeout = const Duration(seconds: 25)}) async =>
      File('test/fixtures/find/librivox_pride.json').readAsStringSync();
}

class _Books extends BookSource {
  _Books({this.fail = false});
  final bool fail;
  @override
  String get id => 'gutenberg';
  @override
  String get name => 'Project Gutenberg';
  @override
  String get blurb => '';
  @override
  Future<FoundPage> search(String query, {int page = 0}) async {
    if (fail) throw const WebError('offline');
    return const FoundPage([
      FoundBook(source: 'gutenberg', id: '946', title: 'Lady Susan', author: 'Jane Austen'),
      FoundBook(source: 'gutenberg', id: '1342', title: 'Pride and Prejudice', author: 'Jane Austen'),
    ], hasMore: false);
  }

  @override
  Future<List<DownloadTarget>> targets(FoundBook book) async => const [];
}

void main() {
  sqfliteFfiInit();

  test('one search: a Gutenberg book carries its recording and comes first', () async {
    final all = EverythingSource(gutenberg: _Books(), recordings: LibrivoxSource(_Web()));
    final page = await all.search('pride');
    final pride = page.books.first;
    expect(pride.source, 'gutenberg');
    expect(pride.id, '1342');
    expect(pride.isRecording, isTrue);
    expect(pride.recordingId, isNotNull);
    expect(page.books.where((b) => b.id == '946').single.isRecording, isFalse);
    expect(page.books.where((b) => b.source == 'librivox' && b.id == pride.recordingId), isEmpty,
        reason: 'the recording is not listed twice');
  });

  test('one library failing still gives the others', () async {
    final all = EverythingSource(gutenberg: _Books(fail: true), recordings: LibrivoxSource(_Web()));
    final page = await all.search('pride');
    expect(page.books, isNotEmpty);
    expect(page.books.every((b) => b.isRecording), isTrue);
  });

  test('shelf filters: with audio and downloaded', () {
    const book = Book(id: 'b', title: 't', format: 'epub', filePath: '/x', addedAt: 1);
    const online = AudioTrack(id: '1', bookId: 'b', filePath: 'https://archive.org/download/x/1.mp3', position: 0, remoteUrl: 'https://archive.org/download/x/1.mp3');
    const local = AudioTrack(id: '2', bookId: 'b', filePath: '/a/1.mp3', position: 0);
    const none = LibraryEntry(book, null, []);
    const streams = LibraryEntry(book, null, [online]);
    const saved = LibraryEntry(book, null, [local]);
    expect(ShelfFilter.audio.keeps(none), isFalse);
    expect(ShelfFilter.audio.keeps(streams), isTrue);
    expect(ShelfFilter.downloaded.keeps(streams), isFalse);
    expect(ShelfFilter.downloaded.keeps(saved), isTrue);
  });

  test('welcome shows on a new install only, once', () async {
    final repo = BookRepo(await openTwoFoldDb(path: inMemoryDatabasePath, factory: databaseFactoryFfi));
    expect(await shouldWelcome(repo), isTrue);
    await repo.setSetting(welcomedKey, 'true');
    expect(await shouldWelcome(repo), isFalse);

    final old = BookRepo(await openTwoFoldDb(path: inMemoryDatabasePath, factory: databaseFactoryFfi));
    await old.insertBook(const Book(id: 'mine', title: 'Mine', format: 'epub', filePath: '/m', addedAt: 1));
    expect(await shouldWelcome(old), isFalse, reason: 'someone updating already has books');
  });
}
