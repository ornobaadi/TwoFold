import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../data/book_repo.dart';
import '../data/models.dart';
import '../find/web.dart' show userAgent;

/// One download as Android's DownloadManager reports it.
class DownloadState {
  const DownloadState(this.id, this.state, {this.bytes = 0, this.total = 0, this.file});

  final int id;

  /// pending, running, paused, done, failed or gone.
  final String state;
  final int bytes;
  final int total;
  final String? file;

  bool get finished => state == 'done';
  bool get broken => state == 'failed' || state == 'gone';
}

/// The native side. Tests replace it.
abstract class DownloadChannel {
  Future<int> enqueue({
    required String url,
    required String path,
    required String title,
    required bool wifiOnly,
  });
  Future<List<DownloadState>> status(List<int> ids);
  Future<void> remove(List<int> ids);

  /// Where saved audiobooks live (app-private storage).
  Future<String> folder();
}

class AndroidDownloads implements DownloadChannel {
  static const _channel = MethodChannel('twofold/downloads');

  @override
  Future<int> enqueue({
    required String url,
    required String path,
    required String title,
    required bool wifiOnly,
  }) async =>
      (await _channel.invokeMethod<num>('enqueue', {
        'url': url,
        'path': path,
        'title': title,
        'userAgent': userAgent,
        'wifiOnly': wifiOnly,
      }))!.toInt();

  @override
  Future<List<DownloadState>> status(List<int> ids) async {
    final list = await _channel.invokeListMethod<Map>('status', {'ids': ids});
    return [
      for (final m in list ?? const <Map>[])
        DownloadState(
          (m['id'] as num).toInt(),
          m['state'] as String,
          bytes: (m['bytes'] as num?)?.toInt() ?? 0,
          total: (m['total'] as num?)?.toInt() ?? 0,
          file: m['file'] as String?,
        ),
    ];
  }

  @override
  Future<void> remove(List<int> ids) =>
      _channel.invokeMethod('remove', {'ids': ids});

  @override
  Future<String> folder() async =>
      (await _channel.invokeMethod<String>('folder'))!;
}

/// How much of a book's free recording is on the phone.
class SaveProgress {
  const SaveProgress({
    required this.saved,
    required this.parts,
    required this.bytes,
    required this.totalBytes,
    required this.saving,
  });

  final int saved;
  final int parts;
  final int bytes;
  final int totalBytes;

  /// Downloads are queued or running.
  final bool saving;

  bool get complete => parts > 0 && saved == parts;
  static const none = SaveProgress(saved: 0, parts: 0, bytes: 0, totalBytes: 0, saving: false);
}

/// True for a file that starts like an MP3 (ID3 tag or an MPEG frame).
bool looksLikeMp3(List<int> head) =>
    head.length >= 3 &&
    ((head[0] == 0x49 && head[1] == 0x44 && head[2] == 0x33) ||
        (head[0] == 0xFF && (head[1] & 0xE0) == 0xE0));

/// Saves free recordings for offline, a few parts at a time and in order, so
/// the first chapters arrive first. Android keeps downloading with the app
/// closed; [refresh] catches up whenever the app is open.
class AudiobookDownloads extends ChangeNotifier {
  AudiobookDownloads(this._repo, this._channel, {this.atOnce = 3});

  final BookRepo _repo;
  final DownloadChannel _channel;
  final int atOnce;
  bool wifiOnly = true;

  final _retried = <String>{};
  final _live = <int, DownloadState>{};
  bool _busy = false;

  static String _wantKey(String bookId) => 'save_offline_$bookId';

  Future<bool> wantsSaving(String bookId) async =>
      await _repo.getSetting(_wantKey(bookId)) == 'true';

  /// Starts saving every part of [bookId] that isn't on the phone yet.
  Future<void> saveAll(String bookId) async {
    await _repo.setSetting(_wantKey(bookId), 'true');
    await refresh();
  }

  /// Stops saving; parts already saved stay.
  Future<void> pause(String bookId) async {
    await _repo.deleteSetting(_wantKey(bookId));
    final pending = [
      for (final t in await _repo.tracksFor(bookId))
        if (t.downloadId != null) t,
    ];
    if (pending.isNotEmpty) {
      await _channel.remove([for (final t in pending) t.downloadId!]);
    }
    for (final t in pending) {
      await _repo.setDownloadId(t.id, null);
    }
    notifyListeners();
  }

  /// Deletes the saved parts; the book streams again.
  Future<void> removeSaved(String bookId) async {
    await pause(bookId);
    for (final t in await _repo.tracksFor(bookId)) {
      if (!t.downloadable || t.isRemote) continue;
      final f = File(t.filePath);
      if (f.existsSync()) await f.delete();
      await _repo.markTrackRemote(t.id);
    }
    notifyListeners();
  }

