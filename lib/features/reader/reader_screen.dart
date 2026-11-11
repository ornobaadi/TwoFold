import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/press.dart';
import '../../app/router.dart';
import '../../app/settings.dart';
import '../../app/theme.dart';
import '../../audio/player_controller.dart';
import '../../data/book_repo.dart';
import '../../data/models.dart';
import '../../import/device_files.dart';
import '../library/book_card.dart';
import '../player/mini_play_button.dart';
import '../player/player_bar.dart';
import '../listen/audiobook_sheet.dart';
import '../settings/settings_sheet.dart';
import 'epub_view.dart';
import 'pane.dart';
import 'pdf_view.dart';
import 'places_sheet.dart';
import 'search_screen.dart';

const openBookKey = 'open_book';
const _fade = Duration(milliseconds: 200);

/// The 2-in-1 screen: the book fills it, audio controls float on top.
class ReaderScreen extends ConsumerStatefulWidget {
  const ReaderScreen({super.key, required this.book});

  final Book book;

  @override
  ConsumerState<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends ConsumerState<ReaderScreen> {
  late final BookRepo _repo;
  Progress? _saved;
  bool _savedRead = false;
  // Visible on open, so the player is never something to go looking for.
  bool _showControls = true;
  bool _showHint = false;
  bool _slow = false;
  bool _ready = false;
  int _attempt = 0;
  String _label = '';
  String _location = '';
  double _percent = 0;
  ReaderActions? _actions;
  double? _dragPercent;

  /// The page before a jump with the book slider, offered as a way back.
  ({String location, String label})? _beforeJump;
  Timer? _beforeTimer;
  bool _keptOn = false;
  String? _error;
  String? _audioError;
  List<TocItem> _contents = const [];
  Timer? _hideTimer;
  SearchResult? _found;

  Book get _book => widget.book;

  @override
  void initState() {
    super.initState();
    _repo = ref.read(bookRepoProvider);
    _open();
    Timer(const Duration(milliseconds: 300), () {
      if (mounted && !_ready) setState(() => _slow = true);
    });
  }

  Future<void> _open() async {
    await _repo.setSetting(openBookKey, _book.id);
    await _repo.touchOpened(_book.id);
    final saved = await _repo.getProgress(_book.id);
    if (!mounted) return;
    setState(() {
      _saved = saved;
      _savedRead = true;
    });
    await _loadAudio();
    if (!mounted) return;

    _touched();
    final settings = ref.read(settingsProvider);
    if (!settings.hintShown) {
      setState(() => _showHint = true);
      ref
          .read(settingsProvider.notifier)
          .change(settings.copyWith(hintShown: true));
    }
  }

  Future<void> _loadAudio({bool reload = false}) async {
    try {
      await ref.read(audioHandlerProvider).loadBook(_book, reload: reload);
      if (mounted) setState(() => _audioError = null);
    } catch (_) {
      if (mounted) {
        setState(() => _audioError = 'The audio files could not be opened.');
      }
    }
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _beforeTimer?.cancel();
    if (_keptOn) DeviceFiles.keepScreenOn(false);
    _repo.deleteSetting(openBookKey);
    super.dispose();
  }

  void _toggleControls() {
    setState(() {
      _showControls = !_showControls;
      _showHint = false;
    });
    _touched();
  }

  /// Controls hide 4 s after the last touch while audio plays.
  void _touched() {
    _hideTimer?.cancel();
    if (!_showControls) return;
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (!mounted) return;
      final playing = ref.read(playbackStateProvider).value?.playing ?? false;
      if (playing) {
        setState(() => _showControls = false);
      } else {
        _touched();
      }
    });
  }

  void _showContents() {
    final theme = Theme.of(context);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheet) => ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.7,
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SheetTitle('Contents'),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _contents.length,
                  itemBuilder: (_, i) => ListTile(
                    contentPadding: EdgeInsets.only(
                      left: Space.l + _contents[i].depth * Space.l,
                      right: Space.l,
                    ),
                    title: Text(
                      _contents[i].title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyLarge,
                    ),
                    onTap: () {
                      Navigator.of(sheet).pop();
                      _contents[i].go();
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _search() async {
    final actions = _actions;
    if (actions == null) return;
    final result = await Navigator.of(context).push<SearchResult>(
      fadeRoute(SearchScreen(actions: actions, previous: _found)),
    );
    if (result == null || !mounted) return;
    _showResult(result);
  }

  /// Opens the result's page, with the words highlighted.
  void _showResult(SearchResult result) {
    final hit = result.hits[result.index];
    _actions?.goTo(hit.location, highlightLength: hit.sourceLength);
    setState(() {
      _found = result;
      _showControls = false;
    });
  }

  void _stepResult(int by) {
    final found = _found!;
    final count = found.hits.length;
    _showResult(
      SearchResult(found.query, found.hits, (found.index + by + count) % count),
    );
  }

  void _endSearch() {
    _actions?.clearHighlight();
    setState(() => _found = null);
  }

  void _jumpTo(double v) {
    _beforeTimer?.cancel();
    final far = (v - _percent).abs() > 0.01 && _location.isNotEmpty;
    setState(() {
      _dragPercent = null;
      if (far) _beforeJump = (location: _location, label: _label);
    });
    _actions?.goToFraction(v);
    if (far) {
      _beforeTimer = Timer(const Duration(seconds: 10), () {
        if (mounted) setState(() => _beforeJump = null);
      });
    }
    _touched();
  }

  void _jumpBack() {
    final before = _beforeJump;
    if (before == null) return;
    _beforeTimer?.cancel();
    setState(() => _beforeJump = null);
    _actions?.goTo(before.location);
    _touched();
  }

  void _showPlaces() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => PlacesSheet(
        book: _book,
        location: _location,
        percent: _percent,
        pageLabel: _label,
        actions: _actions,
      ),
    );
  }

  Future<void> _addAudio() async {
    await openEditBook(context, _book);
    if (mounted) await _loadAudio(reload: true);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.twofold;
    final theme = Theme.of(context);
    final item = ref.watch(mediaItemProvider).value;
    final hasAudio = item?.id == _book.id;
    final keepOn = ref.watch(settingsProvider.select((s) => s.keepScreenOn));
    if (keepOn != _keptOn) {
      _keptOn = keepOn;
      DeviceFiles.keepScreenOn(keepOn);
    }

    final callbacks = PaneCallbacks(
      onCenterTap: _toggleControls,
      onLocation: (label, location, percent) {
        _location = location;
        _percent = percent;
        if (mounted) setState(() => _label = label);
        _repo.saveReading(_book.id, location: location, percent: percent);
      },
      onActions: (actions) => _actions = actions,
      onContents: (list) {
        if (mounted) setState(() => _contents = list);
      },
      onReady: () {
        if (mounted) setState(() => _ready = true);
      },
      onError: (message) {
        if (mounted) setState(() => _error = message);
      },
    );

    return Scaffold(
      // The keyboard on the search screen must not re-paginate the book.
      resizeToAvoidBottomInset: false,
      body: SafeArea(
        child: Stack(
          children: [
            // Page and footer. The footer keeps text out from under the
            // indicator and mini button.
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _error != null
                      ? _Message(
                          message: _error!,
                          onBack: () => Navigator.of(context).pop(),
                          onListen: hasAudio
                              ? () => openListen(context, _book)
                              : null,
                          onRetry: () => setState(() {
                            _error = null;
                            _attempt++;
                          }),
                        )
                      : !_savedRead
                      ? const SizedBox.expand()
                      : _book.format == 'pdf'
                      ? PdfPane(
                          key: ValueKey(_attempt),
                          book: _book,
                          saved: _saved,
                          callbacks: callbacks,
                        )
                      : EpubPane(
                          key: ValueKey(_attempt),
                          book: _book,
                          saved: _saved,
                          callbacks: callbacks,
                        ),
                ),
                // Tapping the footer also opens the controls, so they can
                // always be reached, whatever the page is doing.
                SizedBox(
                  height: 56,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Positioned.fill(
                        child: Semantics(
                          button: true,
                          label: 'Show or hide controls',
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: _toggleControls,
                          ),
                        ),
                      ),
                      if (!_showControls && _found != null)
                        Positioned.fill(
                          child: _ResultBar(
                            found: _found!,
                            onResults: _search,
                            onStep: _stepResult,
                            onClose: _endSearch,
                          ),
                        )
                      else if (!_showControls)
                        IgnorePointer(
                          child: Text(
                            _label,
                            style: theme.textTheme.labelMedium,
                          ),
                        ),
                      if (hasAudio &&
                          !_showControls &&
                          _found == null) ...const [
                        Positioned(left: Space.s, child: MiniBackButton()),
                        Positioned(right: Space.s, child: MiniPlayButton()),
                      ],
                    ],
                  ),
                ),
              ],
            ),

            // Covers the page until it reports ready.
            if (!_ready && _error == null)
              Positioned.fill(
                bottom: 56,
                child: AnimatedOpacity(
                  opacity: _slow ? 1 : 0,
                  duration: _fade,
                  child: _Opening(book: _book),
                ),
              ),

            // Top bar.
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: _Reveal(
                visible: _showControls,
                child: _TouchShield(
                  onTouch: _touched,
                  child: ColoredBox(
                    color: c.bg,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: Space.xs,
                          ),
                          child: Row(
                            children: [
                              IconButton(
                                tooltip: 'Back to library',
                                onPressed: () => Navigator.of(context).pop(),
                                icon: const Icon(Icons.arrow_back_rounded),
                              ),
                              Expanded(
                                child: Semantics(
                                  button: true,
                                  hint: 'About this book',
                                  child: GestureDetector(
                                    onTap: () {
                                      _touched();
                                      openBookDetails(context, _book);
                                    },
                                    child: Text(
                                      _book.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.titleMedium,
                                    ),
                                  ),
                                ),
                              ),
                              if (_label.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(
                                    left: Space.s,
                                    right: Space.m,
                                  ),
                                  child: Text(
                                    _label,
                                    style: theme.textTheme.labelMedium,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        if (_ready)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(
                              Space.l,
                              0,
                              Space.l,
                              Space.s,
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SizedBox(
                                  height: 32,
                                  child: SliderTheme(
                                    data: SliderTheme.of(context).copyWith(
                                      padding: EdgeInsets.zero,
                                      trackHeight: 3,
                                      thumbSize: const WidgetStatePropertyAll(
                                        Size(4, 28),
                                      ),
                                    ),
                                    child: Slider(
                                      value: (_dragPercent ?? _percent).clamp(
                                        0.0,
                                        1.0,
                                      ),
                                      semanticFormatterCallback: (v) =>
                                          '${(v * 100).round()}% through the book',
                                      onChanged: (v) =>
                                          setState(() => _dragPercent = v),
                                      onChangeStart: (_) =>
                                          _hideTimer?.cancel(),
                                      onChangeEnd: _jumpTo,
                                    ),
                                  ),
                                ),
                                _SliderNote(
                                  dragging: _dragPercent,
                                  before: _beforeJump?.label,
                                  onBack: _jumpBack,
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // Floating player.
            Positioned(
              left: Space.m,
              right: Space.m,
              bottom: Space.s,
              child: _Reveal(
                visible: _showControls,
                child: _TouchShield(
                  onTouch: _touched,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      hasAudio
                          ? const PlayerBar()
                          : _AddAudioBar(
                              message: _audioError,
                              onTap: _addAudio,
                              onFree: () => showAudiobookSheet(context, _book),
                            ),
                      const SizedBox(height: Space.s),
                      // The labels stay: they are how people find things.
                      Material(
                        color: theme.colorScheme.surfaceContainerHigh,
                        elevation: 3,
                        shadowColor: theme.colorScheme.shadow.withValues(
                          alpha: 0.4,
                        ),
                        borderRadius: BorderRadius.circular(Space.cardRadius),
                        clipBehavior: Clip.antiAlias,
                        child: Row(
                          children: [
                            if (_contents.isNotEmpty)
                              _Tool(
                                icon: Icons.format_list_bulleted_rounded,
                                label: 'Contents',
                                onTap: _showContents,
                              ),
                            _Tool(
                              icon: Icons.search_rounded,
                              label: 'Search',
                              onTap: _search,
                            ),
                            _Tool(
                              icon: Icons.bookmark_outline_rounded,
                              label: 'My places',
                              onTap: _showPlaces,
                            ),
                            _Tool(
                              icon: Icons.text_fields_rounded,
                              label: 'Text',
                              onTap: () => showSettingsSheet(context),
                            ),
                            if (hasAudio)
                              _Tool(
                                icon: Icons.headphones_outlined,
                                label: 'Listen',
                                onTap: () => openListen(context, _book),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // First-time help.
            if (_showHint)
              Center(
                child: Container(
                  margin: const EdgeInsets.all(Space.xl),
                  padding: const EdgeInsets.all(Space.xl),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(Space.cardRadius),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'How to use this page',
                        style: theme.textTheme.titleLarge,
                      ),
                      const SizedBox(height: Space.m),
                      Text(
                        'Swipe, or tap the left or right side, to turn the page.\n\n'
                        'Tap the middle of the page to show or hide these buttons.\n\n'
                        'Your page and your audio are saved by themselves.',
                        style: theme.textTheme.bodyLarge,
                      ),
                      const SizedBox(height: Space.l),
                      FilledButton(
                        onPressed: () => setState(() => _showHint = false),
                        child: const Text('Got it'),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Steps through search results from the page, in place of the footer.
class _ResultBar extends StatelessWidget {
  const _ResultBar({
    required this.found,
    required this.onResults,
    required this.onStep,
    required this.onClose,
  });

  final SearchResult found;
  final VoidCallback onResults;
  final ValueChanged<int> onStep;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final several = found.hits.length > 1;
    return ColoredBox(
      color: theme.colorScheme.surfaceContainerHigh,
      child: Row(
        children: [
          IconButton(
            tooltip: 'End search',
            onPressed: onClose,
            icon: const Icon(Icons.close_rounded),
          ),
          Expanded(
            child: TextButton(
              onPressed: onResults,
              child: Text(
                '${found.index + 1} of ${found.hits.length} · All results',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Previous result',
            onPressed: several ? () => onStep(-1) : null,
            icon: const Icon(Icons.keyboard_arrow_up_rounded),
          ),
          IconButton(
            tooltip: 'Next result',
            onPressed: several ? () => onStep(1) : null,
            icon: const Icon(Icons.keyboard_arrow_down_rounded),
          ),
        ],
      ),
    );
  }
}

class _Tool extends StatelessWidget {
  const _Tool({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Pressable(
      squish: 0.84,
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: Space.s),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 22),
              const SizedBox(height: 2),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Fades controls and removes them from hit testing while hidden, so they
/// can't catch a page swipe.
class _Reveal extends StatelessWidget {
  const _Reveal({required this.visible, required this.child});

  final bool visible;
  final Widget child;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    ignoring: !visible,
    child: AnimatedOpacity(
      opacity: visible ? 1 : 0,
      duration: _fade,
      child: child,
    ),
  );
}

/// Keeps every touch on a control away from the page below, including swipes
/// and taps that miss a button.
class _TouchShield extends StatelessWidget {
  const _TouchShield({required this.onTouch, required this.child});

  final VoidCallback onTouch;
  final Widget child;

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: (_) => onTouch(),
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {},
      onHorizontalDragStart: (_) {},
      onVerticalDragStart: (_) {},
      child: child,
    ),
  );
}

class _AddAudioBar extends StatelessWidget {
  const _AddAudioBar({
    required this.message,
    required this.onTap,
    required this.onFree,
  });

  final String? message;
  final VoidCallback onTap;
  final VoidCallback onFree;

  @override
  Widget build(BuildContext context) {
    final c = context.twofold;
    return Container(
      padding: const EdgeInsets.fromLTRB(Space.l, Space.xs, Space.xs, Space.xs),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(Space.cardRadius),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              message ?? 'No audio yet',
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: c.muted),
            ),
          ),
          TextButton(onPressed: onTap, child: const Text('Your files')),
          TextButton.icon(
            onPressed: onFree,
            icon: const Icon(Icons.headphones_rounded, size: 18),
            label: const Text('Free audiobook'),
          ),
        ],
      ),
    );
  }
}

class _Opening extends StatelessWidget {
  const _Opening({required this.book});

  final Book book;

  @override
  Widget build(BuildContext context) {
    final c = context.twofold;
    return ColoredBox(
      color: c.bg,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(width: 120, child: BookCover(book: book, titleSize: 14)),
            const SizedBox(height: Space.xl),
            SizedBox(width: 120, child: LinearProgressIndicator()),
            const SizedBox(height: Space.m),
            Text(
              'Opening the book',
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: c.muted),
            ),
          ],
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.message,
    required this.onBack,
    required this.onRetry,
    this.onListen,
  });

  final String message;
  final VoidCallback onBack;
  final VoidCallback onRetry;
  final VoidCallback? onListen;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(Space.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: Space.s),
          if (onListen != null) ...[
            const SizedBox(height: Space.l),
            FilledButton(
              onPressed: onListen,
              child: const Text('Listen to the audio'),
            ),
          ],
          const SizedBox(height: Space.xs),
          TextButton(onPressed: onRetry, child: const Text('Try again')),
          TextButton(onPressed: onBack, child: const Text('Back to library')),
        ],
      ),
    ),
  );
}

/// Under the book slider: where the thumb is while dragging, and after a
/// jump a way back to the page before it. Fixed height, so nothing shifts.
class _SliderNote extends StatelessWidget {
  const _SliderNote({
    required this.dragging,
    required this.before,
    required this.onBack,
  });

  final double? dragging;
  final String? before;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final d = dragging;
    final b = before;
    final Widget child;
    if (d != null) {
      child = Text(
        'Go to ${(d * 100).round()}% of the book',
        style: theme.textTheme.labelMedium?.copyWith(
          fontWeight: FontWeight.w700,
        ),
      );
    } else if (b != null) {
      child = JumpBackChip(
        label: b.isEmpty ? 'Back to where you were' : 'Back to $b',
        onTap: onBack,
      );
    } else {
      return const SizedBox.shrink();
    }
    return SizedBox(height: 36, child: Center(child: child));
  }
}
