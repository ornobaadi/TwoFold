import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/theme.dart';
import 'pane.dart';
import 'search.dart';

/// Finds words in the book. Returns the hit the user tapped.
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key, required this.actions});

  final ReaderActions actions;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _hits = <SearchHit>[];
  StreamSubscription<SearchHit>? _running;
  Timer? _delay;
  bool _searching = false;
  String _query = '';

  @override
  void dispose() {
    _running?.cancel();
    _delay?.cancel();
    super.dispose();
  }

  void _changed(String text) {
    _delay?.cancel();
    _delay = Timer(
      const Duration(milliseconds: 400),
      () => _start(text.trim()),
    );
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = context.twofold;
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(Space.m),
              child: SearchBar(
                autoFocus: true,
                hintText: 'Search this book',
                elevation: const WidgetStatePropertyAll(0),
                constraints: const BoxConstraints(minHeight: 56),
                textInputAction: TextInputAction.search,
                leading: IconButton(
                  tooltip: 'Back',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.arrow_back_rounded),
                ),
                onChanged: _changed,
                onSubmitted: (t) {
                  _delay?.cancel();
                  _start(t.trim());
                },
              ),
            ),
            SizedBox(
              height: 4,
              child: _searching ? const LinearProgressIndicator() : null,
            ),
            if (_hits.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  Space.l,
                  Space.m,
                  Space.l,
                  Space.xs,
                ),
                child: Text(
                  '${_hits.length}${_hits.length >= 300 ? '+' : ''} '
                  '${_hits.length == 1 ? 'result' : 'results'}',
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
      final message = _query.length < 2
          ? 'Type a word or phrase to find every place it appears.'
          : _searching
          ? 'Searching the book…'
          : 'Nothing found. Try fewer words.';
      return Padding(
        padding: const EdgeInsets.all(Space.xl),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyLarge?.copyWith(color: c.muted),
        ),
      );
    }
    return ListView.separated(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(Space.m, Space.xs, Space.m, Space.l),
      itemCount: _hits.length,
      separatorBuilder: (_, _) => const SizedBox(height: Space.s),
      itemBuilder: (context, i) {
        final hit = _hits[i];
        final end = hit.matchStart + hit.matchLength;
        return Card(
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => Navigator.of(context).pop(hit),
            child: Padding(
              padding: const EdgeInsets.all(Space.l),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(hit.pageLabel, style: theme.textTheme.labelMedium),
                  const SizedBox(height: Space.xs),
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: hit.snippet.substring(0, hit.matchStart),
                        ),
                        TextSpan(
                          text: hit.snippet.substring(hit.matchStart, end),
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: c.accent,
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
          ),
        );
      },
    );
  }
}
