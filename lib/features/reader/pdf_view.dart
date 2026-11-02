import 'dart:math';

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../app/theme.dart';
import '../../data/models.dart';
import 'page_surface.dart';
import 'pane.dart';
import 'pdf_crop.dart';
import 'search.dart';

/// Turns a white page with black text into a dark page with light text.
const _nightPage = ColorFilter.matrix([
  -0.82,
  0,
  0,
  0,
  217,
  0,
  -0.82,
  0,
  0,
  214,
  0,
  0,
  -0.82,
  0,
  207,
  0,
  0,
  0,
  1,
  0,
]);

class PdfPane extends StatefulWidget {
  const PdfPane({
    super.key,
    required this.book,
    required this.saved,
    required this.callbacks,
  });

  final Book book;
  final Progress? saved;
  final PaneCallbacks callbacks;

  @override
  State<PdfPane> createState() => _PdfPaneState();
}

class _PdfPaneState extends State<PdfPane> implements ReaderActions {
  late final PageController _pages;
  PdfDocument? _doc;
  CropBox? _typical;
  final _crops = <int, CropBox?>{};
  final _measuring = <int>{};
  bool _announced = false;
  int _count = 0;
  int _current = 0;

  // Zoom works from raw touches: one finger at normal size belongs to the page
  // swipe, two fingers zoom, and one finger pans once zoomed.
  final _touches = <int, Offset>{};
  double _scale = 1;
  Offset _pan = Offset.zero;
  double _startScale = 1;
  double _startSpread = 1;

  bool get _zoomed => _scale > 1.01;

  int get _initialPage {
    final page = (int.tryParse(widget.saved?.readLocation ?? '') ?? 1) - 1;
    return page < 0 ? 0 : page;
  }

  @override
  void initState() {
    super.initState();
    _current = _initialPage;
    _pages = PageController(initialPage: _initialPage);
    _open();
  }

  @override
  void dispose() {
    _pages.dispose();
    _doc?.dispose();
    super.dispose();
  }

  @override
  Stream<SearchHit> search(String query) async* {
    final doc = _doc;
    if (doc == null) return;
    var count = 0;
    for (var i = 0; i < doc.pages.length && count < 300; i++) {
      final text = (await doc.pages[i].loadText())?.fullText ?? '';
      for (final m in findMatches(text, query)) {
        count++;
        yield makeHit(
          text,
          m,
          pageLabel: 'Page ${i + 1}',
          location: '${i + 1}',
          fraction: _count <= 1 ? 0 : i / (_count - 1),
        );
      }
    }
  }

  @override
  void goTo(String location, {int highlightLength = 0}) {
    final page = int.tryParse(location);
    if (page != null) _pages.jumpToPage(page - 1);
  }

  @override
  void goToFraction(double fraction) =>
      _pages.jumpToPage(((_count - 1) * fraction).round());

  void _report(int index) {
    final page = index + 1;
    widget.callbacks.onLocation('$page / $_count', '$page', page / _count);
  }

