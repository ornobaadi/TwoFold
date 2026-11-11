import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/router.dart';
import '../../app/theme.dart';
import '../../audio/player_controller.dart';
import '../../data/models.dart';
import '../../find/book_info.dart';
import 'details_parts.dart';
import 'keep_details.dart';
import '../listen/audiobook_sheet.dart';
import '../../find/librivox.dart';
import '../../audio/downloads.dart' show formatSize;
import '../../find/book_source.dart';
import '../../find/opds_source.dart';
import '../../find/web.dart';
import '../../import/importer.dart';
import '../library/providers.dart';
import 'providers.dart';

/// Where a downloaded book is remembered, so a second search shows it as
/// already in the library.
String foundKey(FoundBook b) => 'found:${b.key}';

/// Where the user's own catalogs are kept: a JSON list of name and link.
const catalogsKey = 'find_catalogs';

/// A file name that is safe to hand to the importer.
String safeFileName(String title) {
  final clean = title.replaceAll(RegExp(r'[\\/:*?"<>|\s]+'), ' ').trim();
  return clean.isEmpty
      ? 'Book'
      : (clean.length > 80 ? clean.substring(0, 80) : clean);
}

/// A catalog link the user typed, or null with the reason in [why].
Uri? catalogLink(String text, {void Function(String why)? why}) {
  var t = text.trim();
  if (t.isEmpty) {
    why?.call('Paste the catalog link.');
    return null;
  }
  if (!t.contains('://')) t = 'https://$t';
  final url = Uri.tryParse(t);
  if (url == null || url.host.isEmpty) {
    why?.call('That does not look like a link.');
    return null;
  }
  if (url.scheme != 'https') {
    why?.call('Only secure links (https) can be added.');
    return null;
  }
  return url;
}

class _Get {
  const _Get({
    this.working = false,
    this.received = 0,
    this.total,
    this.adding = false,
    this.error,
    this.book,
  });

  final bool working;
  final int received;
  final int? total;

  /// Downloaded; now being read into the library.
  final bool adding;
  final String? error;

  /// Set once the book is in the library.
  final Book? book;

  double? get progress =>
      total == null || total == 0 ? null : (received / total!).clamp(0.0, 1.0);
}

/// Browse or search the free libraries, get a book, and it is in the library.
class FindScreen extends ConsumerStatefulWidget {
  const FindScreen({super.key, this.active = true, this.onExit});

  /// False while another dock tab is showing, so back is left to that tab.
  final bool active;

  /// Leaves Find when it is a dock tab; null when Find is its own screen.
  final VoidCallback? onExit;

  @override
  ConsumerState<FindScreen> createState() => _FindScreenState();
}

class _FindScreenState extends ConsumerState<FindScreen> {
  final _field = TextEditingController();
  late BookSource _source;

  /// Lists of each site, once read.
  final _shelves = <String, List<Shelf>>{};
  bool _loadingShelves = false;
  String? _shelvesError;

  /// What the list shows: a search ([_query]) or a path of lists ([_trail]).
  bool _listing = false;
  String _query = '';
  final _trail = <Shelf>[];

  bool _loading = false;
  bool _loadingMore = false;
  bool _hasMore = false;
  int _page = 0;
  String? _error;
  List<FoundBook> _books = const [];
  List<Shelf> _inner = const [];

  final _gets = <String, _Get>{};

  /// Books got on this visit, shown in the tray, oldest first.
  final _tray = <FoundBook>[];

  /// Ticks whenever a download changes, for the details sheet.
  final _changed = ValueNotifier(0);
  int _run = 0;

  @override
  void initState() {
    super.initState();
    _source = ref.read(findServiceProvider).sources.first;
    _loadCatalogs();
    _openSource(_source);
  }

  @override
  void dispose() {
    _run++;
    _field.dispose();
    _changed.dispose();
    super.dispose();
  }

  Future<void> _loadCatalogs() async {
    final raw = await ref.read(bookRepoProvider).getSetting(catalogsKey);
    if (raw == null || !mounted) return;
    try {
      final list = [
        for (final c in (jsonDecode(raw) as List).cast<Map<String, dynamic>>())
          (name: '${c['name']}', url: Uri.parse('${c['url']}')),
      ];
      ref.read(findServiceProvider).setCatalogs(list);
      if (mounted) setState(() {});
    } catch (_) {
      // A broken list is ignored rather than blocking the screen.
    }
  }

  Future<void> _saveCatalogs() => ref
      .read(bookRepoProvider)
      .setSetting(
        catalogsKey,
        jsonEncode([
          for (final c in ref.read(findServiceProvider).catalogs)
            {'name': c.name, 'url': c.root.toString()},
        ]),
      );

  void _setGet(String key, _Get value) {
    if (!mounted) return;
    setState(() => _gets[key] = value);
    _changed.value++;
  }

  Future<void> _openSource(BookSource source) async {
    final run = ++_run;
    setState(() {
      _source = source;
      _listing = false;
      _trail.clear();
      _shelvesError = null;
    });
    if (_shelves.containsKey(source.id)) return;
    setState(() => _loadingShelves = true);
    try {
      final shelves = await source.shelves();
      if (!mounted || run != _run) return;
      setState(() {
        _shelves[source.id] = shelves;
        _loadingShelves = false;
      });
    } catch (e) {
      if (!mounted || run != _run) return;
      setState(() {
        _shelvesError = e is WebError
            ? e.message
            : 'Could not read ${source.name}.';
        _loadingShelves = false;
      });
    }
  }

