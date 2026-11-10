import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../audio/player_controller.dart';
import 'pane.dart';
import 'search.dart';

/// What the user picked, with the results around it for stepping through.
class SearchResult {
  const SearchResult(this.query, this.hits, this.index);

  final String query;
  final List<SearchHit> hits;
  final int index;
}

/// Setting that keeps the last few searches, newest first, across books.
const recentSearchesKey = 'recent_searches';
const _recentLimit = 6;

/// Finds words in the book. Returns the result the user tapped.
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key, required this.actions, this.previous});

  final ReaderActions actions;

  /// An earlier search to come back to, instead of starting empty.
  final SearchResult? previous;

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _hits = <SearchHit>[];
  StreamSubscription<SearchHit>? _running;
  Timer? _delay;
  bool _searching = false;
  String _query = '';
  final _text = TextEditingController();
  List<String> _recent = const [];

  @override
  void initState() {
    super.initState();
    final previous = widget.previous;
    if (previous != null) {
      _query = previous.query;
      _text.text = previous.query;
      _hits.addAll(previous.hits);
    }
    _loadRecent();
  }

  Future<void> _loadRecent() async {
    try {
      final raw = await ref
          .read(bookRepoProvider)
          .getSetting(recentSearchesKey);
      if (raw == null || !mounted) return;
      setState(() => _recent = List<String>.from(jsonDecode(raw) as List));
    } catch (_) {
      // A damaged list is simply forgotten.
    }
  }

  Future<void> _remember(String query) async {
    final list = [
      query,
      ..._recent.where((q) => q.toLowerCase() != query.toLowerCase()),
    ].take(_recentLimit).toList();
    _recent = list;
    await ref
        .read(bookRepoProvider)
        .setSetting(recentSearchesKey, jsonEncode(list));
  }

  Future<void> _clearRecent() async {
    setState(() => _recent = const []);
    await ref.read(bookRepoProvider).deleteSetting(recentSearchesKey);
  }

  @override
  void dispose() {
    _text.dispose();
    _running?.cancel();
    _delay?.cancel();
    super.dispose();
  }

  void _changed(String text) {
    setState(() {}); // Shows or hides the clear button.
    _delay?.cancel();
    _delay = Timer(
      const Duration(milliseconds: 400),
      () => _start(text.trim()),
    );
  }

  void _use(String query) {
    _text.text = query;
    _text.selection = TextSelection.collapsed(offset: query.length);
    _delay?.cancel();
    _start(query);
  }

  void _clear() {
    _text.clear();
    _delay?.cancel();
    _start('');
  }

  void _start(String query) {
    _running?.cancel();
    setState(() {
      _query = query;
      _hits.clear();
      _searching = query.length >= 2;
    });
    if (query.length < 2) return;
    _running = widget.actions
        .search(query)
        .listen(
          (hit) {
            if (mounted) setState(() => _hits.add(hit));
          },
          onDone: () {
            if (mounted) setState(() => _searching = false);
          },
          onError: (_) {
            if (mounted) setState(() => _searching = false);
          },
        );
  }

  void _pick(int i) {
    _remember(_query);
    Navigator.of(context).pop(SearchResult(_query, List.of(_hits), i));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = context.twofold;
    final count = _hits.length;
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(Space.m),
              child: SearchBar(
                controller: _text,
                // The keyboard waits when coming back to existing results.
                autoFocus: widget.previous == null,
                hintText: 'Search this book',
                elevation: const WidgetStatePropertyAll(0),
                constraints: const BoxConstraints(minHeight: 52),
                textInputAction: TextInputAction.search,
                leading: IconButton(
                  tooltip: 'Back',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.arrow_back_rounded),
                ),
                trailing: [
                  if (_text.text.isNotEmpty)
                    IconButton(
                      tooltip: 'Clear',
                      onPressed: _clear,
                      icon: const Icon(Icons.close_rounded),
                    ),
                ],
                onChanged: _changed,
                onSubmitted: (t) {
                  _delay?.cancel();
                  _start(t.trim());
                },
              ),
            ),
            SizedBox(
              height: 2,
              child: _searching ? const LinearProgressIndicator() : null,
            ),
            if (count > 0)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  Space.l,
                  Space.m,
                  Space.l,
                  Space.xs,
                ),
                child: Text(
                  '$count${count >= 300 ? '+' : ''} '
                  '${count == 1 ? 'place' : 'places'}'
                  '${_searching ? ' so far' : ''}',
                  style: theme.textTheme.labelMedium,
                ),
              ),
            Expanded(child: _results(theme, c)),
          ],
        ),
      ),
    );
  }

  Widget _results(ThemeData theme, TwoFoldColors c) {
    if (_hits.isEmpty) {
      if (_query.length < 2) return _intro(theme, c);
      return Padding(
        padding: const EdgeInsets.all(Space.xl),
        child: Text(
          _searching
              ? 'Searching the book…'
              : 'Nothing found for “$_query”. Try fewer or shorter words.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyLarge?.copyWith(color: c.muted),
        ),
      );
    }
    return ListView.separated(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.only(bottom: Space.l),
      itemCount: _hits.length,
      separatorBuilder: (_, _) =>
          const Divider(indent: Space.l, endIndent: Space.l),
      itemBuilder: (context, i) => _HitRow(
        key: ValueKey('search-hit-$i'),
        hit: _hits[i],
        onTap: () => _pick(i),
      ),
    );
  }

  /// Before typing: what search finds, and the last few searches.
  Widget _intro(ThemeData theme, TwoFoldColors c) => ListView(
    padding: const EdgeInsets.fromLTRB(Space.l, Space.l, Space.l, Space.l),
    children: [
      Text(
        'Find every place a word or phrase appears. '
        'Capitals and curly quotes don’t matter.',
        style: theme.textTheme.bodyMedium?.copyWith(color: c.muted),
      ),
      if (_recent.isNotEmpty) ...[
        const SizedBox(height: Space.xl),
        Row(
          children: [
            Expanded(child: Text('Recent', style: theme.textTheme.labelLarge)),
            TextButton(onPressed: _clearRecent, child: const Text('Clear')),
          ],
        ),
        Wrap(
          spacing: Space.s,
          runSpacing: Space.s,
          children: [
            for (final q in _recent)
              ActionChip(
                avatar: const Icon(Icons.history_rounded, size: 16),
                label: Text(q),
                onPressed: () => _use(q),
              ),
          ],
        ),
      ],
    ],
  );
}

