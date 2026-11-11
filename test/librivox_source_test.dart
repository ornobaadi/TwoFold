import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:twofold/features/find/find_screen.dart' show LengthFilter, recordingLine;
import 'package:twofold/find/book_source.dart';
import 'package:twofold/find/librivox_source.dart';
import 'package:twofold/find/web.dart';

/// Answers every LibriVox question with the saved Pride and Prejudice answer,
/// or "not found" for title searches when [titlesEmpty].
class _Web extends Web {
  _Web({this.titlesEmpty = false});

  final bool titlesEmpty;
  final asked = <Uri>[];

  @override
  Future<String> getText(Uri url, {int maxBytes = 4 << 20, Duration timeout = const Duration(seconds: 25)}) async {
    asked.add(url);
    if (titlesEmpty && url.queryParameters.containsKey('title')) {
      throw const WebError('not found', notFound: true);
    }
    return File('test/fixtures/find/librivox_pride.json').readAsStringSync();
  }
}

void main() {
  test('search lists recordings with reader, length and size', () async {
    final web = _Web();
    final page = await LibrivoxSource(web).search('Pride and Prejudice');
    expect(web.asked.first.queryParameters['title'], '^Pride and Prejudice');
    expect(page.books, isNotEmpty);
    final b = page.books.first;
    expect(b.isRecording, isTrue);
    expect(recordingLine(b), contains('Read by'));
    expect(recordingLine(b), contains('MB'));
  });

  test('few title matches: the words are tried as an author too, without repeats', () async {
    final web = _Web(titlesEmpty: true);
    final page = await LibrivoxSource(web).search('Jane Austen');
    expect(page.books, isNotEmpty);
    expect(web.asked.any((u) => u.queryParameters['author'] == 'Austen'), isTrue);
    expect(page.books.map((b) => b.id).toSet().length, page.books.length);
  });

  test('author lists and new recordings ask the right way', () async {
    final web = _Web();
    final src = LibrivoxSource(web, now: () => DateTime.utc(2026, 11, 11));
    await src.browse(LibrivoxSource.lists[1]);
    expect(web.asked.last.queryParameters['author'], 'Austen');
    await src.browse(LibrivoxSource.lists.first, page: 2);
    expect(int.parse(web.asked.last.queryParameters['since']!),
        DateTime.utc(2026, 8, 13).millisecondsSinceEpoch ~/ 1000);
    expect(web.asked.last.queryParameters['offset'], '40');
  });

  test('Get brings the Gutenberg text the recording was read from', () async {
    final src = LibrivoxSource(_Web());
    final page = await src.search('Pride and Prejudice');
    final withText = page.books.firstWhere((b) => src.recording(b.id)!.gutenbergId == '1342');
    final targets = await src.targets(withText);
    expect(targets.first.url.toString(), 'https://www.gutenberg.org/ebooks/1342.epub3.images');
    expect(
      () => src.targets(const FoundBook(source: 'librivox', id: 'unknown', title: 'X')),
      throwsA(isA<WebError>()),
    );
  });

  test('length filter', () {
    FoundBook rec(int h) => FoundBook(source: 'librivox', id: '$h', title: 't', listenLength: Duration(hours: h));
    expect(LengthFilter.short.keeps(rec(2)), isTrue);
    expect(LengthFilter.short.keeps(rec(5)), isFalse);
    expect(LengthFilter.medium.keeps(rec(5)), isTrue);
    expect(LengthFilter.long.keeps(rec(13)), isTrue);
    const book = FoundBook(source: 'gutenberg', id: '1', title: 'b');
    expect(LengthFilter.short.keeps(book), isTrue, reason: 'books have no length');
  });
}