  /// Filters on the list on screen; nothing is asked of the site again.
  LengthFilter _length = LengthFilter.any;
  bool _oneReader = false;
  bool _notOwned = false;

  bool _keeps(FoundBook b) =>
      _length.keeps(b) &&
      (!_oneReader || !b.isRecording || b.readerCount == 1) &&
      (!_notOwned || _gets[b.key]?.book == null);

  void _pick(BookSource source) {
    if (source.id == _source.id) return;
    _length = LengthFilter.any;
    _oneReader = false;
    _notOwned = false;
    final query = _field.text.trim();
    _openSource(source).then((_) {
      if (query.isNotEmpty && mounted && _source.canSearch) _search();
    });
  }

  Future<void> _search() async {
    final query = _field.text.trim();
    if (query.isEmpty) return;
    FocusManager.instance.primaryFocus?.unfocus();
    _trail.clear();
    _query = query;
    await _load(() => _source.search(query));
  }

  Future<void> _browse(Shelf shelf) async {
    _trail.add(shelf);
    _query = '';
    await _load(() => _source.browse(shelf));
  }

  void _back() {
    if (_trail.length > 1) {
      _trail.removeLast();
      final shelf = _trail.removeLast();
      _browse(shelf);
    } else {
      _run++;
      setState(() {
        _trail.clear();
        _listing = false;
        _loading = false;
      });
    }
  }

  Future<void> _load(Future<FoundPage> Function() fetch) async {
    final run = ++_run;
    setState(() {
      _listing = true;
      _loading = true;
      _error = null;
      _books = const [];
      _inner = const [];
      _hasMore = false;
      _page = 0;
    });
    try {
      final page = await fetch();
      if (!mounted || run != _run) return;
      setState(() {
        _books = page.books;
        _inner = page.shelves;
        _hasMore = page.hasMore;
        _loading = false;
      });
      await _markOwned(page.books, run);
    } catch (e) {
      if (!mounted || run != _run) return;
      setState(() {
        _error = e is WebError
            ? e.message
            : 'The answer from ${_source.name} was not what we expected.';
        _loading = false;
      });
    }
  }

  Future<void> _retry() =>
      _query.isNotEmpty ? _search() : _browse(_trail.removeLast());

  Future<void> _more() async {
    if (_loadingMore) return;
    final run = _run;
    setState(() => _loadingMore = true);
    try {
      final next = _page + 1;
      final page = _query.isNotEmpty
          ? await _source.search(_query, page: next)
          : await _source.browse(_trail.last, page: next);
      if (!mounted || run != _run) return;
      final known = _books.map((b) => b.key).toSet();
      final fresh = [
        for (final b in page.books)
          if (!known.contains(b.key)) b,
      ];
      setState(() {
        _page = next;
        _books = [..._books, ...fresh];
        _hasMore = page.hasMore && fresh.isNotEmpty;
        _loadingMore = false;
      });
      await _markOwned(fresh, run);
    } catch (e) {
      if (mounted && run == _run) {
        setState(() => _loadingMore = false);
        _toast(e is WebError ? e.message : 'Could not load more.');
      }
    }
  }

  /// Books fetched before show as already in the library.
  Future<void> _markOwned(List<FoundBook> books, int run) async {
    final repo = ref.read(bookRepoProvider);
    for (final b in books) {
      final id = await repo.getSetting(foundKey(b));
      final book = id == null ? null : await repo.getBook(id);
      if (!mounted || run != _run) return;
      if (book != null) _setGet(b.key, _Get(book: book));
    }
  }

  Future<void> _get(FoundBook b) async {
    if (_gets[b.key]?.working == true) return;
    _setGet(b.key, const _Get(working: true));
    setState(() {
      _tray.removeWhere((t) => t.key == b.key);
      _tray.add(b);
    });
    final service = ref.read(findServiceProvider);
    final importer = ref.read(importerProvider);
    final repo = ref.read(bookRepoProvider);
    var shown = -1;
    try {
      final (file, format) = await service.download(
        b,
        onProgress: (got, total) {
          // Redraw every 64 KB or so; plenty for a smooth bar.
          if (got - shown < (64 << 10) && got != total) return;
          shown = got;
          _setGet(b.key, _Get(working: true, received: got, total: total));
        },
      );
      _setGet(
        b.key,
        _Get(working: true, adding: true, received: shown, total: shown),
      );
      try {
        final draft = await importer.importLocalFile(
          file.path,
          fileName: '${safeFileName(b.title)}${format.extension}',
        );
        final book = await importer.commit(
          draft,
          title: b.title,
          author: b.author ?? draft.author,
          audio: const [],
        );
        await repo.setSetting(foundKey(b), book.id);
        ref.invalidate(libraryProvider);
        _setGet(b.key, _Get(book: book));
        // In the background: keep the details and fetch a real cover.
        keepFindDetails(
          repo: repo,
          importer: importer,
          covers: service.covers,
          book: book,
          found: b,
          sourceName: service.sourceOf(b.source).name,
          info: _info(b),
        ).then((changed) {
          if (changed && mounted) ref.invalidate(libraryProvider);
        });
        if (_withAudio[b.key] ?? true) {
          final list = await _audioFor(b);
          if (list.isNotEmpty && mounted) await _addAudio(b, book);
        }
      } finally {
        if (file.existsSync()) await file.delete();
      }
    } on WebError catch (e) {
      _setGet(b.key, _Get(error: e.message));
    } on ImportError {
      _setGet(
        b.key,
        const _Get(
          error: 'This file downloaded, but TwoFold could not read it.',
        ),
      );
    } catch (_) {
      _setGet(b.key, const _Get(error: 'Something went wrong. Try again.'));
    }
  }

