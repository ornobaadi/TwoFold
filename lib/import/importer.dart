import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:uuid/uuid.dart';
import 'package:xml/xml.dart';

import '../audio/audio_handler.dart';
import '../audio/timeline.dart';
import '../data/book_repo.dart';
import '../data/models.dart';
import 'device_files.dart';
import 'names.dart';

const bookExtensions = {'.epub', '.pdf'};

const unreadableMessage = 'This file could not be read.';

class ImportError implements Exception {
  const ImportError(this.message);
  final String message;
  @override
  String toString() => message;
}

/// A book file copied into app storage but not yet in the library.
class DraftBook {
  const DraftBook({
    required this.id,
    required this.format,
    required this.path,
    required this.title,
    this.author,
    this.coverPath,
  });

  final String id;
  final String format;
  final String path;
  final String title;
  final String? author;
  final String? coverPath;
}

/// One row of the audio list: a newly picked file or an existing track.
class AudioDraft {
  AudioDraft.picked(PickedFile this.picked)
      : existing = null,
        name = picked.name;
  AudioDraft.existing(AudioTrack this.existing)
      : picked = null,
        name = existing.title ?? p.basename(existing.filePath),
        duration = existing.durationMs == null
            ? null
            : Duration(milliseconds: existing.durationMs!);

  final PickedFile? picked;
  final AudioTrack? existing;
  final String name;
  Duration? duration;

  String get source => picked?.uri ?? existing!.filePath;

  String get title => existing != null && existing!.title == null
      ? trackTitle(existing!.filePath)
      : prettifyName(name);
}

/// Copies book files into `appDocs/books/<id>/` and reads their metadata.
/// Audio is not copied: it plays from where the user keeps it.
class Importer {
  Importer(this._repo);

  final BookRepo _repo;
  static const _uuid = Uuid();

  Future<Directory> _bookDir(String id) async {
    final docs = await getApplicationDocumentsDirectory();
    return Directory(p.join(docs.path, 'books', id)).create(recursive: true);
  }

  /// Copies a picked EPUB/PDF and reads its title, author and cover.
  /// Throws [ImportError] if the file can't be used.
  Future<DraftBook> importBookFile(PickedFile file) async {
    final ext = p.extension(file.name).toLowerCase();
    if (!bookExtensions.contains(ext)) {
      throw const ImportError('Choose an EPUB or PDF file.');
    }
    final id = _uuid.v4();
    final dir = await _bookDir(id);
    final path = p.join(dir.path, 'book$ext');
    try {
      await DeviceFiles.copy(file.uri, path);
      return ext == '.epub'
          ? await _inspectEpub(id, path, file.name, dir.path)
          : await _inspectPdf(id, path, file.name, dir.path);
    } catch (e) {
      await discard(id);
      if (e is ImportError) rethrow;
      throw const ImportError(unreadableMessage);
    }
  }

  Future<DraftBook> _inspectEpub(
      String id, String path, String fileName, String dir) async {
    final coverPath = p.join(dir, 'cover.png');
    final info = await Isolate.run(() => _readEpub(path, coverPath));
    if (info.protected) throw const ImportError(unreadableMessage);
    return DraftBook(
      id: id,
      format: 'epub',
      path: path,
      title: info.title ?? prettifyName(fileName),
      author: info.author,
      coverPath: info.hasCover ? coverPath : null,
    );
  }

  Future<DraftBook> _inspectPdf(
      String id, String path, String fileName, String dir) async {
    final doc = await PdfDocument.openFile(path);
    try {
      if (doc.pages.isEmpty) throw const ImportError(unreadableMessage);
      final coverPath = p.join(dir, 'cover.png');
      final ok = await _renderCover(doc.pages.first, coverPath);
      return DraftBook(
        id: id,
        format: 'pdf',
        path: path,
        title: prettifyName(fileName),
        coverPath: ok ? coverPath : null,
      );
    } finally {
      await doc.dispose();
    }
  }

  Future<bool> _renderCover(PdfPage page, String out) async {
    const width = 480.0;
    final height = width * page.height / page.width;
    final rendered = await page.render(
      width: width.round(),
      height: height.round(),
      fullWidth: width,
      fullHeight: height,
      backgroundColor: 0xFFFFFFFF,
    );
    if (rendered == null) return false;
    try {
      final image = await rendered.createImage();
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (data == null) return false;
      await File(out).writeAsBytes(data.buffer.asUint8List());
      return true;
    } finally {
      rendered.dispose();
    }
  }

  /// Copies a chosen image in as the book's cover. Each gets a new name, so
  /// images already on screen don't stay cached.
  Future<String> saveCover(String bookId, PickedFile file) async {
    final dir = await _bookDir(bookId);
    final ext = p.extension(file.name).toLowerCase();
    final path = p.join(dir.path, 'cover_${_uuid.v4()}$ext');
    await DeviceFiles.copy(file.uri, path);
    return path;
  }

  /// Deletes a book's stored files.
  Future<void> discard(String id) async {
    final dir = await _bookDir(id);
    if (dir.existsSync()) await dir.delete(recursive: true);
  }

  /// Adds a draft and its audio to the library.
  Future<Book> commit(
    DraftBook draft, {
    required String title,
    required String? author,
    required List<AudioDraft> audio,
    String? coverPath,
  }) async {
    final book = Book(
      id: draft.id,
      title: title,
      author: author,
      format: draft.format,
      filePath: draft.path,
      coverPath: coverPath ?? draft.coverPath,
      addedAt: DateTime.now().millisecondsSinceEpoch,
    );
    await _repo.insertBook(book);
    await saveAudio(book.id, audio);
    return book;
  }

