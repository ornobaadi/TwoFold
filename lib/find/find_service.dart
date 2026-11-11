import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import 'archive_source.dart';
import 'book_info.dart';
import 'book_source.dart';
import 'cover_source.dart';
import 'librivox.dart';
import 'librivox_source.dart';
import 'gutenberg_source.dart';
import 'opds_source.dart';
import 'web.dart';
import 'wikisource_source.dart';

/// The sites TwoFold can search, and getting a book from one of them.
class FindService {
  FindService({
    Web? web,
    List<BookSource>? sources,
    Future<Directory> Function()? tempDir,
    BookInfoService? info,
    CoverService? covers,
    LibrivoxService? librivox,
    this.maxBytes = 150 << 20,
  }) : web = web ?? Web(),
       _tempDir = tempDir ?? _systemTemp {
    this.info = info ?? BookInfoService(this.web);
    this.covers = covers ?? CoverService(this.web);
    this.librivox = librivox ?? LibrivoxService(this.web);
    recordings = LibrivoxSource(this.web);
    builtIn = sources ??
        [
          GutenbergSource(this.web),
          recordings,
          ArchiveSource(this.web, maxBytes: maxBytes),
          WikisourceSource(this.web),
          unglueSource(this.web),
        ];
  }

  final Web web;
  late final List<BookSource> builtIn;

  /// Ratings and facts from Open Library, looked up when a book is opened.
  late final BookInfoService info;

  /// Covers to choose from, looked up only when the user asks.
  late final CoverService covers;

  /// Free recordings from LibriVox, looked up only when the user asks.
  late final LibrivoxService librivox;

  /// LibriVox as a library to search and browse.
  late final LibrivoxSource recordings;

  /// Catalogs the user added, by their link.
  List<OpdsSource> catalogs = [];

  List<BookSource> get sources => [...builtIn, ...catalogs];

  /// Replaces the user's catalogs with [saved] (name and link pairs).
  void setCatalogs(List<({String name, Uri url})> saved) {
    final old = {for (final c in catalogs) c.root.toString(): c};
    catalogs = [
      for (final c in saved)
        old[c.url.toString()] ?? OpdsSource(web, name: c.name, root: c.url),
    ];
  }
  final Future<Directory> Function() _tempDir;

  /// The biggest file TwoFold will download.
  final int maxBytes;

  static Future<Directory> _systemTemp() async => Directory(
        p.join((await getTemporaryDirectory()).path, 'find'),
      ).create(recursive: true);

  BookSource sourceOf(String id) => sources.firstWhere((s) => s.id == id);

  /// Downloads [book] to a temporary file and returns it with its format. The
  /// caller imports it and then deletes it. [onProgress] gets the bytes so
  /// far and the total, when the site says it.
  Future<(File, BookFormat)> download(
    FoundBook book, {
    void Function(int received, int? total)? onProgress,
  }) async {
    final targets = await sourceOf(book.source).targets(book);
    if (targets.isEmpty) {
      throw const WebError('There is no EPUB or text PDF of this one to download.');
    }
    final dir = await _tempDir();
    WebError? last;
    for (final target in targets) {
      final dest = File(p.join(dir.path, '${const Uuid().v4()}${target.format.extension}'));
      try {
        await web.download(
          target.url,
          dest,
          magic: target.format.magic,
          maxBytes: maxBytes,
          onProgress: onProgress,
        );
        return (dest, target.format);
      } on WebError catch (e) {
        last = e;
        // Only "this file is not there" is worth trying another file for.
        if (!e.notFound) rethrow;
      }
    }
    throw last ?? const WebError('That one is not available.');
  }
}

/// Unglue.it: free, openly licensed ebooks (Creative Commons and public
/// domain) through its OPDS catalog. It has lists to browse, no search.
OpdsSource unglueSource(Web web) => OpdsSource(
  web,
  id: 'unglue',
  name: 'Unglue.it',
  root: Uri.parse('https://unglue.it/api/opds/'),
  customBlurb:
      'Free, openly licensed books: Creative Commons and public domain. '
      'Lists can take up to half a minute to load.',
  // Its lists take 7 to 30 seconds to build (measured 2026-11-10).
  readTimeout: const Duration(seconds: 45),
);