  void _open(Book book) => openReader(context, book);

  void _toast(String message) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));

  Future<void> _addCatalog() async {
    final added = await showDialog<({String name, Uri url})>(
      context: context,
      builder: (_) => const _AddCatalogDialog(),
    );
    if (added == null || !mounted) return;
    final service = ref.read(findServiceProvider);
    if (service.sources.any((s) => s is OpdsSource && s.root == added.url)) {
      _toast('That catalog is already here.');
      return;
    }
    service.setCatalogs([
      for (final c in service.catalogs) (name: c.name, url: c.root),
      added,
    ]);
    await _saveCatalogs();
    if (!mounted) return;
    _openSource(service.catalogs.last);
  }

  Future<void> _removeCatalog(OpdsSource source) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text('Remove "${source.name}"?'),
        content: const Text('Books you got from it stay in your library.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(d).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(d).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    final service = ref.read(findServiceProvider);
    service.setCatalogs([
      for (final c in service.catalogs)
        if (c != source) (name: c.name, url: c.root),
    ]);
    _shelves.remove(source.id);
    await _saveCatalogs();
    if (mounted && _source.id == source.id) _openSource(service.sources.first);
  }

  /// Open Library's details, asked for once per book and only when opened.
  Future<BookInfo?> _info(FoundBook b) => _infos.putIfAbsent(
        b.key,
        () => ref
            .read(findServiceProvider)
            .info
            .lookUp(b)
            .then<BookInfo?>((i) => i, onError: (Object _) => null),
      );
  final _infos = <String, Future<BookInfo?>>{};

  /// LibriVox recordings, looked up once per book when its details open.
  /// A recording picked in the LibriVox library comes first.
  Future<List<LibrivoxBook>> _audioFor(FoundBook b) => _audio.putIfAbsent(
        b.key,
        () {
          final service = ref.read(findServiceProvider);
          final chosen =
              b.source == 'librivox' ? service.recordings.recording(b.id) : null;
          if (chosen != null) return Future.value([chosen]);
          return service.librivox
              .find(
                b.title,
                author: b.author,
                gutenbergId: b.source == 'gutenberg' ? b.id : null,
              )
              .then((list) => list, onError: (Object _) => <LibrivoxBook>[]);
        },
      );
  final _audio = <String, Future<List<LibrivoxBook>>>{};

  /// Whether Get also adds the free audiobook, per book (yes unless unticked).
  final _withAudio = <String, bool>{};

  /// Books whose audiobook is being added, to show progress on the card.
  final _addingAudio = <String>{};

  Future<void> _addAudio(FoundBook b, Book book) async {
    final list = await _audioFor(b);
    if (list.isEmpty || _addingAudio.contains(b.key)) return;
    _addingAudio.add(b.key);
    _changed.value++;
    try {
      await attachRecording(ref, book, list.first, save: true);
      _toast('Audiobook added. It plays now and saves itself for offline.');
    } catch (_) {
      _toast('The audiobook could not be added. Try again from the book.');
    } finally {
      _addingAudio.remove(b.key);
      _changed.value++;
    }
  }

  void _details(FoundBook b) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => ValueListenableBuilder(
        valueListenable: _changed,
        builder: (context, _, _) => _DetailsSheet(
          book: b,
          sourceName: _source.name,
          state: _gets[b.key],
          info: _info(b),
          service: ref.read(findServiceProvider).info,
          onGet: () => _get(b),
          onOpen: (book) {
            Navigator.of(context).pop();
            _open(book);
          },
          audio: _audioFor(b),
          withAudio: _withAudio[b.key] ?? true,
          onWithAudio: (v) {
            _withAudio[b.key] = v;
            _changed.value++;
          },
          onAddAudio: (book) => _addAudio(b, book),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sources = ref.watch(findServiceProvider).sources;
    return PopScope(
      canPop: !widget.active || (!_listing && widget.onExit == null),
      onPopInvokedWithResult: (popped, _) {
        if (popped || !widget.active) return;
        if (_listing) {
          _back();
        } else {
          widget.onExit?.call();
        }
      },
      child: Scaffold(
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  Space.xs,
                  Space.s,
                  Space.xs,
                  0,
                ),
                child: Row(
                  children: [
                    if (widget.onExit == null || _listing)
                      IconButton(
                        tooltip: _listing ? 'Back' : 'Back to library',
                        onPressed: _listing
                            ? _back
                            : () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.arrow_back_rounded),
                      )
                    else
                      const SizedBox(width: Space.m),
                    Expanded(
                      child: Text(
                        'Find free books',
                        style: theme.textTheme.titleLarge,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Add a catalog',
                      onPressed: _addCatalog,
                      icon: const Icon(Icons.add_link_rounded),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  Space.l,
                  Space.s,
                  Space.l,
                  Space.m,
                ),
                child: SearchBar(
                  controller: _field,
                  enabled: _source.canSearch,
                  hintText: _source.canSearch
                      ? 'Title or author in ${_source.name}'
                      : '${_source.name} cannot be searched',
                  constraints: const BoxConstraints(minHeight: 44),
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _search(),
                  leading: const Padding(
                    padding: EdgeInsets.only(left: Space.xs),
                    child: Icon(Icons.search_rounded),
                  ),
                  trailing: [
                    IconButton(
                      tooltip: 'Search',
                      onPressed: _source.canSearch ? _search : null,
                      icon: const Icon(Icons.arrow_forward_rounded),
                    ),
                  ],
                ),
              ),
              SizedBox(
                height: 44,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: Space.l),
                  children: [
                    for (final s in sources)
                      Padding(
                        padding: const EdgeInsets.only(right: Space.s),
                        child: GestureDetector(
                          onLongPress: s is OpdsSource && s.id != 'unglue'
                              ? () => _removeCatalog(s)
                              : null,
                          child: ChoiceChip(
                            label: Text(s.name),
                            selected: s.id == _source.id,
                            onSelected: (_) => _pick(s),
                          ),
                        ),
                      ),
                    ActionChip(
                      avatar: const Icon(Icons.add_rounded, size: 18),
                      label: const Text('Add catalog'),
                      onPressed: _addCatalog,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: Space.s),
              const Divider(),
              Expanded(child: _listing ? _list(theme) : _home(theme)),
              AnimatedSize(
                duration: easeDuration,
                curve: easeCurve,
                alignment: Alignment.topCenter,
                child: _tray.isEmpty
                    ? const SizedBox(width: double.infinity)
                    : _DownloadTray(
                        books: _tray,
                        gets: _gets,
                        onTap: _details,
                        onOpen: _open,
                        onRetry: _get,
                        onDismiss: (b) => setState(
                          () => _tray.removeWhere((t) => t.key == b.key),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The site's lists to browse, and what it is.
  Widget _home(ThemeData theme) {
    final c = context.twofold;
    final shelves = _shelves[_source.id];
    return ListView(
      padding: const EdgeInsets.fromLTRB(Space.l, Space.l, Space.l, Space.xl),
      children: [
        Text(
          _source.blurb,
          style: theme.textTheme.bodyMedium?.copyWith(color: c.muted),
        ),
        const SizedBox(height: Space.l),
        if (_loadingShelves)
          const Padding(
            padding: EdgeInsets.all(Space.xl),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_shelvesError != null)
          _Note(
            icon: Icons.cloud_off_rounded,
            text: _shelvesError!,
            action: OutlinedButton(
              onPressed: () => _openSource(_source),
              child: const Text('Try again'),
            ),
          )
        else if (shelves != null && shelves.isNotEmpty) ...[
          Text('BROWSE', style: _overline(theme)),
          const SizedBox(height: Space.s),
          _ShelfList(shelves: shelves, onOpen: _browse),
        ] else
          _Note(
            icon: Icons.search_rounded,
            text: 'Search ${_source.name} by title or author.',
          ),
        const SizedBox(height: Space.xl),
        Text(
          'Books and audiobooks here are free and are saved in your library. '
          'TwoFold goes online only when you search, browse or get one.',
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }

  Widget _list(ThemeData theme) {
    final title = _query.isNotEmpty
        ? 'Results for "$_query"'
        : _trail.last.title;
    final header = Padding(
      padding: const EdgeInsets.fromLTRB(Space.xs, Space.s, Space.l, Space.s),
      child: Row(
        children: [
          IconButton(
            tooltip: _trail.length > 1
                ? 'Back to ${_trail[_trail.length - 2].title}'
                : 'Back to lists',
            onPressed: _back,
            icon: const Icon(Icons.chevron_left_rounded),
          ),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleMedium,
            ),
          ),
        ],
      ),
    );

    Widget body;
    if (_loading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_error != null) {
      body = _Note(
        icon: Icons.cloud_off_rounded,
        text: _error!,
        action: OutlinedButton(
          onPressed: _retry,
          child: const Text('Try again'),
        ),
      );
    } else if (_books.isEmpty && _inner.isEmpty) {
      body = _Note(
        icon: Icons.search_off_rounded,
        text: _query.isNotEmpty
            ? 'No results for "$_query". Try fewer words, or another library above.'
            : 'Nothing on this list right now.',
      );
    } else {
      final shown = _books.where(_keeps).toList();
      final recordings = _books.any((b) => b.isRecording);
      body = ListView(
        padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.xl),
        children: [
          if (_inner.isNotEmpty) ...[
            _ShelfList(shelves: _inner, onOpen: _browse),
            const SizedBox(height: Space.l),
          ],
          if (_books.isNotEmpty)
            _Filters(
              recordings: recordings,
              length: _length,
              oneReader: _oneReader,
              notOwned: _notOwned,
              onLength: (v) => setState(() => _length = v),
              onOneReader: (v) => setState(() => _oneReader = v),
              onNotOwned: (v) => setState(() => _notOwned = v),
              count: shown.length,
              total: _books.length,
            ),
          if (shown.isEmpty && _books.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: Space.xl),
              child: Text(
                'None of these match the filters.'
                '${_hasMore ? ' Show more to look further.' : ''}',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium,
              ),
            ),
          for (final b in shown)
            _ResultRow(
              book: b,
              state: _gets[b.key],
              onTap: () => _details(b),
              onGet: () => _get(b),
              onOpen: _open,
            ),
          if (_hasMore)
            Padding(
              padding: const EdgeInsets.only(top: Space.m),
              child: Center(
                child: _loadingMore
                    ? const Padding(
                        padding: EdgeInsets.all(Space.m),
                        child: CircularProgressIndicator(),
                      )
                    : OutlinedButton(
                        onPressed: _more,
                        child: const Text('Show more'),
                      ),
              ),
            ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header,
        Expanded(child: body),
      ],
    );
  }
}

TextStyle? _overline(ThemeData theme) => theme.textTheme.labelMedium?.copyWith(
  letterSpacing: 1.2,
  fontWeight: FontWeight.w600,
);

/// Lists as rows in one bordered block, like a book's contents page.
class _ShelfList extends StatelessWidget {
  const _ShelfList({required this.shelves, required this.onOpen});

  final List<Shelf> shelves;
  final ValueChanged<Shelf> onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = context.twofold;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (final (i, s) in shelves.indexed) ...[
            if (i > 0) const Divider(indent: Space.l),
            InkWell(
              onTap: () => onOpen(s),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 52),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    Space.l,
                    Space.m,
                    Space.s,
                    Space.m,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(s.title, style: theme.textTheme.titleMedium),
                            if (s.blurb != null)
                              Text(
                                s.blurb!,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: c.muted,
                                ),
                              ),
                          ],
                        ),
                      ),
                      Icon(Icons.chevron_right_rounded, color: c.muted),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// A cover drawn from the title, in a book-cloth colour, so lists look like a
/// shelf without fetching a picture for every book.
class FoundCover extends StatelessWidget {
  const FoundCover({super.key, required this.book, this.width = 40});

  final FoundBook book;
  final double width;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = clothFor(book.title);
    final small = width < 64;
    return ExcludeSemantics(
      child: SizedBox(
        width: width,
        height: width * 1.45,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(small ? 4 : 8),
          ),
          child: Padding(
            padding: EdgeInsets.all(width * 0.1),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: width * 0.25,
                  height: 1.5,
                  color: fg.withValues(alpha: 0.7),
                ),
                SizedBox(height: width * 0.08),
                Expanded(
                  // Too narrow for words: the first letter, set large.
                  child: Text(
                    small
                        ? book.title.characters.first.toUpperCase()
                        : book.title,
                    maxLines: small ? 1 : 5,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: serifFont,
                      fontSize: width * (small ? 0.42 : 0.11),
                      height: 1.15,
                      fontWeight: FontWeight.w600,
                      color: fg,
                    ),
                  ),
                ),
                if (!small && book.author != null)
                  Text(
                    book.author!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: uiFont,
                      fontSize: width * 0.075,
                      color: fg.withValues(alpha: 0.8),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ResultRow extends StatelessWidget {
  const _ResultRow({
    required this.book,
    required this.state,
    required this.onTap,
    required this.onGet,
    required this.onOpen,
  });

  final FoundBook book;
  final _Get? state;
  final VoidCallback onTap;
  final VoidCallback onGet;
  final ValueChanged<Book> onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = context.twofold;
    final get = state;
    final meta = [
      if (book.isRecording) recordingLine(book),
      if (book.detail != null && book.author != null) book.detail!,
      if (get?.book != null) 'In your library',
    ].join(' · ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: Space.m),
            child: Row(
              children: [
                FoundCover(book: book),
                const SizedBox(width: Space.l),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        book.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium,
                      ),
                      if (book.author != null)
                        Text(
                          book.author!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: c.muted,
                          ),
                        )
                      else if (book.detail != null)
                        Text(
                          book.detail!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: c.muted,
                          ),
                        ),
                      if (meta.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            meta,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelMedium,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: Space.s),
                _GetButton(
                  book: book,
                  state: get,
                  onGet: onGet,
                  onOpen: onOpen,
                ),
              ],
            ),
          ),
        ),
        if (get?.error != null)
          Padding(
            padding: const EdgeInsets.only(left: 40 + Space.m, bottom: Space.s),
            child: Text(
              get!.error!,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ),
        const Divider(),
      ],
    );
  }
}

String _mb(int bytes) {
  final mb = bytes / (1 << 20);
  return mb >= 10 ? mb.toStringAsFixed(0) : mb.toStringAsFixed(1);
}

/// "1.2 of 3.4 MB · 35%", or what is happening when that is not known.
String progressText(int received, int? total, {bool adding = false}) {
  if (adding) return 'Adding to your library…';
  if (received == 0) return 'Starting…';
  if (total == null || total == 0) return '${_mb(received)} MB so far';
  final pct = (received / total * 100).clamp(0, 100).round();
  return '${_mb(received)} of ${_mb(total)} MB · $pct%';
}

class _GetButton extends StatelessWidget {
  const _GetButton({
    required this.book,
    required this.state,
    required this.onGet,
    required this.onOpen,
    this.wide = false,
  });

  final FoundBook book;
  final _Get? state;
  final VoidCallback onGet;
  final ValueChanged<Book> onOpen;

  /// The full-width button of the details sheet.
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final get = state;
    final size = wide ? const Size(double.infinity, 44) : const Size(64, 36);
    if (get?.working == true) {
      final p = get!.adding ? null : get.progress;
      if (wide) {
        return Semantics(
          label: 'Getting ${book.title}',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LinearProgressIndicator(value: p, minHeight: 4),
              const SizedBox(height: Space.s),
              Text(
                progressText(get.received, get.total, adding: get.adding),
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ],
          ),
        );
      }
      return SizedBox(
        width: 64,
        height: 36,
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: Semantics(
              label: 'Getting ${book.title}',
              child: CircularProgressIndicator(value: p, strokeWidth: 2.5),
            ),
          ),
        ),
      );
    }
    final owned = get?.book;
    if (owned != null) {
      return FilledButton(
        style: FilledButton.styleFrom(
          minimumSize: size,
          backgroundColor: s.onSurface,
          foregroundColor: s.surface,
        ),
        onPressed: () => onOpen(owned),
        child: Text(wide ? 'Open in reader' : 'Open'),
      );
    }
    if (wide && get?.error == null) {
      return FilledButton.icon(
        style: FilledButton.styleFrom(
          minimumSize: size,
          backgroundColor: s.onSurface,
          foregroundColor: s.surface,
        ),
        onPressed: onGet,
        icon: const Icon(Icons.download_rounded, size: 18),
        label: const Text('Get book'),
      );
    }
    return OutlinedButton(
      style: OutlinedButton.styleFrom(minimumSize: size),
      onPressed: onGet,
      child: Text(get?.error == null ? 'Get' : 'Try again'),
    );
  }
}

