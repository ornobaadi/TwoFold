import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/settings.dart';
import '../../app/theme.dart';
import '../../data/models.dart';
import 'epub_book.dart';
import 'epub_layout.dart';
import 'page_surface.dart';
import 'pane.dart';
import 'search.dart';

const _pagePadding = EdgeInsets.fromLTRB(24, 20, 24, 8);

/// Native EPUB reader: the book is parsed to text and laid out into pages by
/// Flutter, so it looks and behaves the same as the rest of the app.
class EpubPane extends ConsumerStatefulWidget {
  const EpubPane({
    super.key,
    required this.book,
    required this.saved,
    required this.callbacks,
  });

  final Book book;
  final Progress? saved;
  final PaneCallbacks callbacks;

  @override
  ConsumerState<EpubPane> createState() => _EpubPaneState();
}

class _EpubPaneState extends ConsumerState<EpubPane> implements ReaderActions {
  EpubDoc? _doc;
  Map<int, Size> _images = const {};
  List<List<PageSlice>>? _pages;
  PageController? _controller;
  bool _announced = false;

  Size? _laidOutSize;
  TextSettings? _laidOutSettings;
  int _layoutRun = 0;

  // Where the reader is, independent of font size and screen size.
  int _block = 0;
  int _char = 0;
  double? _restorePercent;

  // Search match to highlight; cleared when the page turns.
  ({int block, int start, int end, int page})? _mark;

  @override
  void initState() {
    super.initState();
    _restore();
    _load();
  }

  void _restore() {
    final saved = widget.saved?.readLocation;
    final parts = saved?.split(':');
    final block = parts?.length == 2 ? int.tryParse(parts![0]) : null;
    final char = parts?.length == 2 ? int.tryParse(parts![1]) : null;
    if (block != null && char != null) {
      _block = block;
      _char = char;
    } else {
      _restorePercent = widget.saved?.readPercent;
    }
  }

  Future<void> _load() async {
    final path = widget.book.filePath;
    try {
      final doc = await loadEpubFile(path);
      final images = <int, Size>{};
      for (var i = 0; i < doc.blocks.length; i++) {
        if (doc.blocks[i].image == null) continue;
        final size = await imageSize(doc.blocks[i]);
        if (size != null) images[i] = size;
      }
      if (!mounted) return;
      setState(() {
        _doc = doc;
        _images = images;
      });
      widget.callbacks.onContents([
        for (final t in doc.toc)
          TocItem(t.title, t.depth, () => _jumpToBlock(t.block)),
      ]);
    } catch (_) {
      if (mounted) {
        widget.callbacks.onError(
          'This file could not be read. You can still listen to its audio.',
        );
      }
    }
  }

  @override
  Stream<SearchHit> search(String query) async* {
    final doc = _doc;
    final pages = _pages;
    if (doc == null || pages == null) return;
    var count = 0;
    for (var i = 0; i < doc.blocks.length && count < 300; i++) {
      final block = doc.blocks[i];
      if (block.length == 0) continue;
      final text = block.runs.map((r) => r.text).join();
      for (final m in findMatches(text, query)) {
        final page = pageOf(pages, i, m.$1);
        count++;
        yield makeHit(
          text,
          m,
          pageLabel: 'Page ${page + 1}',
          location: '$i:${m.$1}',
          fraction: pages.length <= 1 ? 0 : page / (pages.length - 1),
        );
      }
      if (i % 50 == 0) await Future<void>.delayed(Duration.zero);
    }
  }

  @override
  void goTo(String location, {int highlightLength = 0}) {
    final pages = _pages;
    final parts = location.split(':');
    if (pages == null || parts.length != 2) return;
    final block = int.tryParse(parts[0]) ?? 0;
    final char = int.tryParse(parts[1]) ?? 0;
    final page = pageOf(pages, block, char);
    // Later re-layouts return here, not to wherever the reader was before.
    _block = block;
    _char = char;
    _showPage(
      page,
      highlightLength > 0
          ? (block: block, start: char, end: char + highlightLength, page: page)
          : null,
    );
  }

  @override
  void clearHighlight() {
    if (mounted) setState(() => _mark = null);
  }

