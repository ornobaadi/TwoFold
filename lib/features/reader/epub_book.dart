import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';

class TextRun {
  const TextRun(this.text, {this.bold = false, this.italic = false});

  final String text;
  final bool bold;
  final bool italic;
}

/// A paragraph, heading ([level] 1-6) or image of a book.
class EpubBlock {
  const EpubBlock.text(this.runs, {this.level = 0, this.opensSection = false})
    : image = null;
  const EpubBlock.image(Uint8List this.image, {this.opensSection = false})
    : runs = const [],
      level = 0;

  final List<TextRun> runs;
  final int level;
  final Uint8List? image;

  /// First block of a file in the book: a chapter, prologue, foreword and so
  /// on, which starts on a new page.
  final bool opensSection;

  EpubBlock asOpening() {
    final img = image;
    if (img != null) return EpubBlock.image(img, opensSection: true);
    final text = runs.map((r) => r.text).join().trim();
    // Many books style their chapter titles with CSS instead of heading tags.
    final looksLikeTitle =
        level == 0 &&
        text.length <= 40 &&
        !RegExp(r'[.,;:!?…"”]$').hasMatch(text);
    return EpubBlock.text(
      runs,
      level: looksLikeTitle ? 1 : level,
      opensSection: true,
    );
  }

  int get length => runs.fold(0, (sum, r) => sum + r.text.length);
}

class TocEntry {
  const TocEntry(this.title, this.depth, this.block);

  final String title;
  final int depth;

  /// Index of the first block of this entry.
  final int block;
}

class EpubDoc {
  const EpubDoc(this.blocks, this.toc);

  final List<EpubBlock> blocks;
  final List<TocEntry> toc;
}

const _blockTags = {
  'address',
  'article',
  'aside',
  'blockquote',
  'body',
  'center',
  'dd',
  'div',
  'dl',
  'dt',
  'figcaption',
  'figure',
  'footer',
  'h1',
  'h2',
  'h3',
  'h4',
  'h5',
  'h6',
  'header',
  'hr',
  'li',
  'main',
  'nav',
  'ol',
  'p',
  'pre',
  'section',
  'table',
  'tbody',
  'td',
  'th',
  'thead',
  'tr',
  'ul',
};
const _skipTags = {'head', 'script', 'style', 'title'};

/// Reads the EPUB at [path] on a background isolate. Top level on purpose: a
/// closure made inside a widget's method can capture the widget, which can't
/// be sent to an isolate.
Future<EpubDoc> loadEpubFile(String path) =>
    Isolate.run(() => parseEpub(File(path).readAsBytesSync()));