/// Stars for a 1-5 rating, read out as words.
/// The book's cover from Open Library when it has one, else a drawn one.
class _Cover extends StatelessWidget {
  const _Cover({
    required this.book,
    required this.info,
    required this.service,
  });

  final FoundBook book;
  final BookInfo? info;
  final BookInfoService service;
  static const width = 88.0;

  @override
  Widget build(BuildContext context) {
    final drawn = FoundCover(book: book, width: width);
    final url = info?.cover;
    if (url == null) return drawn;
    return FutureBuilder(
      future: service.cover(url),
      builder: (context, snap) {
        final bytes = snap.data;
        if (bytes == null) return drawn;
        return ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.memory(
            bytes,
            width: width,
            height: width * 1.45,
            fit: BoxFit.cover,
            semanticLabel: 'Cover of ${book.title}',
            errorBuilder: (_, _, _) => drawn,
          ),
        );
      },
    );
  }
}

class _DetailsSheet extends StatefulWidget {
  const _DetailsSheet({
    required this.book,
    required this.sourceName,
    required this.state,
    required this.info,
    required this.service,
    required this.onGet,
    required this.onOpen,
    required this.audio,
    required this.withAudio,
    required this.onWithAudio,
    required this.onAddAudio,
  });

  final FoundBook book;
  final String sourceName;
  final _Get? state;
  final Future<BookInfo?> info;
  final BookInfoService service;
  final VoidCallback onGet;
  final ValueChanged<Book> onOpen;

