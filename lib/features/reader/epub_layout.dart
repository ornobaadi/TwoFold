import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../app/theme.dart';
import 'epub_book.dart';

/// Part of a block on one page; an image block has start and end 0.
class PageSlice {
  const PageSlice(this.block, this.start, this.end, this.top);

  final int block;
  final int start;
  final int end;

  /// Distance from the top of the page. Slices are drawn at exactly this
  /// position, so small rounding in one can't push later lines off the page.
  final double top;
}

class TextSettings {
  const TextSettings(
    this.fontSize,
    this.lineHeight, [
    this.font = ReadingFont.serif,
  ]);

  final double fontSize;
  final double lineHeight;
  final ReadingFont font;

  @override
  bool operator ==(Object other) =>
      other is TextSettings &&
      other.fontSize == fontSize &&
      other.lineHeight == lineHeight &&
      other.font == font;

  @override
  int get hashCode => Object.hash(fontSize, lineHeight, font);
}

TextStyle blockStyle(EpubBlock b, TextSettings s, [Color? color]) {
  final level = b.level;
  final size = switch (level) {
    1 => s.fontSize * 1.5,
    2 => s.fontSize * 1.3,
    3 => s.fontSize * 1.15,
    _ => s.fontSize,
  };
  // inherit: false, or the theme's letter spacing joins in when drawn but not
  // when measured, and lines wrap differently from what the pages expect.
  return TextStyle(
    inherit: false,
    textBaseline: TextBaseline.alphabetic,
    letterSpacing: 0,
    wordSpacing: 0,
    fontFamily: s.font == ReadingFont.serif ? serifFont : uiFont,
    fontSize: size,
    height: level > 0 ? 1.25 : s.lineHeight,
    fontWeight: level > 0 ? FontWeight.w500 : FontWeight.w400,
    color: color ?? const Color(0xFF000000),
  );
}

/// Chapter titles at the top of their page are centred, with room above.
bool isChapterTitle(EpubBlock b) => b.opensSection && b.level > 0;

TextAlign blockAlign(EpubBlock b) =>
    isChapterTitle(b) ? TextAlign.center : TextAlign.start;

double blockGap(EpubBlock b, TextSettings s) =>
    b.level > 0 ? s.fontSize * 1.2 : s.fontSize * 0.7;

/// The text of [b] between two character offsets, keeping bold and italics.
TextSpan blockSpan(
  EpubBlock b,
  int start,
  int end,
  TextStyle style, {
  int markStart = 0,
  int markEnd = 0,
  Color? markColor,
}) {
  // A slice that stops at a line break would be drawn with an empty extra line.
  final all = b.runs.map((r) => r.text).join();
  while (end > start && all[end - 1] == '\n') {
    end--;
  }
  final children = <TextSpan>[];
  var at = 0;
  for (final r in b.runs) {
    final from = max(start, at);
    final to = min(end, at + r.text.length);
    if (from < to) {
      // A run is split where a search highlight begins and ends.
      final cuts = {from, to};
      for (final m in [markStart, markEnd]) {
        if (m > from && m < to) cuts.add(m);
      }
      final points = cuts.toList()..sort();
      for (var i = 0; i + 1 < points.length; i++) {
        final marked =
            markColor != null &&
            points[i] >= markStart &&
            points[i + 1] <= markEnd;
        children.add(
          TextSpan(
            text: r.text.substring(points[i] - at, points[i + 1] - at),
            style: TextStyle(
              fontWeight: r.bold ? FontWeight.w500 : null,
              fontStyle: r.italic ? FontStyle.italic : null,
              backgroundColor: marked ? markColor : null,
            ),
          ),
        );
      }
    }
    at += r.text.length;
  }
  return TextSpan(style: style, children: children);
}

/// Natural size of an image, or null if Flutter can't draw it (such as SVG).
Future<Size?> imageSize(EpubBlock b) async {
  try {
    final buffer = await ui.ImmutableBuffer.fromUint8List(b.image!);
    final d = await ui.ImageDescriptor.encoded(buffer);
    final size = Size(d.width.toDouble(), d.height.toDouble());
    d.dispose();
    buffer.dispose();
    return size;
  } catch (_) {
    return null;
  }
}

/// Size an image takes in a page of [page] size.
Size fitImage(Size natural, Size page) {
  final scale = min(
    min(page.width / natural.width, page.height / natural.height),
    2.0,
  );
  return natural * scale;
}

/// Splits the book into pages of [size]. Yields regularly so the screen stays
/// responsive; returns null if [cancelled] turns true.
Future<List<List<PageSlice>>?> paginate(
  EpubDoc doc,
  Size size,
  TextSettings settings,
  Map<int, Size> images, {
  bool Function()? cancelled,
}) async {
  final pages = <List<PageSlice>>[];
  var page = <PageSlice>[];
  var y = 0.0;
  final clock = Stopwatch()..start();

  void newPage() {
    if (page.isNotEmpty) pages.add(page);
    page = <PageSlice>[];
    y = 0;
  }

  for (var i = 0; i < doc.blocks.length; i++) {
    if (clock.elapsedMilliseconds > 12) {
      await Future<void>.delayed(Duration.zero);
      if (cancelled?.call() ?? false) return null;
      clock.reset();
    }
    final block = doc.blocks[i];
    if (block.opensSection) newPage();

    if (block.image != null) {
      final natural = images[i];
      if (natural == null) continue;
      final fitted = fitImage(natural, size);
      if (y + fitted.height > size.height) newPage();
      page.add(PageSlice(i, 0, 0, y));
      y += fitted.height + settings.fontSize;
      continue;
    }

    final length = block.length;
    if (length == 0) continue;
    final painter = TextPainter(
      text: blockSpan(block, 0, length, blockStyle(block, settings)),
      textAlign: blockAlign(block),
      textDirection: TextDirection.ltr,
      textScaler: TextScaler.noScaling,
    )..layout(minWidth: size.width, maxWidth: size.width);
    final lines = painter.computeLineMetrics();

    if (isChapterTitle(block)) y += size.height * 0.1;

    // A heading never sits alone at the bottom of a page.
    if (block.level > 0 &&
        y + painter.height + settings.fontSize * settings.lineHeight * 2 >
            size.height) {
      newPage();
    }

    var start = 0;
    var top = 0.0;
    var sliceTop = y;
    for (final line in lines) {
      if (y + line.height > size.height - 1) {
        final at = painter
            .getPositionForOffset(Offset(0, top + line.height / 2))
            .offset;
        if (at > start) page.add(PageSlice(i, start, at, sliceTop));
        newPage();
        start = at;
        sliceTop = 0;
      }
      y += line.height;
      top += line.height;
    }
    page.add(PageSlice(i, start, length, sliceTop));
    y += isChapterTitle(block)
        ? settings.fontSize * 2.5
        : blockGap(block, settings);
    painter.dispose();
  }
  if (page.isNotEmpty) pages.add(page);
  return pages;
}

/// Index of the page holding this character of this block.
int pageOf(List<List<PageSlice>> pages, int block, int char) {
  for (var i = 0; i < pages.length; i++) {
    final last = pages[i].last;
    if (last.block > block ||
        (last.block == block && char < max(last.end, 1))) {
      return i;
    }
  }
  return pages.isEmpty ? 0 : pages.length - 1;
}
