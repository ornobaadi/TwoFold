import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/bubbly.dart';
import '../../app/format.dart';
import '../../app/theme.dart';
import '../../audio/audio_handler.dart';
import '../../audio/player_controller.dart';
import '../../data/models.dart';
import '../../import/device_files.dart';
import '../../import/importer.dart';
import '../../import/names.dart';
import 'book_card.dart';
import 'providers.dart';

/// Adds a book, or edits one: choose the book file, choose all audio files at
/// once, put them in order. Files are only committed by the bottom button.
class NewBookScreen extends ConsumerStatefulWidget {
  const NewBookScreen({super.key, this.editing});

  final Book? editing;

  @override
  ConsumerState<NewBookScreen> createState() => _NewBookScreenState();
}

class _NewBookScreenState extends ConsumerState<NewBookScreen> {
  final _title = TextEditingController();
  final _author = TextEditingController();
  final _audio = <AudioDraft>[];

  DraftBook? _draft;
  String? _coverPath;
  bool _readingBook = false;
  bool _pickingAudio = false;
  String? _progress;
  String? _error;

  Book? get _editing => widget.editing;
  bool get _busy => _progress != null;
  bool get _hasBook => _draft != null || _editing != null;

  @override
  void initState() {
    super.initState();
    final book = _editing;
    if (book != null) {
      _title.text = book.title;
      _author.text = book.author ?? '';
      ref.read(bookRepoProvider).tracksFor(book.id).then((tracks) {
        if (mounted)
          setState(() => _audio.addAll(tracks.map(AudioDraft.existing)));
      });
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _author.dispose();
    super.dispose();
  }

  Future<void> _pickBook() async {
    setState(() {
      _error = null;
    });
    final file = await DeviceFiles.pickBook();
    if (file == null) return;
    setState(() => _readingBook = true);
    final importer = ref.read(importerProvider);
    try {
      final draft = await importer.importBookFile(file);
      final old = _draft;
      if (old != null) await importer.discard(old.id);
      if (!mounted) return;
      setState(() {
        _draft = draft;
        _title.text = draft.title;
        _author.text = draft.author ?? '';
      });
    } on ImportError catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _readingBook = false);
    }
  }

  Future<void> _pickAudio(
    Future<List<PickedFile>> Function() pick, {
    bool replace = false,
  }) async {
    setState(() {
      _error = null;
      _pickingAudio = true;
    });
    try {
      final files = await pick();
      if (!mounted || files.isEmpty) return;
      if (replace) setState(_audio.clear);
      final known = _audio.map((a) => a.source).toSet();
      final fresh = files
          .where((f) => !known.contains(f.uri))
          .map(AudioDraft.picked)
          .toList();
      setState(() => _audio.addAll(fresh));
      // Lengths fill in one by one; the screen stays usable meanwhile.
      for (final d in fresh) {
        final length = await probeDuration(d.source);
        if (mounted) setState(() => d.duration = length);
      }
    } finally {
      if (mounted) setState(() => _pickingAudio = false);
    }
  }

  Future<void> _pickCover() async {
    final id = _editing?.id ?? _draft?.id;
    if (id == null) return;
    final file = await DeviceFiles.pickImage();
    if (file == null) return;
    try {
      final path = await ref.read(importerProvider).saveCover(id, file);
      if (mounted) setState(() => _coverPath = path);
    } catch (_) {
      if (mounted) setState(() => _error = 'That image could not be used.');
    }
  }

  /// For another narrator: the new files take over from all the old ones.
  void _replaceAudio() {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Use a different recording',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: Space.s),
                  Text(
                    'The new audio replaces this list and starts at about the same point in the story. Your old files stay on your phone.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(Icons.folder_outlined),
              title: const Text('Choose a folder'),
              onTap: () {
                Navigator.of(sheet).pop();
                _pickAudio(DeviceFiles.pickAudioFolder, replace: true);
              },
            ),
            ListTile(
              leading: const Icon(Icons.audio_file_outlined),
              title: const Text('Choose files'),
              onTap: () {
                Navigator.of(sheet).pop();
                _pickAudio(DeviceFiles.pickAudioFiles, replace: true);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _sortByName() =>
      setState(() => _audio.sort((a, b) => naturalCompare(a.title, b.title)));

  Future<void> _submit() async {
    final title = _title.text.trim();
    if (title.isEmpty) {
      setState(() => _error = 'Give the book a title.');
      return;
    }
    final author = _author.text.trim().isEmpty ? null : _author.text.trim();
    final importer = ref.read(importerProvider);
    final repo = ref.read(bookRepoProvider);
    final handler = ref.read(audioHandlerProvider);
    final nav = Navigator.of(context);

    setState(() {
      _error = null;
      _progress = 'Saving…';
    });
    try {
      final editing = _editing;
      if (editing != null) {
        await repo.updateBookMeta(editing.id, title, author);
        if (_coverPath != null) await repo.setCover(editing.id, _coverPath!);
        await importer.saveAudio(editing.id, _audio);
        if (handler.bookId == editing.id) {
          final fresh = await repo.getBook(editing.id);
          if (fresh != null) await handler.loadBook(fresh, reload: true);
        }
        nav.pop();
      } else {
        final book = await importer.commit(
          _draft!,
          title: title,
          author: author,
          audio: _audio,
          coverPath: _coverPath,
        );
        _draft = null;
        nav.pop(book);
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _progress = null;
          _error = 'Could not save the book. Try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = context.twofold;
    final total = _audio.fold(
      Duration.zero,
      (s, a) => s + (a.duration ?? Duration.zero),
    );

    return PopScope(
      canPop: !_busy,
      onPopInvokedWithResult: (didPop, _) {
        final d = _draft;
        if (didPop && d != null) ref.read(importerProvider).discard(d.id);
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
                  Space.l,
                  0,
                ),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: 'Back',
                      onPressed: _busy
                          ? null
                          : () => Navigator.of(context).maybePop(),
                      icon: const Icon(Icons.arrow_back_rounded),
                    ),
                    const SizedBox(width: Space.xs),
                    Text(
                      _editing == null ? 'Add book' : 'Edit book',
                      style: theme.textTheme.titleLarge,
                    ),
                  ],
                ),
              ),
              Expanded(
                child: CustomScrollView(
                  slivers: [
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(
                        Space.l,
                        Space.l,
                        Space.l,
                        0,
                      ),
                      sliver: SliverToBoxAdapter(child: _bookSection(theme)),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(
                        Space.l,
                        Space.xxl,
                        Space.s,
                        Space.xs,
                      ),
                      sliver: SliverToBoxAdapter(
                        child: Row(
                          children: [
                            Expanded(
                              child: Text.rich(
                                TextSpan(
                                  children: [
                                    TextSpan(
                                      text: 'Audio',
                                      style: theme.textTheme.titleLarge,
                                    ),
                                    if (total > Duration.zero)
                                      TextSpan(
                                        text: '  ${formatTime(total)}',
                                        style: theme.textTheme.labelMedium,
                                      ),
                                  ],
                                ),
                              ),
                            ),
                            if (_audio.length > 1)
                              TextButton(
                                onPressed: _busy ? null : _sortByName,
                                child: const Text('Sort by name'),
                              ),
                          ],
                        ),
                      ),
                    ),
                    SliverReorderableList(
                      itemCount: _audio.length,
                      onReorderItem: (from, to) => setState(() {
                        _audio.insert(to, _audio.removeAt(from));
                      }),
                      proxyDecorator: (child, _, _) => Material(
                        color: theme.colorScheme.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(Space.l),
                        child: child,
                      ),
                      itemBuilder: (context, i) => _AudioRow(
                        key: ObjectKey(_audio[i]),
                        index: i,
                        draft: _audio[i],
                        enabled: !_busy,
                        onRemove: () => setState(() => _audio.removeAt(i)),
                      ),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(
                        Space.l,
                        Space.s,
                        Space.l,
                        Space.xl,
                      ),
                      sliver: SliverToBoxAdapter(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: _PickButton(
                                    icon: Icons.folder_outlined,
                                    label: 'Choose a folder',
                                    onTap: _busy || _pickingAudio
                                        ? null
                                        : () => _pickAudio(
                                            DeviceFiles.pickAudioFolder,
                                          ),
                                  ),
                                ),
                                const SizedBox(width: Space.s),
                                Expanded(
                                  child: _PickButton(
                                    icon: Icons.audio_file_outlined,
                                    label: 'Choose files',
                                    onTap: _busy || _pickingAudio
                                        ? null
                                        : () => _pickAudio(
                                            DeviceFiles.pickAudioFiles,
                                          ),
                                  ),
                                ),
                              ],
                            ),
                            if (_editing != null && _audio.isNotEmpty) ...[
                              const SizedBox(height: Space.s),
                              _PickButton(
                                icon: Icons.swap_horiz_rounded,
                                label: 'Use a different recording',
                                onTap: _busy || _pickingAudio
                                    ? null
                                    : _replaceAudio,
                              ),
                            ],
                            const SizedBox(height: Space.s),
                            Text(
                              _audio.length > 1
                                  ? 'Plays top to bottom. Drag the handle to change the order.'
                                  : _audio.isEmpty
                                  ? 'Optional, and you can add it later. Book in several parts? Choose their folder. Audio stays where it is and takes no extra space.'
                                  : 'Your audio stays where it is and takes no extra space.',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: c.muted,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    Space.l,
                    0,
                    Space.l,
                    Space.s,
                  ),
                  child: Text(
                    _error!,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  Space.l,
                  0,
                  Space.l,
                  Space.l,
                ),
                child: Bubbly(
                  squish: 0.96,
                  child: FilledButton(
                    onPressed: _hasBook && !_busy && !_readingBook
                        ? _submit
                        : null,
                    child: Text(
                      _progress ??
                          (_editing == null
                              ? 'Add to library'
                              : 'Save changes'),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bookSection(ThemeData theme) {
    final draft = _draft;
    final editing = _editing;
    if (draft == null && editing == null) {
      return Material(
        color: theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(Space.cardRadius),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: _readingBook ? null : _pickBook,
          child: SizedBox(
            height: 148,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _readingBook
                    ? const CircularProgressIndicator()
                    : Icon(
                        Icons.menu_book_outlined,
                        size: 36,
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                const SizedBox(height: Space.m),
                Text(
                  _readingBook ? 'Reading the book…' : 'Choose an EPUB or PDF',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
    final preview =
        editing ??
        Book(
          id: draft!.id,
          title: _title.text,
          format: draft.format,
          filePath: draft.path,
          coverPath: draft.coverPath,
          addedAt: 0,
        );
    final shown = _coverPath == null
        ? preview
        : Book(
            id: preview.id,
            title: preview.title,
            format: preview.format,
            filePath: preview.filePath,
            coverPath: _coverPath,
            addedAt: 0,
          );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 96,
          child: Column(
            children: [
              GestureDetector(
                onTap: _busy ? null : _pickCover,
                child: Semantics(
                  button: true,
                  label: 'Change cover',
                  child: BookCover(book: shown, titleSize: 11),
                ),
              ),
              TextButton(
                onPressed: _busy ? null : _pickCover,
                style: TextButton.styleFrom(padding: EdgeInsets.zero),
                child: const Text(
                  'Change cover',
                  maxLines: 1,
                  style: TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: Space.l),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _title,
                enabled: !_busy,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Title'),
              ),
              const SizedBox(height: Space.m),
              TextField(
                controller: _author,
                enabled: !_busy,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Author'),
              ),
              if (editing == null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: _busy || _readingBook ? null : _pickBook,
                    style: TextButton.styleFrom(padding: EdgeInsets.zero),
                    child: Text(
                      _readingBook ? 'Reading…' : 'Choose another file',
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PickButton extends StatelessWidget {
  const _PickButton({required this.icon, required this.label, this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return FilledButton.tonalIcon(
      onPressed: onTap,
      style: ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(Size(0, 52)),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: Space.s),
        ),
        textStyle: WidgetStatePropertyAll(
          Theme.of(context).textTheme.labelLarge,
        ),
      ),
      icon: Icon(icon, size: 20),
      label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
    );
  }
}

class _AudioRow extends StatelessWidget {
  const _AudioRow({
    super.key,
    required this.index,
    required this.draft,
    required this.enabled,
    required this.onRemove,
  });

  final int index;
  final AudioDraft draft;
  final bool enabled;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = context.twofold;
    final length = draft.duration;
    return Container(
      constraints: const BoxConstraints(minHeight: 56),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(Space.l),
      ),
      margin: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, 2),
      padding: const EdgeInsets.only(left: Space.m),
      child: Row(
        children: [
          SizedBox(
            width: 28,
            child: Text('${index + 1}', style: theme.textTheme.labelMedium),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: Space.s),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    draft.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium,
                  ),
                  if (length != null)
                    Text(
                      formatTime(length),
                      style: theme.textTheme.labelMedium,
                    ),
                ],
              ),
            ),
          ),
          IconButton(
            tooltip: 'Remove ${draft.title}',
            onPressed: enabled ? onRemove : null,
            icon: Icon(Icons.close_rounded, size: 20, color: c.muted),
          ),
          ReorderableDragStartListener(
            index: index,
            enabled: enabled,
            child: Semantics(
              label: 'Drag to reorder',
              child: SizedBox(
                width: Space.minTarget,
                height: Space.minTarget,
                child: Icon(Icons.drag_handle_rounded, color: c.muted),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