  /// Makes [audio], in this order, the book's playlist, and keeps the
  /// listening position on the same file.
  Future<void> saveAudio(String bookId, List<AudioDraft> audio) async {
    final before = await _repo.tracksFor(bookId);
    final saved = await _repo.getProgress(bookId);
    final index = saved?.trackIndex ?? 0;
    final currentId = index < before.length ? before[index].id : null;

    // A different recording: same place in the story, not the same minute.
    final isNewRecording = before.isNotEmpty &&
        audio.isNotEmpty &&
        audio.every((d) => d.existing == null);
    var storyFraction = 0.0;
    if (isNewRecording && saved != null) {
      final old = Timeline([
        for (final t in before) Duration(milliseconds: t.durationMs ?? 0),
      ]);
      final at = old.toAbsolute(index, Duration(milliseconds: saved.audioMs));
      if (old.total > Duration.zero) {
        storyFraction = at.inMilliseconds / old.total.inMilliseconds;
      }
    }

    final tracks = <AudioTrack>[];
    for (var i = 0; i < audio.length; i++) {
      final draft = audio[i];
      draft.duration ??= await probeDuration(draft.source);
      final old = draft.existing;
      tracks.add(AudioTrack(
        id: old?.id ?? _uuid.v4(),
        bookId: bookId,
        filePath: draft.source,
        position: i,
        durationMs: draft.duration?.inMilliseconds ?? old?.durationMs,
        title: old == null ? draft.name : old.title,
      ));
    }
    await _repo.setTracks(bookId, tracks);
    if (isNewRecording) {
      final next = Timeline([
        for (final t in tracks) Duration(milliseconds: t.durationMs ?? 0),
      ]);
      final spot = next.fromAbsolute(next.total * storyFraction);
      await _repo.saveAudio(bookId,
          trackIndex: spot.index,
          audioMs: spot.position.inMilliseconds,
          speed: saved?.speed ?? 1.0);
    } else {
      await _repo.remapAudioPosition(bookId,
          oldTrackId: currentId, tracks: tracks);
    }

    // Copies made by older versions are ours to delete; originals never are.
    final kept = tracks.map((t) => t.filePath).toSet();
    for (final t in before) {
      if (!kept.contains(t.filePath) && !isContentUri(t.filePath)) {
        final f = File(t.filePath);
        if (f.existsSync()) await f.delete();
      }
    }
  }

  /// Removes a book from the library and deletes its copied files.
  Future<void> removeBook(String id) async {
    await _repo.deleteBook(id);
    await discard(id);
  }
}

typedef _EpubInfo = ({
  String? title,
  String? author,
  bool hasCover,
  bool protected
});

/// Title, author and cover file name from an EPUB's OPF package document.
({String? title, String? author, String? coverHref}) parseOpf(String opf) {
  final doc = XmlDocument.parse(opf);
  String? text(String name) {
    final found = doc.descendants
        .whereType<XmlElement>()
        .where((e) => e.name.local == name);
    final value = found.isEmpty ? '' : found.first.innerText.trim();
    return value.isEmpty ? null : value;
  }

  final items = doc.descendants
      .whereType<XmlElement>()
      .where((e) => e.name.local == 'item')
      .toList();
  String? href;
  // EPUB 3 marks the cover in the manifest; EPUB 2 points at it from a <meta>.
  for (final i in items) {
    if ((i.getAttribute('properties') ?? '').split(' ').contains('cover-image')) {
      href = i.getAttribute('href');
    }
  }
  if (href == null) {
    final metas = doc.descendants.whereType<XmlElement>().where((e) =>
        e.name.local == 'meta' && e.getAttribute('name') == 'cover');
    final id = metas.isEmpty ? null : metas.first.getAttribute('content');
    for (final i in items) {
      if (i.getAttribute('id') == id) href = i.getAttribute('href');
    }
  }
  return (title: text('title'), author: text('creator'), coverHref: href);
}

Future<_EpubInfo> _readEpub(String path, String coverPath) async {
  final Uint8List bytes = await File(path).readAsBytes();
  final Archive archive;
  try {
    archive = ZipDecoder().decodeBytes(bytes);
  } catch (_) {
    return (title: null, author: null, hasCover: false, protected: true);
  }
  // Metadata is a bonus: the viewer may open books this parser dislikes.
  try {
    final container = XmlDocument.parse(
        utf8.decode(archive.findFile('META-INF/container.xml')!.content));
    final opfPath = container.descendants
        .whereType<XmlElement>()
        .firstWhere((e) => e.name.local == 'rootfile')
        .getAttribute('full-path')!;
    final meta = parseOpf(utf8.decode(archive.findFile(opfPath)!.content));
    var hasCover = false;
    final href = meta.coverHref;
    if (href != null) {
      final inZip = p.posix.normalize(
          p.posix.join(p.posix.dirname(opfPath), Uri.decodeFull(href)));
      final cover = archive.findFile(inZip);
      if (cover != null) {
        await File(coverPath).writeAsBytes(cover.content);
        hasCover = true;
      }
    }
    return (
      title: meta.title,
      author: meta.author,
      hasCover: hasCover,
      protected: false,
    );
  } catch (_) {
    return (title: null, author: null, hasCover: false, protected: false);
  }
}