  /// Forgets downloads of a book that is being removed.
  Future<void> forget(String bookId) async {
    await pause(bookId);
    final dir = Directory(p.join(await _channel.folder(), bookId));
    if (dir.existsSync()) await dir.delete(recursive: true);
  }

  /// Checks running downloads, keeps finished parts, and queues the next.
  Future<void> refresh() async {
    if (_busy) return;
    _busy = true;
    try {
      final pending = await _repo.pendingDownloads();
      final states = pending.isEmpty
          ? const <DownloadState>[]
          : await _channel.status([for (final t in pending) t.downloadId!]);
      final byId = {for (final s in states) s.id: s};
      _live.clear();
      final books = <String>{};
      for (final t in pending) {
        books.add(t.bookId);
        final s = byId[t.downloadId];
        if (s == null) continue;
        _live[s.id] = s;
        final failed = s.broken || (s.finished && !await _keep(t, s));
        if (failed) {
          await _repo.setDownloadId(t.id, null);
          // Tried once more; after that it waits for the next Save.
          if (!_retried.add(t.id)) await _repo.deleteSetting(_wantKey(t.bookId));
        }
      }
      for (final id in await _booksWanting()) {
        books.add(id);
        await _topUp(id);
      }
      notifyListeners();
    } finally {
      _busy = false;
    }
  }

  Future<List<String>> _booksWanting() async {
    final out = <String>[];
    for (final t in await _repo.allBooks()) {
      if (await wantsSaving(t.id)) out.add(t.id);
    }
    return out;
  }

  /// Keeps a finished part if it is real audio. False when it was not.
  Future<bool> _keep(AudioTrack t, DownloadState s) async {
    final path = s.file;
    final file = path == null ? null : File(path);
    if (file == null || !file.existsSync()) return false;
    final head = file.lengthSync() < 100 * 1024
        ? const <int>[]
        : await file.openRead(0, 4).first;
    if (!looksLikeMp3(head)) {
      await file.delete();
      return false;
    }
    await _repo.markTrackSaved(t.id, file.path);
    return true;
  }

  Future<void> _topUp(String bookId) async {
    final tracks = await _repo.tracksFor(bookId);
    var running = tracks.where((t) => t.downloadId != null).length;
    final book = await _repo.getBook(bookId);
    for (final t in tracks) {
      if (running >= atOnce) break;
      if (!t.downloadable || !t.isRemote || t.downloadId != null) continue;
      final id = await _channel.enqueue(
        url: t.remoteUrl!,
        path: p.join(bookId, '${(t.position + 1).toString().padLeft(3, '0')}.mp3'),
        title: '${book?.title ?? 'Audiobook'}: ${t.title ?? 'Part ${t.position + 1}'}',
        wifiOnly: wifiOnly,
      );
      await _repo.setDownloadId(t.id, id);
      running++;
    }
    if (running == 0 && tracks.every((t) => !t.isRemote || !t.downloadable)) {
      await _repo.deleteSetting(_wantKey(bookId));
    }
  }

  /// Saved and total parts and bytes of [bookId], for the status line.
  Future<SaveProgress> progress(String bookId) async {
    final tracks = [
      for (final t in await _repo.tracksFor(bookId))
        if (t.downloadable) t,
    ];
    if (tracks.isEmpty) return SaveProgress.none;
    var saved = 0;
    var bytes = 0;
    var total = 0;
    var saving = false;
    for (final t in tracks) {
      // 64 kbps: 8 KB a second.
      final size = ((t.durationMs ?? 0) / 1000 * 8000).round();
      total += size;
      if (!t.isRemote) {
        saved++;
        bytes += File(t.filePath).existsSync() ? File(t.filePath).lengthSync() : size;
      } else if (t.downloadId != null) {
        saving = true;
        bytes += _live[t.downloadId]?.bytes ?? 0;
      }
    }
    return SaveProgress(
      saved: saved,
      parts: tracks.length,
      bytes: bytes,
      totalBytes: total,
      saving: saving || await wantsSaving(bookId),
    );
  }

  /// Space used by all saved audiobooks.
  Future<int> savedBytes() async {
    try {
      final dir = Directory(await _channel.folder());
      if (!dir.existsSync()) return 0;
      var sum = 0;
      await for (final f in dir.list(recursive: true)) {
        if (f is File) sum += await f.length();
      }
      return sum;
    } catch (_) {
      return 0;
    }
  }
}

/// "375 MB", "1.2 GB".
String formatSize(int bytes) {
  if (bytes >= 1000 * 1000 * 1000) {
    return '${(bytes / 1e9).toStringAsFixed(1)} GB';
  }
  return '${(bytes / 1e6).round()} MB';
}
