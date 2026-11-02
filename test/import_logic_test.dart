import 'dart:convert';
import 'dart:typed_data';

import 'package:twofold/audio/chapters.dart';
import 'package:twofold/import/importer.dart';
import 'package:twofold/import/names.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('natural order puts part 2 before part 10', () {
    final names = ['Part 10.mp3', 'part 2.mp3', 'Part 1.mp3']
      ..sort(naturalCompare);
    expect(names, ['Part 1.mp3', 'part 2.mp3', 'Part 10.mp3']);
  });

  test('stored audio names give back a readable title', () {
    expect(trackTitle('/x/${storedAudioName('abc', 'the_book-part_2.m4b')}'),
        'the book part 2');
  });

  test('reads title, author and both cover styles from the OPF', () {
    const epub3 = '''<package xmlns:dc="http://purl.org/dc/elements/1.1/">
      <metadata><dc:title> Dune </dc:title><dc:creator>Frank Herbert</dc:creator></metadata>
      <manifest><item id="a" href="c.jpg" properties="cover-image"/></manifest>
    </package>''';
    final m = parseOpf(epub3);
    expect(m.title, 'Dune');
    expect(m.author, 'Frank Herbert');
    expect(m.coverHref, 'c.jpg');

    const epub2 = '''<package><metadata><meta name="cover" content="x"/></metadata>
      <manifest><item id="x" href="img/cover.png"/></manifest></package>''';
    expect(parseOpf(epub2).coverHref, 'img/cover.png');
    expect(parseOpf(epub2).title, isNull);
  });

  group('audio chapters', () {
    Uint8List chpl(Map<String, int> chapters) {
      final b = BytesBuilder()
        ..add([1, 0, 0, 0, 0, 0, 0, 0, chapters.length]);
      chapters.forEach((title, seconds) {
        final d = ByteData(8)..setUint64(0, seconds * 10000000);
        final t = utf8.encode(title);
        b
          ..add(d.buffer.asUint8List())
          ..addByte(t.length)
          ..add(t);
      });
      return b.toBytes();
    }

    test('parses Nero chapters', () {
      final list = parseChpl(chpl({'One': 0, 'Two': 90}));
      expect(list.map((c) => c.title), ['One', 'Two']);
      expect(list[1].start, const Duration(seconds: 90));
    });

    test('truncated data does not throw', () {
      expect(parseChpl(Uint8List(2)), isEmpty);
      final cut = chpl({'One': 0});
      expect(parseChpl(cut.sublist(0, cut.length - 2)), isEmpty);
    });

    test('finds the chapter for a position', () {
      const list = [
        AudioChapter('a', Duration.zero),
        AudioChapter('b', Duration(seconds: 10)),
      ];
      expect(chapterIndexAt(list, const Duration(seconds: 9)), 0);
      expect(chapterIndexAt(list, const Duration(seconds: 10)), 1);
      expect(chapterIndexAt(const [], Duration.zero), -1);
    });
  });
}