  /// LibriVox recordings of this book, best first.
  final Future<List<LibrivoxBook>> audio;
  final bool withAudio;
  final ValueChanged<bool> onWithAudio;

  /// Adds the best recording to a book already in the library.
  final ValueChanged<Book> onAddAudio;

  @override
  State<_DetailsSheet> createState() => _DetailsSheetState();
}

class _DetailsSheetState extends State<_DetailsSheet> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = context.twofold;
    final book = widget.book;
    final state = widget.state;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.66,
      maxChildSize: 0.94,
      builder: (context, scroll) => FutureBuilder<BookInfo?>(
        future: widget.info,
        builder: (context, snap) {
          final info = snap.data;
          final looking = snap.connectionState != ConnectionState.done;
          final about = info?.description ?? book.summary;
          final facts = <(String, String)>[
            if (info?.firstYear != null)
              ('First published', '${info!.firstYear}')
            else if (book.detail != null && book.author != null)
              ('Year', book.detail!),
            if (info?.pages != null) ('Pages', '${info!.pages}'),
            if (book.isRecording) ...[
              ('Read by', book.reader ?? 'LibriVox volunteers'),
              ('Listening', formatLength(book.listenLength!)),
              if (book.sizeBytes != null) ('Audio size', formatSize(book.sizeBytes!)),
            ],
            (
              'Format',
              book.isRecording
                  ? 'EPUB from Project Gutenberg, MP3 audiobook'
                  : book.downloads.isEmpty
                  ? 'EPUB'
                  : book.downloads
                        .map((d) => d.format.name.toUpperCase())
                        .toSet()
                        .join(' or '),
            ),
            ('From', widget.sourceName),
          ];
          return ListView(
            controller: scroll,
            padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.xl),
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Cover(book: book, info: info, service: widget.service),
                  const SizedBox(width: Space.l),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(book.title, style: theme.textTheme.titleLarge),
                        if (book.author != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            book.author!,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: c.muted,
                            ),
                          ),
                        ],
                        const SizedBox(height: Space.s),
                        if (looking && info == null)
                          Text(
                            'Looking up details…',
                            style: theme.textTheme.labelMedium,
                          )
                        else
                          RatingLine(
                            rating: info?.rating,
                            count: info?.ratingCount ?? 0,
                            wantToRead: info?.wantToRead ?? 0,
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Space.l),
              _GetButton(
                book: book,
                state: state,
                onGet: widget.onGet,
                onOpen: widget.onOpen,
                wide: true,
              ),
              _FreeAudiobook(
                audio: widget.audio,
                state: state,
                withAudio: widget.withAudio,
                onWithAudio: widget.onWithAudio,
                onAddAudio: widget.onAddAudio,
              ),
              if (state?.error != null) ...[
                const SizedBox(height: Space.s),
                Text(
                  state!.error!,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ],
              const SizedBox(height: Space.l),
              FactsCard(facts),
              if (about != null) ...[
                const SizedBox(height: Space.xl),
                AboutText(about),
              ],
              if (info != null && info.subjects.isNotEmpty) ...[
                const SizedBox(height: Space.l),
                SubjectTags(info.subjects),
              ],
              if (info != null) ...[
                const SizedBox(height: Space.xl),
                Text(openLibraryNote, style: theme.textTheme.bodySmall),
              ],
            ],
          );
        },
      ),
    );
  }
}