  /// Opens [page] with a fresh controller. Jumping the old one is unreliable
  /// while this screen is coming back from behind another route.
  void _showPage(int page, ({int block, int start, int end, int page})? mark) {
    final old = _controller;
    setState(() {
      _mark = mark;
      _controller = PageController(initialPage: page);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => old?.dispose());
    _report(page, remember: mark == null);
  }

  @override
  void goToFraction(double fraction) {
    final pages = _pages;
    if (pages == null) return;
    _showPage(((pages.length - 1) * fraction).round(), null);
  }

  void _jumpToBlock(int block) {
    final pages = _pages;
    if (pages != null) _showPage(pageOf(pages, block, 0), null);
  }

  Future<void> _layout(Size size, TextSettings settings) async {
    final run = ++_layoutRun;
    _laidOutSize = size;
    _laidOutSettings = settings;
    final pages = await paginate(
      _doc!,
      size,
      settings,
      _images,
      cancelled: () => run != _layoutRun || !mounted,
    );
    if (pages == null || pages.isEmpty || !mounted || run != _layoutRun) return;

    var index = pageOf(pages, _block, _char);
    final percent = _restorePercent;
    if (percent != null) {
      index = ((pages.length - 1) * percent).round();
      _restorePercent = null;
    }
    final mark = _mark;
    if (mark != null) {
      index = pageOf(pages, mark.block, mark.start);
      _mark = (block: mark.block, start: mark.start, end: mark.end, page: index);
    }
    final old = _controller;
    setState(() {
      _pages = pages;
      _controller = PageController(initialPage: index);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => old?.dispose());
    _report(index, remember: mark == null);
    if (!_announced) {
      _announced = true;
      widget.callbacks.onActions?.call(this);
      widget.callbacks.onReady();
    }
  }

  void _report(int index, {bool remember = true}) {
    final mark = _mark;
    if (mark != null && mark.page != index) setState(() => _mark = null);
    final pages = _pages!;
    final first = pages[index].first;
    if (remember) {
      _block = first.block;
      _char = first.start;
    }
    final total = pages.length;
    widget.callbacks.onLocation(
      '${index + 1} / $total',
      '${first.block}:${first.start}',
      total <= 1 ? 1 : index / (total - 1),
    );
  }

  void _onTap(double x) {
    if (x >= 0.3 && x <= 0.7) {
      widget.callbacks.onCenterTap();
      return;
    }
    final c = _controller;
    if (c == null || !c.hasClients) return;
    final next = (c.page?.round() ?? 0) + (x < 0.3 ? -1 : 1);
    if (next >= 0 && next < _pages!.length) {
      c.animateToPage(
        next,
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  void dispose() {
    _layoutRun++;
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(settingsProvider);
    final settings = TextSettings(s.fontSize.toDouble(), s.lineHeight, s.font);
    return LayoutBuilder(
      builder: (context, box) {
        final doc = _doc;
        if (doc != null) {
          final size = Size(
            box.maxWidth - _pagePadding.horizontal,
            box.maxHeight - _pagePadding.vertical,
          );
          if (size != _laidOutSize || settings != _laidOutSettings) {
            WidgetsBinding.instance.addPostFrameCallback(
              (_) => _layout(size, settings),
            );
            _laidOutSize = size;
            _laidOutSettings = settings;
          }
        }
        final pages = _pages;
        if (doc == null || pages == null) return const SizedBox.expand();
        return PageSurface(
          onTap: _onTap,
          child: PageView.builder(
            key: ObjectKey(_controller),
            controller: _controller,
            itemCount: pages.length,
            onPageChanged: _report,
            itemBuilder: (context, i) => Padding(
              padding: _pagePadding,
              child: EpubPage(
                doc: doc,
                slices: pages[i],
                images: _images,
                settings: settings,
                mark: _mark,
              ),
            ),
          ),
        );
      },
    );
  }
}

class EpubPage extends StatelessWidget {
  const EpubPage({
    super.key,
    required this.doc,
    required this.slices,
    required this.images,
    required this.settings,
    this.mark,
  });

  final EpubDoc doc;
  final List<PageSlice> slices;
  final Map<int, Size> images;
  final TextSettings settings;
  final ({int block, int start, int end, int page})? mark;

  @override
  Widget build(BuildContext context) {
    final color = context.twofold.text;
    final markColor = context.twofold.accent.withValues(alpha: 0.35);
    return LayoutBuilder(
      builder: (context, box) => ClipRect(
        child: Stack(
          children: [
            for (final slice in slices)
              Positioned(
                top: slice.top,
                left: 0,
                right: 0,
                child: _slice(slice, box, color, markColor),
              ),
          ],
        ),
      ),
    );
  }

  Widget _slice(
    PageSlice slice,
    BoxConstraints box,
    Color color,
    Color markColor,
  ) {
    final block = doc.blocks[slice.block];
    final image = block.image;
    if (image != null) {
      final fitted = fitImage(images[slice.block]!, box.biggest);
      return Center(
        child: Image.memory(
          image,
          width: fitted.width,
          height: fitted.height,
          fit: BoxFit.contain,
          gaplessPlayback: true,
        ),
      );
    }
    return Text.rich(
      blockSpan(
        block,
        slice.start,
        slice.end,
        blockStyle(block, settings, color),
        markStart: mark?.block == slice.block ? mark!.start : 0,
        markEnd: mark?.block == slice.block ? mark!.end : 0,
        markColor: mark?.block == slice.block ? markColor : null,
      ),
      textAlign: blockAlign(block),
      textScaler: TextScaler.noScaling,
    );
  }
}