  void _announce(PdfDocument doc) {
    if (_announced) return;
    _announced = true;
    _count = doc.pages.length;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final index = _current.clamp(0, _count - 1);
      if (index != _current) {
        _current = index;
        _pages.jumpToPage(index);
      }
      _report(index);
      widget.callbacks.onReady();
      widget.callbacks.onActions?.call(this);
      try {
        final outline = await doc.loadOutline();
        if (mounted) widget.callbacks.onContents(_flatten(outline, 0));
      } catch (_) {}
    });
  }

  List<TocItem> _flatten(List<PdfOutlineNode> nodes, int depth) => [
    for (final n in nodes) ...[
      if (n.dest != null)
        TocItem(
          n.title,
          depth,
          () => _pages.jumpToPage(n.dest!.pageNumber - 1),
        ),
      ..._flatten(n.children, depth + 1),
    ],
  ];

  void _onTap(double x) {
    if (_zoomed || (x >= 0.3 && x <= 0.7)) {
      widget.callbacks.onCenterTap();
      return;
    }
    final next = _current + (x < 0.3 ? -1 : 1);
    if (next >= 0 && next < _count) {
      _pages.animateToPage(
        next,
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
      );
    }
  }

  double _spread() {
    final points = _touches.values.toList();
    return max((points[0] - points[1]).distance, 1);
  }

  void _onDown(PointerDownEvent e) {
    final wasOne = _touches.length == 1;
    _touches[e.pointer] = e.localPosition;
    if (_touches.length == 2) {
      _startSpread = _spread();
      _startScale = _scale;
    }
    // A second finger takes the drag away from the page swipe.
    if (wasOne && _touches.length == 2) setState(() {});
  }

  void _onMove(PointerMoveEvent e, Size box) {
    if (!_touches.containsKey(e.pointer)) return;
    final before = _touches[e.pointer]!;
    _touches[e.pointer] = e.localPosition;
    if (_touches.length == 2) {
      setState(() {
        _scale = (_startScale * _spread() / _startSpread).clamp(1.0, 5.0);
        _pan = _clampPan(_pan, box);
      });
    } else if (_touches.length == 1 && _zoomed) {
      setState(() => _pan = _clampPan(_pan + e.localPosition - before, box));
    }
  }

  Offset _clampPan(Offset pan, Size box) {
    final x = box.width * (_scale - 1) / 2;
    final y = box.height * (_scale - 1) / 2;
    return Offset(pan.dx.clamp(-x, x), pan.dy.clamp(-y, y));
  }

  void _onUp(int pointer) {
    final hadTwo = _touches.length >= 2;
    _touches.remove(pointer);
    if (hadTwo && _touches.length < 2) {
      setState(() {
        if (!_zoomed) {
          _scale = 1;
          _pan = Offset.zero;
        }
      });
    }
  }

  /// Finds the book's text area from pages spread through it.
  Future<void> _measureBook(PdfDocument doc) async {
    final count = doc.pages.length;
    final found = <CropBox>[];
    final step = max(1, count ~/ 15);
    for (var i = min(step, count - 1); i < count; i += step) {
      final crop = await _measure(doc, i);
      _crops[i] = crop;
      if (crop != null) found.add(crop);
    }
    _typical = typicalCrop(found);
  }

  Future<CropBox?> _measure(PdfDocument doc, int index) async {
    try {
      final page = doc.pages[index];
      const width = 240.0;
      final height = width * page.height / page.width;
      final image = await page.render(
        width: width.round(),
        height: height.round(),
        fullWidth: width,
        fullHeight: height,
        backgroundColor: 0xFFFFFFFF,
      );
      if (image == null) return null;
      try {
        return contentBounds(image.pixels, image.width, image.height);
      } finally {
        image.dispose();
      }
    } catch (_) {
      return null;
    }
  }

  /// Measures pages just before they're needed, for covers and full figures.
  void _measureAround(int index) {
    final doc = _doc;
    if (doc == null) return;
    for (var i = index - 1; i <= index + 2; i++) {
      if (i < 0 || i >= doc.pages.length) continue;
      if (_crops.containsKey(i) || !_measuring.add(i)) continue;
      _measure(doc, i).then((crop) {
        _crops[i] = crop;
        _measuring.remove(i);
        if (mounted && cropForPage(crop, _typical) != _typical) setState(() {});
      });
    }
  }

  /// Opened once and kept: this screen rebuilds on every page turn and touch.
  Future<void> _open() async {
    try {
      final doc = await PdfDocument.openFile(widget.book.filePath);
      if (!mounted) {
        await doc.dispose();
        return;
      }
      if (doc.pages.isEmpty) throw const FormatException('No pages');
      _doc = doc;
      await _measureBook(doc);
      if (!mounted) return;
      setState(() {});
      _measureAround(_current);
      _announce(doc);
    } catch (_) {
      if (mounted) {
        widget.callbacks.onError(
          'This file could not be read. You can still listen to its audio.',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final doc = _doc;
    if (doc == null) return const SizedBox.expand();
    return LayoutBuilder(
      builder: (context, box) {
        final size = box.biggest;
        return ClipRect(
          child: PageSurface(
            onTap: _onTap,
            child: Listener(
              onPointerDown: _onDown,
              onPointerMove: (e) => _onMove(e, size),
              onPointerUp: (e) => _onUp(e.pointer),
              onPointerCancel: (e) => _onUp(e.pointer),
              child: PageView.builder(
                controller: _pages,
                physics: _touches.length > 1 || _zoomed
                    ? const NeverScrollableScrollPhysics()
                    : const PageScrollPhysics(),
                itemCount: doc.pages.length,
                onPageChanged: (i) {
                  setState(() {
                    _current = i;
                    _scale = 1;
                    _pan = Offset.zero;
                  });
                  _measureAround(i);
                  _report(i);
                },
                itemBuilder: (context, i) {
                  final page = _CroppedPage(
                    page: doc.pages[i],
                    document: doc,
                    crop: cropForPage(_crops[i], _typical),
                    view: size,
                  );
                  if (i != _current || !_zoomed) return page;
                  return Transform.translate(
                    offset: _pan,
                    child: Transform.scale(scale: _scale, child: page),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}

/// One page with its blank margins cut off, as large as the screen allows and
/// tinted to the reading theme, so page and app read as one sheet.
class _CroppedPage extends StatelessWidget {
  const _CroppedPage({
    required this.document,
    required this.page,
    required this.crop,
    required this.view,
  });

  final PdfDocument document;
  final PdfPage page;
  final CropBox crop;
  final Size view;

  @override
  Widget build(BuildContext context) {
    final c = context.twofold;
    final fit = fitCrop(
      crop,
      page.width,
      page.height,
      view.width - 16,
      view.height - 8,
    );
    final fullW = page.width * fit.scale;
    final fullH = page.height * fit.scale;
    final filter = c.brightness == Brightness.dark
        ? _nightPage
        : ColorFilter.mode(c.bg, BlendMode.multiply);
    return Center(
      child: SizedBox(
        width: fit.width,
        height: fit.height,
        child: ClipRect(
          child: ColorFiltered(
            colorFilter: filter,
            child: OverflowBox(
              alignment: Alignment.topLeft,
              minWidth: fullW,
              maxWidth: fullW,
              minHeight: fullH,
              maxHeight: fullH,
              child: Transform.translate(
                offset: Offset(-crop.left * fullW, -crop.top * fullH),
                child: PdfPageView(
                  document: document,
                  pageNumber: page.pageNumber,
                  decoration: const BoxDecoration(color: Colors.white),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