/// Reads an EPUB into plain blocks. Throws if there is no readable text.
EpubDoc parseEpub(Uint8List bytes) {
  final archive = ZipDecoder().decodeBytes(bytes);
  final files = {
    for (final f in archive.files)
      if (f.isFile) f.name: f,
  };
  final lower = {for (final n in files.keys) n.toLowerCase(): n};

  ArchiveFile? find(String path) =>
      files[path] ?? files[lower[path.toLowerCase()]];
  String? read(String path) {
    final f = find(path);
    return f == null ? null : _decode(f.content);
  }

  final order = <String>[];
  final tocSources = <({String path, bool ncx})>[];
  try {
    final container = XmlDocument.parse(read('META-INF/container.xml')!);
    final opfPath = _elements(
      container,
      'rootfile',
    ).first.getAttribute('full-path')!;
    final opf = XmlDocument.parse(read(opfPath)!);
    final base = p.posix.dirname(opfPath);
    final manifest = <String, String>{};
    for (final item in _elements(opf, 'item')) {
      final href = item.getAttribute('href');
      if (href == null) continue;
      final path = _resolve(base, href);
      manifest[item.getAttribute('id') ?? path] = path;
      if ((item.getAttribute('properties') ?? '').split(' ').contains('nav')) {
        tocSources.add((path: path, ncx: false));
      }
      if (item.getAttribute('media-type') == 'application/x-dtbncx+xml') {
        tocSources.add((path: path, ncx: true));
      }
    }
    for (final ref in _elements(opf, 'itemref')) {
      final path = manifest[ref.getAttribute('idref')];
      if (path != null) order.add(path);
    }
  } catch (_) {
    // A broken package file should not stop the book: read its pages in order.
  }
  if (order.isEmpty) {
    order.addAll(
      files.keys.where(
        (n) => RegExp(r'\.(x?html?)$', caseSensitive: false).hasMatch(n),
      ),
    );
    order.sort();
  }

  final blocks = <EpubBlock>[];
  final firstBlock = <String, int>{};
  for (final path in order) {
    final html = read(path);
    if (html == null) continue;
    firstBlock.putIfAbsent(path.toLowerCase(), () => blocks.length);
    final page = _parsePage(html, p.posix.dirname(path), find);
    if (page.isNotEmpty) page[0] = page[0].asOpening();
    blocks.addAll(page);
  }
  if (!blocks.any((b) => b.length > 0 || b.image != null)) {
    throw const FormatException('No readable text');
  }

  var toc = const <TocEntry>[];
  for (final source in tocSources) {
    final xml = read(source.path);
    if (xml == null) continue;
    try {
      toc = _parseToc(
        xml,
        p.posix.dirname(source.path),
        source.ncx,
        firstBlock,
      );
    } catch (_) {}
    if (toc.isNotEmpty) break;
  }
  return EpubDoc(blocks, toc);
}

String _decode(List<int> bytes) {
  final s = utf8.decode(bytes, allowMalformed: true);
  return s.startsWith('﻿') ? s.substring(1) : s;
}

XmlDocument _parseHtml(String s) =>
    XmlDocument.parse(s, entityMapping: const XmlDefaultEntityMapping.html5());

Iterable<XmlElement> _elements(XmlNode root, String local) => root.descendants
    .whereType<XmlElement>()
    .where((e) => e.name.local.toLowerCase() == local);

String _resolve(String base, String href) {
  final clean = Uri.decodeFull(href.split('#').first);
  return p.posix.normalize(p.posix.join(base, clean));
}

List<EpubBlock> _parsePage(
  String html,
  String base,
  ArchiveFile? Function(String) find,
) {
  try {
    final walker = _Walker(base, find);
    final doc = _parseHtml(html);
    final body = _elements(doc, 'body');
    walker.walk(body.isEmpty ? doc.rootElement : body.first, false, false, 0);
    walker.flush(0);
    return walker.out;
  } catch (_) {
    return _parseLoosely(html);
  }
}

/// For pages that aren't valid XML: split at block tags and drop the rest.
List<EpubBlock> _parseLoosely(String html) {
  final body = html
      .replaceAll(
        RegExp(
          r'<(head|script|style)\b.*?</\1>',
          dotAll: true,
          caseSensitive: false,
        ),
        '',
      )
      .replaceAll(
        RegExp(r'</(p|div|h[1-6]|li|tr)>|<br\s*/?>', caseSensitive: false),
        '\u0000',
      )
      .replaceAll(RegExp(r'<[^>]*>'), '');
  return [
    for (final part in body.split('\u0000'))
      if (_unescape(part).trim().isNotEmpty)
        EpubBlock.text([
          TextRun(_unescape(part).trim().replaceAll(RegExp(r'\s+'), ' ')),
        ]),
  ];
}

String _unescape(String s) => s
    .replaceAll('&nbsp;', ' ')
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&#39;', "'")
    .replaceAll('&amp;', '&');

class _Walker {
  _Walker(this.base, this.find);

  final String base;
  final ArchiveFile? Function(String) find;
  final out = <EpubBlock>[];
  final _runs = <TextRun>[];

