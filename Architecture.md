# Architecture

Keep it small. Few packages, one database, and the network only for Find free books.

## Stack

| Need | Package | Why |
|------|---------|-----|
| Audio playback | `just_audio` | Reliable, plays gapless playlists, speed control, M4B support |
| Background + lock screen | `audio_service` | Media notification, lock screen controls, headset buttons |
| Calls / headphone unplug | `audio_session` | Handles interruptions correctly |
| EPUB (paginated) | `flutter_epub_viewer` | Built on epub.js. Real swipe pagination, reflow, themes, CFI locations |
| PDF | `pdfrx` | Fast (PDFium), page-by-page rendering, zoom |
| File import | `file_picker` | System file picker |
| Database | `sqflite` | One small table set; nothing fancier needed |
| State | `flutter_riverpod` | Simple, testable, no boilerplate |
| Paths | `path_provider` | App storage folder |
| EPUB metadata/cover | `epubx` | Read title, author, cover on import |

Fonts are bundled as assets (see design.md); no Google Fonts network calls.

## Folder structure

```
lib/
  main.dart
  app/
    theme.dart            colours, type, spacing
    router.dart           3 routes: library, reader, listen
  data/
    db.dart               sqflite open + migrations
    book_repo.dart        CRUD for books, audio tracks, progress
    models.dart           Book, AudioTrack, Progress
  audio/
    audio_handler.dart    audio_service handler wrapping just_audio
    player_controller.dart  riverpod notifier: play, pause, skip, speed
  import/
    importer.dart         copy files, read metadata, make cover
  features/
    library/              library_screen.dart, book_card.dart
    reader/               reader_screen.dart, epub_view.dart, pdf_view.dart
    player/               player_bar.dart, mini_play_button.dart
    listen/               listen_screen.dart
    settings/             settings_sheet.dart
```

## Data model

```sql
CREATE TABLE books (
  id            TEXT PRIMARY KEY,      -- uuid
  title         TEXT NOT NULL,
  author        TEXT,
  format        TEXT NOT NULL,         -- 'epub' | 'pdf'
  file_path     TEXT NOT NULL,         -- inside app storage
  cover_path    TEXT,
  added_at      INTEGER NOT NULL,
  last_opened   INTEGER
);

CREATE TABLE audio_tracks (
  id            TEXT PRIMARY KEY,
  book_id       TEXT NOT NULL REFERENCES books(id) ON DELETE CASCADE,
  file_path     TEXT NOT NULL,
  position      INTEGER NOT NULL,      -- order in the playlist
  duration_ms   INTEGER
);

CREATE TABLE progress (
  book_id       TEXT PRIMARY KEY REFERENCES books(id) ON DELETE CASCADE,
  read_location TEXT,                  -- EPUB CFI, or PDF page number as text
  read_percent  REAL,                  -- 0..1, for the library card
  track_index   INTEGER DEFAULT 0,
  audio_ms      INTEGER DEFAULT 0,     -- position inside that track
  speed         REAL DEFAULT 1.0,
  updated_at    INTEGER NOT NULL
);
```

Saved places live in `marks` (DB v3; v4 adds `note`, the user's name for a place): book, location, percent, page label, audio position, time, and `synced` (left from the removed page/audio sync; such rows are hidden).

`book_details` (DB v5) keeps, per book, where it came from (source name, id, page) and Open Library's rating, counts, first year, pages, description and subjects (JSON). Written after a Find download and when the user taps Look up details; removed with the book.

Settings (skip length, theme, font size, recent searches) live in one `settings` key/value table.

## Audio flow

```
UI buttons / lock screen / headset
            │
            ▼
     AudioHandler (audio_service)  ── runs as a foreground service
            │
            ▼
        just_audio player  ── ConcatenatingAudioSource of the book's tracks
            │
            ▼
   position stream ──► ProgressSaver ──► sqflite
```

- **Skip:** `seek(position ± skip)`, clamped, and crosses track boundaries using the absolute timeline position.
- Lock screen "next/previous" are mapped to skip forward/back, because that is what people expect from audiobooks.
- One `AudioHandler` for the whole app. Opening another book swaps the playlist after saving the current progress.

## Saving progress (the critical part)

Save the same row from four triggers:

1. Every 5 s while playing (throttled position stream).
2. On pause / stop.
3. On every page turn (reader location callback).
4. On `AppLifecycleState.paused` / `detached`.

Writes are a single `INSERT OR REPLACE`, so they're cheap. Because of trigger 1, a force-kill loses 5 seconds at most. On open: load the row → `setAudioSource(..., initialIndex, initialPosition)` paused → open the reader at `read_location`.

## Gestures

- The reader owns horizontal swipes.
- Taps in the centre 40% of the screen toggle the controls. Taps on the outer edges turn pages (optional, on by default for EPUB).
- The player bar is a separate widget above the reader in a `Stack`, with its own hit area. Touches on it never reach the reader.

## Import

1. Pick a file → copy it into `appDocs/books/<id>/`.
2. EPUB: read metadata + cover with `epubx`. PDF: title from metadata or the file name, and the cover is page 1 rendered small.
3. If parsing fails or the file is encrypted → show "This file is DRM-protected or damaged".

## Permissions (Android)

- `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_MEDIA_PLAYBACK`, `WAKE_LOCK`, `POST_NOTIFICATIONS`.
- No storage permission: the system file picker gives temporary access and the files get copied.
- `INTERNET`, used only by Find free books (`lib/find/`): search, browse and download from Gutenberg, the Internet Archive, Wikisource and user-added OPDS catalogs (`find/opds_source.dart`), plus book details and ratings from Open Library (`find/book_info.dart`), https only, to a fixed list of hosts. Nothing else in the app opens a connection.
