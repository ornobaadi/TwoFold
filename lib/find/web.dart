import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// How TwoFold introduces itself to the sites it asks. They can see who is
/// calling, and a name and a page to read about us is the polite thing to send.
const userAgent = 'TwoFold/0.2 (Android reader; https://github.com/ornobaadi/TwoFold)';

/// The only sites TwoFold talks to, and the sites they send files from.
const findHosts = {
  'gutenberg.org',
  'archive.org',
  'wikisource.org',
  'wmcloud.org',
  'openlibrary.org',
  'unglue.it',
};

/// Something went wrong that the user can be told about in plain words.
class WebError implements Exception {
  const WebError(this.message, {this.notFound = false});

  final String message;

  /// The site has no such file, so a different file may work.
  final bool notFound;

  @override
  String toString() => message;
}

const offlineMessage = 'Could not connect. Check your internet and try again.';

/// A small, strict HTTP client. It talks only to [hosts] over https (also
/// when a redirect asks for something else), sends a plain User-Agent and
/// limits how much it will read.
class Web {
  Web({
    HttpClient? client,
    Set<String> hosts = findHosts,
    this.https = true,
  }) : hosts = {...hosts},
       _client = (client ?? HttpClient())
         ..connectionTimeout = const Duration(seconds: 15)
         ..userAgent = userAgent;

  final HttpClient _client;
  final Set<String> hosts;

  /// Lets a catalog the user added be reached, over https only.
  void allow(String host) => hosts.add(host.toLowerCase());

  /// Tests turn this off to use a server on this computer.
  final bool https;

  void close() => _client.close(force: true);

  void _check(Uri url) {
    final schemeOk = url.scheme == 'https' || (!https && url.scheme == 'http');
    final hostOk = hosts.any((h) => url.host == h || url.host.endsWith('.$h'));
    if (!schemeOk || !hostOk) {
      throw const WebError('The site tried to send us somewhere else, so we stopped.');
    }
  }

  /// Runs [body], turning network trouble into a [WebError].
  Future<T> _guard<T>(Future<T> Function() body) async {
    try {
      return await body();
    } on WebError {
      rethrow;
    } on SocketException {
      throw const WebError(offlineMessage);
    } on HandshakeException {
      throw const WebError(offlineMessage);
    } on TimeoutException {
      throw const WebError('The site took too long to answer. Try again in a moment.');
    } on HttpException {
      throw const WebError(offlineMessage);
    }
  }

  /// Opens [url], following redirects by hand so each stop can be checked.
  /// With [from], asks for the file from that byte on (a 206 reply).
  Future<HttpClientResponse> _open(Uri url, Duration timeout, {int? from}) async {
    var current = url;
    for (var hop = 0; hop <= 5; hop++) {
      _check(current);
      final request = await _client.getUrl(current).timeout(timeout);
      request.followRedirects = false;
      // One request per connection. Project Gutenberg's server cut a download
      // short when the connection was kept for the next one.
      request.persistentConnection = false;
      if (from != null) {
        request.headers.set(HttpHeaders.rangeHeader, 'bytes=$from-');
      }
      final response = await request.close().timeout(timeout);
      if (response.isRedirect) {
        final next = response.headers.value(HttpHeaders.locationHeader);
        await response.drain<void>();
        if (next == null) throw const WebError('The site sent an odd reply.');
        current = current.resolve(next);
        continue;
      }
      if (response.statusCode == 200 || (from != null && response.statusCode == 206)) {
        return response;
      }
      await response.drain<void>();
      throw _statusError(response.statusCode);
    }
    throw const WebError('The site sent us round in circles.');
  }

  WebError _statusError(int code) => switch (code) {
        404 || 410 => const WebError('That one is not available.', notFound: true),
        429 || 503 => const WebError('The site is busy right now. Try again in a minute.'),
        _ => WebError('The site answered with an error ($code). Try again later.'),
      };

  /// The text of a page, at most [maxBytes] long.
  Future<String> getText(
    Uri url, {
    int maxBytes = 4 << 20,
    Duration timeout = const Duration(seconds: 25),
  }) async =>
      utf8.decode(await getBytes(url, maxBytes: maxBytes, timeout: timeout),
          allowMalformed: true);

  /// The bytes of a small file (a page, a cover), at most [maxBytes].
  Future<Uint8List> getBytes(
    Uri url, {
    int maxBytes = 4 << 20,
    Duration timeout = const Duration(seconds: 25),
  }) => _guard(() async {
    final response = await _open(url, timeout);
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in response.timeout(timeout)) {
      bytes.add(chunk);
      if (bytes.length > maxBytes) {
        throw const WebError('The answer was too big to read.');
      }
    }
    return bytes.takeBytes();
  });

  /// Saves [url] to [dest], only if it is a real [magic]-marked file no bigger
  /// than [maxBytes]. Nothing is left behind when it fails. [onProgress] gets
  /// the bytes so far and the total, when the site says what it is.
  ///
  /// If the connection drops part-way, which happens on phones, it carries on
  /// from where it stopped (up to [resumes] times) instead of starting over.
  Future<void> download(
    Uri url,
    File dest, {
    required List<int> magic,
    required int maxBytes,
    void Function(int received, int? total)? onProgress,
    Duration headerTimeout = const Duration(seconds: 120),
    Duration stallTimeout = const Duration(seconds: 30),
    int resumes = 2,
  }) => _guard(() async {
    final part = File('${dest.path}.part');
    var received = 0;
    int? total;
    try {
      for (var attempt = 0;; attempt++) {
        final resuming = received > 0;
        final response = await _open(
          url,
          headerTimeout,
          from: resuming ? received : null,
        );
        // A site that ignores the request to resume starts the file again.
        if (resuming && response.statusCode != 206) received = 0;
        if (received == 0) {
          total = response.contentLength >= 0 ? response.contentLength : null;
        }
        if (total != null && total > maxBytes) {
          await response.drain<void>();
          throw WebError('That file is too big (${(total / (1 << 20)).round()} MB).');
        }
        final sink = part.openWrite(
          mode: received == 0 ? FileMode.write : FileMode.append,
        );
        try {
          await for (final chunk in response.timeout(stallTimeout)) {
            received += chunk.length;
            if (received > maxBytes) throw const WebError('That file is too big.');
            sink.add(chunk);
            onProgress?.call(received, total);
          }
          await sink.close();
          break;
        } on WebError {
          await _closeQuietly(sink);
          rethrow;
        } catch (e) {
          await _closeQuietly(sink);
          final dropped = e is HttpException ||
              e is SocketException ||
              e is TimeoutException;
          if (!dropped || attempt >= resumes || received == 0) rethrow;
        }
      }
      if (total != null && received != total) {
        throw const WebError('The download stopped early. Try again.');
      }
      final head = await _head(part, magic.length);
      if (head.length < magic.length || !_same(head, magic)) {
        throw const WebError(
          'The site did not send a book. It may be busy, so try again later.',
        );
      }
      await part.rename(dest.path);
    } catch (_) {
      if (part.existsSync()) await part.delete();
      rethrow;
    }
  });

  Future<void> _closeQuietly(IOSink sink) async {
    try {
      await sink.close();
    } catch (_) {}
  }

  Future<List<int>> _head(File file, int count) async {
    final f = await file.open();
    try {
      return await f.read(count);
    } finally {
      await f.close();
    }
  }

  bool _same(List<int> a, List<int> b) {
    for (var i = 0; i < b.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
