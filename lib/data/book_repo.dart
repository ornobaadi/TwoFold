import 'package:sqflite/sqflite.dart';

import 'models.dart';

/// All database access. UI and audio code go through this class.
///
/// The audio fields and the reading fields of `progress` are written by
/// separate methods that touch disjoint columns, so a page turn can never
/// overwrite the audio position and the other way round.
class BookRepo {
  BookRepo(this._db);

  final Database _db;

  int Function() now = () => DateTime.now().millisecondsSinceEpoch;

  // --- books ---

  Future<void> insertBook(Book book) => _db.insert(
        'books',
        book.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

  Future<Book?> getBook(String id) async {
    final rows = await _db.query('books', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : Book.fromMap(rows.first);
  }

  Future<List<Book>> allBooks() async {
    final rows = await _db.query('books', orderBy: 'last_opened DESC, added_at DESC');
    return rows.map(Book.fromMap).toList();
  }

  Future<void> updateBookMeta(String id, String title, String? author) =>
      _db.update(
        'books',
        {'title': title, 'author': author},
        where: 'id = ?',
        whereArgs: [id],
      );

  Future<void> setCover(String id, String path) => _db.update(
        'books',
        {'cover_path': path},
        where: 'id = ?',
        whereArgs: [id],
      );

  Future<void> touchOpened(String id) => _db.update(
        'books',
        {'last_opened': now()},
        where: 'id = ?',
        whereArgs: [id],
      );

  Future<void> deleteBook(String id) =>
      _db.delete('books', where: 'id = ?', whereArgs: [id]);

  // --- audio tracks ---

  Future<List<AudioTrack>> tracksFor(String bookId) async {
    final rows = await _db.query(
      'audio_tracks',
      where: 'book_id = ?',
      whereArgs: [bookId],
      orderBy: 'position ASC',
    );
    return rows.map(AudioTrack.fromMap).toList();
  }

  /// Replaces the whole playlist of [bookId].
  Future<void> setTracks(String bookId, List<AudioTrack> tracks) async {
    await _db.transaction((txn) async {
      await txn.delete('audio_tracks', where: 'book_id = ?', whereArgs: [bookId]);
      for (final t in tracks) {
        await txn.insert('audio_tracks', t.toMap());
      }
    });
  }

  Future<void> setTrackDuration(String trackId, int durationMs) => _db.update(
        'audio_tracks',
        {'duration_ms': durationMs},
        where: 'id = ?',
        whereArgs: [trackId],
      );

  // --- progress ---

  Future<Progress?> getProgress(String bookId) async {
    final rows =
        await _db.query('progress', where: 'book_id = ?', whereArgs: [bookId]);
    return rows.isEmpty ? null : Progress.fromMap(rows.first);
  }

  /// Saves the audio position and speed. Leaves the reading fields alone.
  Future<void> saveAudio(
    String bookId, {
    required int trackIndex,
    required int audioMs,
    required double speed,
  }) async {
    final t = now();
    await _db.transaction((txn) async {
      await txn.insert(
        'progress',
        {'book_id': bookId, 'updated_at': t},
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
      await txn.update(
        'progress',
        {
          'track_index': trackIndex,
          'audio_ms': audioMs,
          'speed': speed,
          'updated_at': t,
        },
        where: 'book_id = ?',
        whereArgs: [bookId],
      );
    });
  }

  /// Saves the reading position. Leaves the audio fields alone.
  Future<void> saveReading(
    String bookId, {
    required String location,
    double? percent,
  }) async {
    final t = now();
    await _db.transaction((txn) async {
      await txn.insert(
        'progress',
        {'book_id': bookId, 'updated_at': t},
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
      await txn.update(
        'progress',
        {'read_location': location, 'read_percent': percent, 'updated_at': t},
        where: 'book_id = ?',
        whereArgs: [bookId],
      );
    });
  }

  /// Keeps the audio position on the same file after the playlist changed.
  /// If that file was removed, audio restarts at the beginning.
  Future<void> remapAudioPosition(
    String bookId, {
    required String? oldTrackId,
    required List<AudioTrack> tracks,
  }) async {
    final p = await getProgress(bookId);
    if (p == null) return;
    final i = tracks.indexWhere((t) => t.id == oldTrackId);
    await saveAudio(
      bookId,
      trackIndex: i < 0 ? 0 : i,
      audioMs: i < 0 ? 0 : p.audioMs,
      speed: p.speed,
    );
  }

  // --- saved places ---

  Future<List<PlaceMark>> marksFor(String bookId) async {
    final rows = await _db.query('marks',
        where: 'book_id = ?', whereArgs: [bookId], orderBy: 'created_at DESC');
    return rows.map(PlaceMark.fromMap).toList();
  }

  Future<void> addMark(PlaceMark mark) => _db.insert('marks', mark.toMap());

  Future<void> deleteMark(String id) =>
      _db.delete('marks', where: 'id = ?', whereArgs: [id]);

  // --- settings ---

  Future<void> deleteSetting(String key) =>
      _db.delete('settings', where: 'key = ?', whereArgs: [key]);

  Future<String?> getSetting(String key) async {
    final rows = await _db.query('settings', where: 'key = ?', whereArgs: [key]);
    return rows.isEmpty ? null : rows.first['value'] as String;
  }

  Future<void> setSetting(String key, String value) => _db.insert(
        'settings',
        {'key': key, 'value': value},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
}
