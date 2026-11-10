import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:twofold/find/book_source.dart';
import 'package:twofold/find/find_service.dart';
import 'package:twofold/find/web.dart';

class _Source extends BookSource {
  _Source(this.targetList);

  final List<DownloadTarget> targetList;

  @override
  String get id => 'fake';
  @override
  String get name => 'Fake';
  @override
  String get blurb => '';
  @override
  Future<FoundPage> search(String query, {int page = 0}) async =>
      const FoundPage([], hasMore: false);
  @override
  Future<List<DownloadTarget>> targets(FoundBook book) async => targetList;
}

const _book = FoundBook(source: 'fake', id: '1', title: 'A Book');

void main() {
  late Directory tmp;
  late HttpServer server;
  final hits = <String>[];

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('twofold-find');
    hits.clear();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((r) async {
      hits.add(r.uri.path);
      switch (r.uri.path) {
        case '/missing':
          r.response.statusCode = 404;
        case '/busy':
          r.response.statusCode = 503;
        default:
          r.response.add(Uint8List.fromList([0x50, 0x4B, 0x03, 0x04, 1, 2, 3]));
      }
      await r.response.close();
    });
  });
  tearDown(() async {
    await server.close(force: true);
    tmp.deleteSync(recursive: true);
  });

  FindService service(List<String> paths) => FindService(
        web: Web(hosts: {'127.0.0.1'}, https: false),
        sources: [
          _Source([
            for (final p in paths)
              DownloadTarget(
                Uri.parse('http://127.0.0.1:${server.port}$p'),
                BookFormat.epub,
              ),
          ]),
        ],
        tempDir: () async => tmp,
      );

  test('a missing file falls back to the next one', () async {
    final (file, format) = await service(['/missing', '/ok']).download(_book);
    expect(hits, ['/missing', '/ok']);
    expect(format, BookFormat.epub);
    expect(file.path, endsWith('.epub'));
    expect(file.lengthSync(), 7);
  });

  test('a busy site stops the search instead of trying more files', () async {
    await expectLater(
      service(['/busy', '/ok']).download(_book),
      throwsA(isA<WebError>().having((e) => e.message, 'message', contains('busy'))),
    );
    expect(hits, ['/busy']);
  });

  test('when every file is missing, says so', () async {
    await expectLater(
      service(['/missing', '/missing']).download(_book),
      throwsA(isA<WebError>().having((e) => e.notFound, 'notFound', isTrue)),
    );
  });

  test('a book with nothing to download says so without asking the site', () async {
    await expectLater(
      service([]).download(_book),
      throwsA(isA<WebError>().having((e) => e.message, 'message', contains('no EPUB'))),
    );
    expect(hits, isEmpty);
  });

  test('reports progress in bytes, with the total when the site gives it', () async {
    final seen = <(int, int?)>[];
    await service(['/ok']).download(_book, onProgress: (got, total) => seen.add((got, total)));
    expect(seen, isNotEmpty);
    expect(seen.every((p) => p.$1 > 0 && (p.$2 == null || p.$1 <= p.$2!)), isTrue);
  });
}