/// Downloads in progress and just finished, kept in view at the bottom of
/// the screen with the book they are for.
class _DownloadTray extends StatelessWidget {
  const _DownloadTray({
    required this.books,
    required this.gets,
    required this.onTap,
    required this.onOpen,
    required this.onRetry,
    required this.onDismiss,
  });

  final List<FoundBook> books;
  final Map<String, _Get> gets;
  final ValueChanged<FoundBook> onTap;
  final ValueChanged<Book> onOpen;
  final ValueChanged<FoundBook> onRetry;
  final ValueChanged<FoundBook> onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = context.twofold;
    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Divider(),
            for (final b in books.reversed.take(3))
              Builder(
                builder: (context) {
                  final g = gets[b.key];
                  final done = g?.book;
                  final failed = g?.error;
                  final status = done != null
                      ? 'In your library'
                      : failed ??
                            progressText(
                              g?.received ?? 0,
                              g?.total,
                              adding: g?.adding ?? false,
                            );
                  return InkWell(
                    onTap: () => onTap(b),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(
                        Space.l,
                        Space.s,
                        Space.xs,
                        Space.s,
                      ),
                      child: Row(
                        children: [
                          FoundCover(book: b, width: 32),
                          const SizedBox(width: Space.m),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  b.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.titleSmall,
                                ),
                                Text(
                                  [
                                    if (b.author != null) b.author!,
                                    status,
                                  ].join(' · '),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.labelMedium?.copyWith(
                                    color: failed != null
                                        ? theme.colorScheme.error
                                        : c.muted,
                                  ),
                                ),
                                if (g?.working == true) ...[
                                  const SizedBox(height: Space.xs),
                                  LinearProgressIndicator(
                                    value: g!.adding ? null : g.progress,
                                    minHeight: 3,
                                  ),
                                ],
                              ],
                            ),
                          ),
                          if (done != null)
                            TextButton(
                              onPressed: () => onOpen(done),
                              child: const Text('Open'),
                            )
                          else if (failed != null)
                            TextButton(
                              onPressed: () => onRetry(b),
                              child: const Text('Retry'),
                            ),
                          if (g?.working != true)
                            IconButton(
                              tooltip: 'Hide',
                              onPressed: () => onDismiss(b),
                              icon: const Icon(Icons.close_rounded, size: 18),
                            )
                          else
                            const SizedBox(width: Space.m),
                        ],
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _AddCatalogDialog extends StatefulWidget {
  const _AddCatalogDialog();

  @override
  State<_AddCatalogDialog> createState() => _AddCatalogDialogState();
}

class _AddCatalogDialogState extends State<_AddCatalogDialog> {
  final _name = TextEditingController();
  final _link = TextEditingController();
  String? _problem;

