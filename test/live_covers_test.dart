import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:twofold/find/cover_source.dart';
import 'package:twofold/find/find_service.dart';
import 'package:twofold/audio/downloads.dart';
import 'package:twofold/find/librivox.dart';
import 'package:twofold/find/web.dart';

/// Talks to the real sites. Run by hand only: LIVE=1 flutter test test/live_covers_test.dart
void main() {
  final live = Platform.environment['LIVE'] == '1';

  test('Open Library covers for a real book', () async {
    final web = Web();
    final covers = CoverService(web);
    final list = await covers.search('Pride and Prejudice', 'Jane Austen');
    expect(list.length, greaterThan(5));
    final bytes = await covers.image(list.first.thumb);
    expect(bytes, isNotNull);
    final full = await covers.image(list.first.full);
    expect(full!.length, greaterThan(bytes!.length));
    web.close();
  }, skip: !live, timeout: const Timeout(Duration(minutes: 1)));

  test('Unglue.it lists books with free EPUBs', () async {
    final web = Web();
    final source = unglueSource(web);
    final shelves = await source.shelves();
    expect(shelves, isNotEmpty);
    final page = await source.browse(shelves.first);
    expect(page.books, isNotEmpty);
    final targets = await source.targets(page.books.first);
    expect(targets, isNotEmpty);
    web.close();
  }, skip: !live, timeout: const Timeout(Duration(minutes: 2)));

  test('LibriVox finds the matching recording and its first part is an MP3', () async {
    final web = Web();
    final found = await LibrivoxService(web)
        .find('Pride and Prejudice', author: 'Jane Austen', gutenbergId: '1342');
    expect(found.first.gutenbergId, '1342');
    expect(found.first.parts, isNotEmpty);
    final bytes = await web.getBytes(found.first.parts.first.url, maxBytes: 40 << 20);
    expect(looksLikeMp3(bytes), isTrue);
    web.close();
  }, skip: !live, timeout: const Timeout(Duration(minutes: 3)));
}
