import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:twofold/features/reader/epub_book.dart';
import 'package:twofold/features/reader/epub_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List _zip(Map<String, String> files) {
  final a = Archive();
  files.forEach((name, body) {
    final bytes = utf8.encode(body);
    a.addFile(ArchiveFile(name, bytes.length, bytes));
  });
  return Uint8List.fromList(ZipEncoder().encode(a));
}

const _container = '''<container><rootfiles>
  <rootfile full-path="OEBPS/content.opf"/></rootfiles></container>''';
const _opf = '''<package><manifest>
  <item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>
  <item id="one" href="text/one.xhtml"/>
  <item id="two" href="text/two%20b.xhtml"/>
</manifest><spine><itemref idref="two"/><itemref idref="one"/></spine></package>''';
const _ncx = '''<ncx><navMap><navPoint><navLabel><text>Second file</text></navLabel>
  <content src="text/one.xhtml#a"/></navPoint></navMap></ncx>''';

void main() {
  final epub = _zip({
    'META-INF/container.xml': _container,
    'OEBPS/content.opf': _opf,
    'OEBPS/toc.ncx': _ncx,
    'OEBPS/text/one.xhtml':
        '<html><body><h1>Chapter</h1><p>Plain <i>italic</i>&nbsp;<b>bold</b>.</p></body></html>',
    'OEBPS/text/two b.xhtml':
        '<html><head><title>x</title></head><body><p>First   page\n text.<br/>Next</p><ul><li>Item</li></ul></body></html>',
  });

  test('reads pages in spine order, with styles and contents', () {
    final doc = parseEpub(epub);
    final text = doc.blocks.map((b) => b.runs.map((r) => r.text).join()).toList();
    expect(text[0], 'First page text.\nNext');
    expect(text[1], '•  Item');
    expect(text[2], 'Chapter');
    expect(doc.blocks[2].level, 1);
    expect(text[3], contains('italic'));
    expect(doc.blocks[3].runs.any((r) => r.italic && r.text == 'italic'), isTrue);
    expect(doc.blocks[3].runs.any((r) => r.bold && r.text == 'bold'), isTrue);
    expect(doc.toc.single.title, 'Second file');
    expect(doc.toc.single.block, 2);
  });

  test('a page that is not valid XML still gives text', () {
    final doc = parseEpub(_zip({
      'META-INF/container.xml': _container,
      'OEBPS/content.opf': _opf,
      'OEBPS/text/one.xhtml': '<html><body><p>Broken<br>tag &amp; more</p></html',
    }));
    expect(doc.blocks.first.runs.first.text, 'Broken');
    expect(doc.blocks[1].runs.first.text, 'tag & more');
  });

  test('a book with a broken package still opens', () {
    final doc = parseEpub(_zip({'chapter1.html': '<html><body><p>Hi</p></body></html>'}));
    expect(doc.blocks.single.runs.single.text, 'Hi');
  });

  test('a file with no text is refused', () {
    expect(() => parseEpub(_zip({'a.txt': 'x'})), throwsFormatException);
  });

  test('a title without heading tags is recognised, prose is not', () {
    expect(EpubBlock.text(const [TextRun('Prologue')]).asOpening().level, 1);
    expect(EpubBlock.text(const [TextRun('It was a dark night.')]).asOpening().level, 0);
  });

  testWidgets('each section starts a new page', (tester) async {
    final doc = EpubDoc([
      const EpubBlock.text([TextRun('Foreword')], level: 1, opensSection: true),
      const EpubBlock.text([TextRun('Short text.')]),
      const EpubBlock.text([TextRun('Chapter 1')], level: 1, opensSection: true),
      const EpubBlock.text([TextRun('More.')]),
    ], const []);
    final pages = (await tester.runAsync(() => paginate(
        doc, const Size(320, 500), const TextSettings(18, 1.55), const {})))!;
    expect(pages.length, 2);
    expect(pages[1].first.block, 2);
    expect(pages[1].first.top, 50, reason: 'room above the title');
  });

  testWidgets('pages hold all the text, in order, and fit', (tester) async {
    final words = List.generate(4000, (i) => 'word$i').join(' ');
    final doc = EpubDoc([
      EpubBlock.text([const TextRun('Title')], level: 1),
      EpubBlock.text([TextRun(words)]),
      for (var i = 0; i < 200; i++)
        EpubBlock.text([
          TextRun('Short paragraph $i, '),
          TextRun('with italics ' * (i % 7), italic: true),
        ]),
      EpubBlock.text([const TextRun('The end.')]),
    ], const []);
    const size = Size(320, 500);
    const settings = TextSettings(18, 1.55);
    final pages = (await tester.runAsync(
        () => paginate(doc, size, settings, const {})))!;

    expect(pages.length, greaterThan(5));
    final rebuilt = StringBuffer();
    for (final page in pages) {
      for (final s in page.where((s) => s.block == 1)) {
        rebuilt.write(blockSpan(doc.blocks[1], s.start, s.end, const TextStyle()).toPlainText());
      }
    }
    expect(rebuilt.toString(), words);
    expect(pages.last.last.block, doc.blocks.length - 1);

    // Every line of every page fits, measured the way it is drawn.
    for (final page in pages) {
      for (final slice in page) {
        final block = doc.blocks[slice.block];
        final painter = TextPainter(
          text: blockSpan(block, slice.start, slice.end, blockStyle(block, settings)),
          textDirection: TextDirection.ltr,
          textScaler: TextScaler.noScaling,
        )..layout(maxWidth: size.width);
        expect(slice.top + painter.height, lessThanOrEqualTo(size.height));
        painter.dispose();
      }
    }

    // A position finds its page again after a font change.
    final mid = pages[3].first;
    expect(pageOf(pages, mid.block, mid.start), 3);
  });
}