  @override
  void dispose() {
    _name.dispose();
    _link.dispose();
    super.dispose();
  }

  void _add() {
    String? why;
    final url = catalogLink(_link.text, why: (w) => why = w);
    if (url == null) {
      setState(() => _problem = why);
      return;
    }
    final name = _name.text.trim().isEmpty ? url.host : _name.text.trim();
    Navigator.of(context).pop((name: name, url: url));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add a catalog'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Any OPDS catalog: your Calibre library, a public library, or a site '
            'that offers one. Only free downloads work; nothing that needs a login.',
          ),
          const SizedBox(height: Space.l),
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Name (optional)'),
          ),
          const SizedBox(height: Space.m),
          TextField(
            controller: _link,
            keyboardType: TextInputType.url,
            autocorrect: false,
            onSubmitted: (_) => _add(),
            decoration: InputDecoration(
              labelText: 'Catalog link',
              hintText: 'https://…/opds',
              errorText: _problem,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(onPressed: _add, child: const Text('Add')),
      ],
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.icon, required this.text, this.action});

  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Space.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 36, color: context.twofold.muted),
            const SizedBox(height: Space.m),
            Text(
              text,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge,
            ),
            if (action != null) ...[const SizedBox(height: Space.l), action!],
          ],
        ),
      ),
    );
  }
}

