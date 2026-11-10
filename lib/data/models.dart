import 'dart:convert';

class Book {
  const Book({
    required this.id,
    required this.title,
    this.author,
    required this.format,
    required this.filePath,
    this.coverPath,
    required this.addedAt,
    this.lastOpened,
  });

  final String id;
  final String title;
  final String? author;

  /// 'epub' | 'pdf'
  final String format;
  final String filePath;
  final String? coverPath;
  final int addedAt;
  final int? lastOpened;

  Map<String, Object?> toMap() => {
        'id': id,
        'title': title,
        'author': author,
        'format': format,
        'file_path': filePath,
        'cover_path': coverPath,
        'added_at': addedAt,
        'last_opened': lastOpened,
      };

  factory Book.fromMap(Map<String, Object?> m) => Book(
        id: m['id'] as String,
        title: m['title'] as String,
        author: m['author'] as String?,
        format: m['format'] as String,
        filePath: m['file_path'] as String,
        coverPath: m['cover_path'] as String?,
        addedAt: m['added_at'] as int,
        lastOpened: m['last_opened'] as int?,
      );
}

class AudioTrack {
  const AudioTrack({
    required this.id,
    required this.bookId,
    required this.filePath,
    required this.position,
    this.durationMs,
    this.title,
  });

  final String id;
  final String bookId;
  final String filePath;

  /// Order in the playlist.
  final int position;
  final int? durationMs;

  /// Display name. Older rows have none and derive it from the stored file.
  final String? title;

  Map<String, Object?> toMap() => {
        'id': id,
        'book_id': bookId,
        'file_path': filePath,
        'position': position,
        'duration_ms': durationMs,
        'title': title,
      };

  factory AudioTrack.fromMap(Map<String, Object?> m) => AudioTrack(
        id: m['id'] as String,
        bookId: m['book_id'] as String,
        filePath: m['file_path'] as String,
        position: m['position'] as int,
        durationMs: m['duration_ms'] as int?,
        title: m['title'] as String?,
      );
}

class Progress {
  const Progress({
    required this.bookId,
    this.readLocation,
    this.readPercent,
    this.trackIndex = 0,
    this.audioMs = 0,
    this.speed = 1.0,
    required this.updatedAt,
  });

  final String bookId;

  /// EPUB CFI, or PDF page number as text.
  final String? readLocation;

  /// 0..1, for the library card.
  final double? readPercent;
  final int trackIndex;

  /// Position inside [trackIndex].
  final int audioMs;
  final double speed;
  final int updatedAt;

  factory Progress.fromMap(Map<String, Object?> m) => Progress(
        bookId: m['book_id'] as String,
        readLocation: m['read_location'] as String?,
        readPercent: (m['read_percent'] as num?)?.toDouble(),
        trackIndex: (m['track_index'] as int?) ?? 0,
        audioMs: (m['audio_ms'] as int?) ?? 0,
        speed: (m['speed'] as num?)?.toDouble() ?? 1.0,
        updatedAt: m['updated_at'] as int,
      );
}

/// A spot the user saved: a place in the book and a minute in the audio.
class PlaceMark {
  const PlaceMark({
    required this.id,
    required this.bookId,
    required this.location,
    required this.percent,
    required this.pageLabel,
    this.audioMs,
    required this.createdAt,
    this.synced = false,
    this.note,
  });

  final String id;
  final String bookId;
  final String location;
  final double percent;
  final String pageLabel;

  /// Absolute position in the audio.
  final int? audioMs;
  final int createdAt;

  /// The user confirmed that page and audio match here.
  final bool synced;

  /// The user's name for this place, if they gave one.
  final String? note;

  Map<String, Object?> toMap() => {
        'id': id,
        'book_id': bookId,
        'location': location,
        'percent': percent,
        'page_label': pageLabel,
        'audio_ms': audioMs,
        'created_at': createdAt,
        'synced': synced ? 1 : 0,
        'note': note,
      };

  factory PlaceMark.fromMap(Map<String, Object?> m) => PlaceMark(
        id: m['id'] as String,
        bookId: m['book_id'] as String,
        location: m['location'] as String,
        percent: (m['percent'] as num).toDouble(),
        pageLabel: m['page_label'] as String,
        audioMs: m['audio_ms'] as int?,
        createdAt: m['created_at'] as int,
        synced: m['synced'] == 1,
        note: m['note'] as String?,
      );
}

/// Where a book came from and what Open Library says about it.
class BookDetails {
  const BookDetails({
    required this.bookId,
    this.source,
    this.sourceId,
    this.sourceUrl,
    this.summary,
    this.description,
    this.subjects = const [],
    this.rating,
    this.ratingCount = 0,
    this.wantToRead = 0,
    this.firstYear,
    this.pages,
    this.olWork,
    required this.updatedAt,
  });

  final String bookId;

  /// The Find source's name ("Project Gutenberg"), when it came from Find.
  final String? source;
  final String? sourceId;
  final String? sourceUrl;

  /// The source's own short description.
  final String? summary;

  /// Open Library's description.
  final String? description;
  final List<String> subjects;
  final double? rating;
  final int ratingCount;
  final int wantToRead;
  final int? firstYear;
  final int? pages;

  /// Open Library's work, as "/works/OL123W".
  final String? olWork;
  final int updatedAt;

  /// True once Open Library has been asked (it may have known nothing).
  bool get lookedUp => olWork != null || rating != null || description != null;

  Map<String, Object?> toMap() => {
    'book_id': bookId,
    'source': source,
    'source_id': sourceId,
    'source_url': sourceUrl,
    'summary': summary,
    'description': description,
    'subjects': jsonEncode(subjects),
    'rating': rating,
    'rating_count': ratingCount,
    'want_to_read': wantToRead,
    'first_year': firstYear,
    'pages': pages,
    'ol_work': olWork,
    'updated_at': updatedAt,
  };

  factory BookDetails.fromMap(Map<String, Object?> m) {
    var subjects = const <String>[];
    try {
      subjects = List<String>.from(jsonDecode(m['subjects'] as String? ?? '[]') as List);
    } catch (_) {}
    return BookDetails(
      bookId: m['book_id'] as String,
      source: m['source'] as String?,
      sourceId: m['source_id'] as String?,
      sourceUrl: m['source_url'] as String?,
      summary: m['summary'] as String?,
      description: m['description'] as String?,
      subjects: subjects,
      rating: (m['rating'] as num?)?.toDouble(),
      ratingCount: m['rating_count'] as int? ?? 0,
      wantToRead: m['want_to_read'] as int? ?? 0,
      firstYear: m['first_year'] as int?,
      pages: m['pages'] as int?,
      olWork: m['ol_work'] as String?,
      updatedAt: m['updated_at'] as int,
    );
  }
}
