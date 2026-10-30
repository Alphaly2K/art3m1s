import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:art3m1s/services/script_http_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'GET and POST return status and bytes, including form file values',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final client = ScriptHttpClient();
      addTearDown(() async {
        client.cancel();
        await server.close(force: true);
      });
      server.listen((request) async {
        expect(request.headers.value('x-game'), 'test');
        if (request.method == 'POST') {
          final form = Uri.splitQueryString(
            await utf8.decoder.bind(request).join(),
          );
          expect(form, {'text': 'a & b', 'file': '文件正文'});
        }
        request.response.statusCode = 201;
        request.response.add([1, 2, 3]);
        await request.response.close();
      });
      for (final method in ['GET', 'POST']) {
        final done = Completer<(int, Uint8List)>();
        client.start(
          {
            'serial': 1,
            'url': 'http://${server.address.address}:${server.port}/',
            'method': method,
            'headers': [
              ['x-game', 'test'],
            ],
            'data': [
              ['text', 'a & b'],
            ],
            'file_data': [
              ['file', 'body.txt'],
            ],
          },
          readFile: (_) => utf8.encode('文件正文'),
          onComplete: (status, body) => done.complete((status, body)),
        );
        final (status, body) = await done.future;
        expect(status, 201);
        expect(body, [1, 2, 3]);
      }
    },
  );

  test(
    'timeout and invalid URLs complete with the core failure status',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((_) {});
      final client = ScriptHttpClient(
        timeout: const Duration(milliseconds: 100),
      );
      addTearDown(client.cancel);
      for (final url in [
        'file:///invalid',
        'http://127.0.0.1:${server.port}/',
      ]) {
        final done = Completer<int>();
        client.start(
          {'serial': 2, 'url': url, 'method': 'GET'},
          readFile: (_) => null,
          onComplete: (status, _) => done.complete(status),
        );
        expect(await done.future, 0);
      }
    },
  );

  test('canceled replies cannot complete a replacement request', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final client = ScriptHttpClient();
    addTearDown(() async {
      client.cancel();
      await server.close(force: true);
    });
    final first = Completer<HttpRequest>();
    server.listen((request) {
      if (request.uri.path == '/first') {
        first.complete(request);
      } else {
        request.response.write('new');
        unawaited(request.response.close());
      }
    });
    var staleCompletions = 0;
    final base = 'http://127.0.0.1:${server.port}';
    client.start(
      {'serial': 1, 'url': '$base/first', 'method': 'GET'},
      readFile: (_) => null,
      onComplete: (_, _) => staleCompletions++,
    );
    final delayed = await first.future;
    final done = Completer<String>();
    client.start(
      {'serial': 2, 'url': '$base/second', 'method': 'GET'},
      readFile: (_) => null,
      onComplete: (_, body) => done.complete(utf8.decode(body)),
    );
    client.cancel(1);
    delayed.response.write('old');
    await delayed.response.close();
    expect(await done.future, 'new');
    expect(staleCompletions, 0);
  });
}
