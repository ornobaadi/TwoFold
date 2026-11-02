import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

const _dbVersion = 3;

/// Opens the app database. Pass [path] to open elsewhere (tests use an in-memory db).
Future<Database> openTwoFoldDb({String? path, DatabaseFactory? factory}) async {
  final f = factory ?? databaseFactory;
  final dbPath = path ?? p.join(await f.getDatabasesPath(), 'twofold.db');
  return f.openDatabase(
    dbPath,
    options: OpenDatabaseOptions(
      version: _dbVersion,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: _create,
      onUpgrade: (db, from, to) async {
        if (from < 2) {
          await db.execute('ALTER TABLE audio_tracks ADD COLUMN title TEXT');
        }
        if (from < 3) await _createMarks(db);
      },
    ),
  );
}

Future<void> _createMarks(Database db) => db.execute('''
    CREATE TABLE marks (
      id         TEXT PRIMARY KEY,
      book_id    TEXT NOT NULL REFERENCES books(id) ON DELETE CASCADE,
      location   TEXT NOT NULL,
      percent    REAL NOT NULL,
      page_label TEXT NOT NULL,
      audio_ms   INTEGER,
      created_at INTEGER NOT NULL,
      synced     INTEGER NOT NULL DEFAULT 0
    )''');

Future<void> _create(Database db, int version) async {
  await _createMarks(db);
  await db.execute('''
    CREATE TABLE books (
      id          TEXT PRIMARY KEY,
      title       TEXT NOT NULL,
      author      TEXT,
      format      TEXT NOT NULL,
      file_path   TEXT NOT NULL,
      cover_path  TEXT,
      added_at    INTEGER NOT NULL,
      last_opened INTEGER
    )''');
  await db.execute('''
    CREATE TABLE audio_tracks (
      id          TEXT PRIMARY KEY,
      book_id     TEXT NOT NULL REFERENCES books(id) ON DELETE CASCADE,
      file_path   TEXT NOT NULL,
      position    INTEGER NOT NULL,
      duration_ms INTEGER,
      title       TEXT
    )''');
  await db.execute('''
    CREATE TABLE progress (
      book_id       TEXT PRIMARY KEY REFERENCES books(id) ON DELETE CASCADE,
      read_location TEXT,
      read_percent  REAL,
      track_index   INTEGER DEFAULT 0,
      audio_ms      INTEGER DEFAULT 0,
      speed         REAL DEFAULT 1.0,
      updated_at    INTEGER NOT NULL
    )''');
  await db.execute('''
    CREATE TABLE settings (
      key   TEXT PRIMARY KEY,
      value TEXT NOT NULL
    )''');
}