/// The free LibriVox recording of a book in Find, if there is one: who reads
/// it, how long and how big, and whether Get brings it along.
class _FreeAudiobook extends StatelessWidget {
  const _FreeAudiobook({
    required this.audio,
    required this.state,
    required this.withAudio,
    required this.onWithAudio,
    required this.onAddAudio,
  });

  final Future<List<LibrivoxBook>> audio;
  final _Get? state;
  final bool withAudio;
  final ValueChanged<bool> onWithAudio;
  final ValueChanged<Book> onAddAudio;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FutureBuilder<List<LibrivoxBook>>(
      future: audio,
      builder: (context, snap) {
        final list = snap.data;
        if (list == null || list.isEmpty) return const SizedBox.shrink();
        final r = list.first;
        final inLibrary = state?.book;
        final busy = state?.working == true;
        return Padding(
          padding: const EdgeInsets.only(top: Space.m),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(Space.l, Space.m, Space.s, Space.s),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.headphones_rounded, size: 18),
                      const SizedBox(width: Space.s),
                      Text(
                        'FREE AUDIOBOOK',
                        style: theme.textTheme.labelMedium?.copyWith(letterSpacing: 1.2),
                      ),
                    ],
                  ),
                  const SizedBox(height: Space.xs),
                  Text('Read by ${r.readerLine}', style: theme.textTheme.titleSmall),
                  Text(
                    '${formatLength(r.total)} · ${r.parts.length} parts · '
                    '${formatSize(r.bytes)} · from LibriVox',
                    style: theme.textTheme.bodySmall,
                  ),
                  if (inLibrary == null)
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      dense: true,
                      title: const Text('Add it with the book'),
                      subtitle: const Text('Plays right away, saves for offline'),
                      value: withAudio,
                      onChanged: busy ? null : (v) => onWithAudio(v ?? true),
                    )
                  else
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () => onAddAudio(inLibrary),
                        icon: const Icon(Icons.add_rounded, size: 18),
                        label: const Text('Add audiobook'),
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

/// "Read by Annie · 9 h 4 min · 260 MB" for a recording in a list.
String recordingLine(FoundBook b) => [
  if (b.reader != null) 'Read by ${b.reader}',
  if (b.listenLength != null) formatLength(b.listenLength!),
  if (b.sizeBytes != null) formatSize(b.sizeBytes!),
].join(' · ');

/// Length filters for lists of recordings.
enum LengthFilter {
  any('Any length', 0, 1 << 30),
  short('Under 3 h', 0, 3),
  medium('3 to 10 h', 3, 10),
  long('Over 10 h', 10, 1 << 30);

  const LengthFilter(this.label, this.fromHours, this.toHours);

  final String label;
  final int fromHours;
  final int toHours;

  bool keeps(FoundBook b) {
    final l = b.listenLength;
    if (l == null || this == any) return true;
    final h = l.inMinutes / 60;
    return h >= fromHours && h < toHours;
  }
}

/// Quick filters over a list: length for recordings, one reader, and books
/// not yet in the library.
class _Filters extends StatelessWidget {
  const _Filters({
    required this.recordings,
    required this.length,
    required this.oneReader,
    required this.notOwned,
    required this.onLength,
    required this.onOneReader,
    required this.onNotOwned,
    required this.count,
    required this.total,
  });

  final bool recordings;
  final LengthFilter length;
  final bool oneReader;
  final bool notOwned;
  final ValueChanged<LengthFilter> onLength;
  final ValueChanged<bool> onOneReader;
  final ValueChanged<bool> onNotOwned;
  final int count;
  final int total;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final chips = <Widget>[
      if (recordings)
        for (final f in LengthFilter.values)
          ChoiceChip(
            label: Text(f.label),
            selected: length == f,
            onSelected: (_) => onLength(f),
          ),
      if (recordings)
        FilterChip(
          label: const Text('One reader'),
          selected: oneReader,
          onSelected: onOneReader,
        ),
      FilterChip(
        label: const Text('Not in my library'),
        selected: notOwned,
        onSelected: onNotOwned,
      ),
    ];
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.s),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 44,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: chips.length,
              separatorBuilder: (_, _) => const SizedBox(width: Space.s),
              itemBuilder: (_, i) => Center(child: chips[i]),
            ),
          ),
          if (count != total)
            Text('Showing $count of $total', style: theme.textTheme.labelMedium),
        ],
      ),
    );
  }
}
