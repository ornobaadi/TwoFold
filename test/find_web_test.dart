import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:twofold/find/book_source.dart';
import 'package:twofold/find/web.dart';

/// A tiny web server on this computer, for checking the downloader without
/// the internet.
Future<HttpServer> _serve(
  FutureOr<void> Function(HttpRequest request) handle,
) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((r) async {
    await handle(r);
    await r.response.close();
  });
  return server;
}

Uri _at(Object s, String path) => Uri.parse(
    'http://127.0.0.1:${s is HttpServer ? s.port : (s as ServerSocket).port}$path');

/// A bare-bones server that answers with raw bytes, so a test can cut the
/// connection part-way through a file.
Future<ServerSocket> _raw(
  Future<void> Function(String request, Socket socket) handle,
) async {
  final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((socket) {
    final text = StringBuffer();
    var answered = false;
    socket.listen((chunk) async {
      text.write(latin1.decode(chunk));
      if (!answered && text.toString().contains('\r\n\r\n')) {
        answered = true;
        await handle(text.toString(), socket);
      }
    }, onError: (_) {}, cancelOnError: true);
  });
  return server;
}

Web _web({Set<String> hosts = const {'127.0.0.1'}, bool https = false}) =>
    Web(hosts: hosts, https: https);

Uint8List _epub(int extra) =>
    Uint8List.fromList([0x50, 0x4B, 0x03, 0x04, ...List.filled(extra, 7)]);

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('twofold-web'));
  tearDown(() => tmp.deleteSync(recursive: true));

  Future<WebError> failure(Future<void> Function() run) async {
    try {
      await run();
    } on WebError catch (e) {
      return e;
    }
    fail('expected a WebError');
  }

  test('downloads a file, reports progress, and keeps only the final file', () async {
    final server = await _serve((r) {
      r.response.headers.contentLength = 2004;
      r.response.add(_epub(2000));
    });
    final dest = File('${tmp.path}/book.epub');
    final steps = <int>[];
    await _web().download(
      _at(server, '/book'),
      dest,
      magic: BookFormat.epub.magic,
      maxBytes: 1 << 20,
      onProgress: (got, total) {
        expect(total, 2004);
        steps.add(got);
      },
    );
    expect(dest.lengthSync(), 2004);
    expect(steps.last, 2004);
    expect(tmp.listSync().map((e) => e.path.split(Platform.pathSeparator).last),
        ['book.epub']);
    await server.close(force: true);
  });

  test('follows a redirect within the allowed sites', () async {
    final server = await _serve((r) {
      if (r.uri.path == '/start') {
        r.response.statusCode = 302;
        r.response.headers.set('location', '/real');
      } else {
        r.response.add(_epub(10));
      }
    });
    final dest = File('${tmp.path}/a.epub');
    await _web().download(_at(server, '/start'), dest,
        magic: BookFormat.epub.magic, maxBytes: 1 << 20);
    expect(dest.existsSync(), isTrue);
    await server.close(force: true);
  });

  test('refuses a redirect to a site that is not on the list', () async {
    final server = await _serve((r) {
      r.response.statusCode = 302;
      r.response.headers.set('location', 'http://localhost:9/elsewhere');
    });
    final dest = File('${tmp.path}/a.epub');
    final e = await failure(() => _web().download(_at(server, '/x'), dest,
        magic: BookFormat.epub.magic, maxBytes: 1 << 20));
    expect(e.message, contains('somewhere else'));
    expect(dest.existsSync(), isFalse);
    await server.close(force: true);
  });

  test('refuses plain http when https is required', () async {
    final e = await failure(() => Web(hosts: {'127.0.0.1'}).download(
        Uri.parse('http://127.0.0.1:1/x'), File('${tmp.path}/a.epub'),
        magic: BookFormat.epub.magic, maxBytes: 100));
    expect(e.message, contains('somewhere else'));
  });

  test('refuses a web page that is not a book, and leaves nothing behind', () async {
    final server = await _serve((r) {
      r.response.headers.contentType = ContentType.html;
      r.response.write('<html>Please prove you are human</html>');
    });
    final dest = File('${tmp.path}/a.epub');
    final e = await failure(() => _web().download(_at(server, '/x'), dest,
        magic: BookFormat.epub.magic, maxBytes: 1 << 20));
    expect(e.message, contains('did not send a book'));
    expect(tmp.listSync(), isEmpty);
    await server.close(force: true);
  });

  test('stops a file that is too big, by its size or as it arrives', () async {
    final server = await _serve((r) {
      if (r.uri.path == '/announced') {
        r.response.headers.contentLength = 5000;
      } else {
        r.response.headers.chunkedTransferEncoding = true;
      }
      r.response.add(_epub(4996));
    });
    for (final path in ['/announced', '/chunked']) {
      final dest = File('${tmp.path}/big.epub');
      final e = await failure(() => _web().download(_at(server, path), dest,
          magic: BookFormat.epub.magic, maxBytes: 1000));
      expect(e.message, contains('too big'));
      expect(tmp.listSync(), isEmpty, reason: path);
    }
    await server.close(force: true);
  });

  test('says in words when a file is missing, so another can be tried', () async {
    final server = await _serve((r) => r.response.statusCode = 404);
    final e = await failure(() => _web().download(_at(server, '/x'),
        File('${tmp.path}/a.epub'),
        magic: BookFormat.epub.magic, maxBytes: 100));
    expect(e.notFound, isTrue);
    await server.close(force: true);

    final busy = await _serve((r) => r.response.statusCode = 429);
    final b = await failure(() => _web().download(_at(busy, '/x'),
        File('${tmp.path}/a.epub'),
        magic: BookFormat.epub.magic, maxBytes: 100));
    expect(b.notFound, isFalse);
    expect(b.message, contains('busy'));
    await busy.close(force: true);
  });

  test('carries on from where a dropped connection stopped', () async {
    final whole = _epub(1996); // 2000 bytes
    final ranges = <String?>[];
    final server = await _raw((request, socket) async {
      final range = RegExp(r'range: bytes=(\d+)-', caseSensitive: false).firstMatch(request);
      ranges.add(range?.group(1));
      if (range == null) {
        // First try: promise everything, send 800 bytes, then the line goes dead.
        socket.add(latin1.encode('HTTP/1.1 200 OK\r\nContent-Length: 2000\r\n\r\n'));
        socket.add(whole.sublist(0, 800));
        await socket.flush();
        socket.destroy();
      } else {
        final from = int.parse(range.group(1)!);
        socket.add(latin1.encode('HTTP/1.1 206 Partial Content\r\n'
            'Content-Length: ${2000 - from}\r\n'
            'Content-Range: bytes $from-1999/2000\r\n\r\n'));
        socket.add(whole.sublist(from));
        await socket.flush();
        await socket.close();
      }
    });
    final dest = File('${tmp.path}/resumed.epub');
    final seen = <int>[];
    await _web().download(_at(server, '/x'), dest,
        magic: BookFormat.epub.magic,
        maxBytes: 1 << 20,
        onProgress: (got, _) => seen.add(got));
    expect(ranges, [null, '800']);
    expect(dest.readAsBytesSync(), whole, reason: 'byte for byte the same file');
    expect(seen.last, 2000);
    expect(tmp.listSync().length, 1, reason: 'no .part file is left');
    await server.close();
  });

  test('starts again when the site will not resume', () async {
    final whole = _epub(1996);
    var tries = 0;
    final server = await _raw((request, socket) async {
      tries++;
      socket.add(latin1.encode('HTTP/1.1 200 OK\r\nContent-Length: 2000\r\n\r\n'));
      if (tries == 1) {
        socket.add(whole.sublist(0, 500));
        await socket.flush();
        socket.destroy();
      } else {
        // Ignores the Range header and sends the whole file again.
        socket.add(whole);
        await socket.flush();
        await socket.close();
      }
    });
    final dest = File('${tmp.path}/restarted.epub');
    await _web().download(_at(server, '/x'), dest,
        magic: BookFormat.epub.magic, maxBytes: 1 << 20);
    expect(dest.readAsBytesSync(), whole);
    expect(tries, 2);
    await server.close();
  });

  test('gives up after a few drops and leaves nothing behind', () async {
    final whole = _epub(1996);
    var drops = 0;
    final server = await _raw((request, socket) async {
      drops++;
      socket.add(latin1.encode('HTTP/1.1 200 OK\r\nContent-Length: 2000\r\n\r\n'));
      socket.add(whole.sublist(0, 300));
      await socket.flush();
      socket.destroy();
    });
    final dest = File('${tmp.path}/never.epub');
    final e = await failure(() => _web().download(_at(server, '/x'), dest,
        magic: BookFormat.epub.magic, maxBytes: 1 << 20));
    expect(e.message, offlineMessage);
    expect(drops, 3, reason: 'one try and two resumes');
    expect(dest.existsSync(), isFalse);
    expect(tmp.listSync(), isEmpty);
    await server.close();
  });

  test('no connection gives the offline message', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final port = server.port;
    await server.close(force: true);
    final e = await failure(() => _web().getText(Uri.parse('http://127.0.0.1:$port/')));
    expect(e.message, offlineMessage);
  });

  test('reads text, and sends its own name', () async {
    String? agent;
    final server = await _serve((r) {
      agent = r.headers.value('user-agent');
      r.response.write('hello');
    });
    expect(await _web().getText(_at(server, '/')), 'hello');
    expect(agent, userAgent);
    expect(agent, startsWith('TwoFold/'));
    await server.close(force: true);
  });

  test('the real list of sites covers what the sources talk to', () {
    final web = Web();
    for (final url in [
      'https://www.gutenberg.org/ebooks/11.epub3.images',
      'https://archive.org/download/x/x.epub',
      'https://ia800000.us.archive.org/1/items/x/x.epub',
      'https://en.wikisource.org/w/api.php',
      'https://ws-export.wmcloud.org/',
    ]) {
      expect(findHosts.any((h) => Uri.parse(url).host == h || Uri.parse(url).host.endsWith('.$h')),
          isTrue, reason: url);
    }
    expect(findHosts.any((h) => 'evil-gutenberg.org'.endsWith('.$h') || 'evil-gutenberg.org' == h),
        isFalse);
    web.close();
  });
}