/// One result: where it is (page and how far in), and the line around it.
class _HitRow extends StatelessWidget {
  const _HitRow({super.key, required this.hit, required this.onTap});

  final SearchHit hit;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = context.twofold;
    final s = theme.colorScheme;
    final end = hit.matchStart + hit.matchLength;
    final percent = (hit.fraction * 100).clamp(0, 100).round();
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Space.l, Space.m, Space.l, Space.m),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(hit.pageLabel, style: theme.textTheme.labelMedium),
                const SizedBox(width: Space.s),
                // Where in the book, at a glance.
                SizedBox(
                  width: 48,
                  height: 3,
                  child: Stack(
                    children: [
                      Container(color: s.onSurface.withValues(alpha: 0.12)),
                      FractionallySizedBox(
                        widthFactor: hit.fraction.clamp(0.02, 1.0),
                        child: Container(color: s.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: Space.xs),
                Text('$percent%', style: theme.textTheme.labelSmall),
              ],
            ),
            const SizedBox(height: Space.xs),
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: hit.snippet.substring(0, hit.matchStart)),
                  TextSpan(
                    text: hit.snippet.substring(hit.matchStart, end),
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: s.onSurface,
                      backgroundColor: c.accent.withValues(alpha: 0.18),
                    ),
                  ),
                  TextSpan(text: hit.snippet.substring(end)),
                ],
              ),
              style: theme.textTheme.bodyLarge?.copyWith(
                fontFamily: serifFont,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