  void walk(XmlNode node, bool bold, bool italic, int level) {
    for (final child in node.children) {
      if (child is XmlText || child is XmlCDATA) {
        final text = child.value!.replaceAll(RegExp(r'\s+'), ' ');
        if (text.isNotEmpty) {
          _runs.add(TextRun(text, bold: bold, italic: italic));
        }
      } else if (child is XmlElement) {
        final tag = child.name.local.toLowerCase();
        if (_skipTags.contains(tag)) continue;
        if (tag == 'br') {
          _runs.add(const TextRun('\n'));
        } else if (tag == 'img' || tag == 'image') {
          flush(level);
          final href =
              child.getAttribute('src') ??
              child.getAttribute('href') ??
              child.getAttribute('xlink:href');
          final file = href == null ? null : find(_resolve(base, href));
          if (file != null) out.add(EpubBlock.image(file.content));
        } else if (_blockTags.contains(tag)) {
          flush(level);
          final heading = RegExp(r'^h([1-6])$').firstMatch(tag);
          final inner = heading == null ? level : int.parse(heading[1]!);
          if (tag == 'li') _runs.add(const TextRun('•  '));
          walk(child, bold, italic, inner);
          flush(inner);
        } else {
          walk(
            child,
            bold || tag == 'b' || tag == 'strong',
            italic || tag == 'i' || tag == 'em' || tag == 'cite',
            level,
          );
        }
      }
    }
  }

  void flush(int level) {
    if (_runs.isEmpty) return;
    final cleaned = <TextRun>[];
    var endsInSpace = true;
    for (final r in _runs) {
      var t = r.text;
      if (endsInSpace) t = t.replaceFirst(RegExp(r'^ +'), '');
      t = t.replaceAll(' \n', '\n').replaceAll('\n ', '\n');
      if (t.isEmpty) continue;
      endsInSpace = t.endsWith(' ') || t.endsWith('\n');
      cleaned.add(TextRun(t, bold: r.bold, italic: r.italic));
    }
    _runs.clear();
    while (cleaned.isNotEmpty) {
      final last = cleaned.last;
      final t = last.text.trimRight();
      if (t.isEmpty) {
        cleaned.removeLast();
        continue;
      }
      cleaned[cleaned.length - 1] = TextRun(
        t,
        bold: last.bold,
        italic: last.italic,
      );
      break;
    }
    if (cleaned.isNotEmpty) out.add(EpubBlock.text(cleaned, level: level));
  }
}

List<TocEntry> _parseToc(
  String xml,
  String base,
  bool ncx,
  Map<String, int> firstBlock,
) {
  final doc = _parseHtml(xml);
  final out = <TocEntry>[];
  void add(String title, String? href, int depth) {
    if (href == null) return;
    final block = firstBlock[_resolve(base, href).toLowerCase()];
    final clean = title.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (block != null && clean.isNotEmpty) {
      out.add(TocEntry(clean, depth, block));
    }
  }

  if (ncx) {
    void walk(XmlElement parent, int depth) {
      for (final point in parent.childElements.where(
        (e) => e.name.local == 'navPoint',
      )) {
        final label = _elements(point, 'text');
        final content = _elements(point, 'content');
        add(
          label.isEmpty ? '' : label.first.innerText,
          content.isEmpty ? null : content.first.getAttribute('src'),
          depth,
        );
        walk(point, depth + 1);
      }
    }

    final map = _elements(doc, 'navmap');
    if (map.isNotEmpty) walk(map.first, 0);
  } else {
    final navs = _elements(doc, 'nav').where(
      (n) =>
          n.getAttribute('epub:type') == 'toc' ||
          n.getAttribute('type') == 'toc',
    );
    final nav = navs.isNotEmpty ? navs.first : _elements(doc, 'nav').first;
    for (final a in _elements(nav, 'a')) {
      var depth = -1;
      for (final parent in a.ancestors) {
        if (parent is XmlElement && parent.name.local == 'ol') depth++;
      }
      add(a.innerText, a.getAttribute('href'), depth < 0 ? 0 : depth);
    }
  }
  return out;
}
