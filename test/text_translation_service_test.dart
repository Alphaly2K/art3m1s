import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:art3m1s/models/translation_settings.dart';
import 'package:art3m1s/proto/translation_cache.pb.dart';
import 'package:art3m1s/services/text_translation_service.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('translation provider protocols', () {
    test('OpenAI Responses carries auth and ruby context', () async {
      final mock = await _MockApi.start({
        'output': [
          {
            'content': [
              {'type': 'output_text', 'text': '水豚'},
            ],
          },
        ],
      }, path: '/v1/responses');
      final result = await _translate(
        mock,
        TranslationSettings(
          mode: TranslationMode.online,
          provider: TranslationProvider.openAi,
          endpoint: mock.endpoint,
          apiKey: 'openai-key',
          model: 'test-model',
        ),
        '鬼天竺鼠',
        ruby: 'カピバラ',
      );

      expect(result.translation, '水豚');
      expect(result.request.headers['authorization'], 'Bearer openai-key');
      final body = jsonDecode(result.request.body) as Map;
      expect(body['input'], '鬼天竺鼠');
      expect(body['instructions'], contains('カピバラ'));
    });

    test('Anthropic Messages uses required headers', () async {
      final mock = await _MockApi.start({
        'content': [
          {'type': 'text', 'text': '你好'},
        ],
      });
      final result = await _translate(
        mock,
        TranslationSettings(
          mode: TranslationMode.online,
          provider: TranslationProvider.anthropic,
          endpoint: mock.endpoint,
          apiKey: 'anthropic-key',
          model: 'claude-test',
        ),
        'こんにちは',
      );

      expect(result.translation, '你好');
      expect(result.request.headers['x-api-key'], 'anthropic-key');
      expect(result.request.headers['anthropic-version'], '2023-06-01');
    });

    test('DeepL uses JSON and provider language codes', () async {
      final mock = await _MockApi.start({
        'translations': [
          {'text': '你好'},
        ],
      });
      final result = await _translate(
        mock,
        TranslationSettings(
          mode: TranslationMode.online,
          provider: TranslationProvider.deepL,
          endpoint: mock.endpoint,
          apiKey: 'deepl-key',
        ),
        'こんにちは',
        ruby: 'コンニチハ',
      );

      expect(result.translation, '你好');
      expect(
        result.request.headers['authorization'],
        'DeepL-Auth-Key deepl-key',
      );
      final body = jsonDecode(result.request.body) as Map;
      expect(body['source_lang'], 'JA');
      expect(body['target_lang'], 'ZH-HANS');
      expect(body['context'], contains('コンニチハ'));
    });

    test('Google Basic sends API key and text language codes', () async {
      final mock = await _MockApi.start({
        'data': {
          'translations': [
            {'translatedText': 'A &amp; B'},
          ],
        },
      });
      final result = await _translate(
        mock,
        TranslationSettings(
          mode: TranslationMode.online,
          provider: TranslationProvider.google,
          endpoint: mock.endpoint,
          apiKey: 'google-key',
        ),
        'こんにちは',
      );

      expect(result.translation, 'A & B');
      expect(result.request.uri.queryParameters['key'], 'google-key');
      final body = jsonDecode(result.request.body) as Map;
      expect(body['source'], 'ja');
      expect(body['target'], 'zh-CN');
      expect(body['format'], 'text');
    });

    test('Baidu form signature follows appid q salt secret MD5', () async {
      final mock = await _MockApi.start({
        'trans_result': [
          {'src': 'こんにちは', 'dst': '你好'},
        ],
      });
      final result = await _translate(
        mock,
        TranslationSettings(
          mode: TranslationMode.online,
          provider: TranslationProvider.baidu,
          endpoint: mock.endpoint,
          appId: 'baidu-app',
          appSecret: 'baidu-secret',
        ),
        'こんにちは',
      );

      expect(result.translation, '你好');
      final form = Uri.splitQueryString(result.request.body);
      final expected = md5
          .convert(utf8.encode('baidu-appこんにちは${form['salt']}baidu-secret'))
          .toString();
      expect(form['sign'], expected);
      expect(form['from'], 'jp');
      expect(form['to'], 'zh');
    });

    test('Youdao v3 form signature uses truncated input and SHA-256', () async {
      const source = '1234567890abcdefghijKLMN';
      final mock = await _MockApi.start({
        'errorCode': '0',
        'translation': ['译文'],
      });
      final result = await _translate(
        mock,
        TranslationSettings(
          mode: TranslationMode.online,
          provider: TranslationProvider.youdao,
          endpoint: mock.endpoint,
          appId: 'youdao-app',
          appSecret: 'youdao-secret',
        ),
        source,
      );

      expect(result.translation, '译文');
      final form = Uri.splitQueryString(result.request.body);
      final input =
          '${source.substring(0, 10)}${source.length}'
          '${source.substring(source.length - 10)}';
      final expected = sha256
          .convert(
            utf8.encode(
              'youdao-app$input${form['salt']}'
              '${form['curtime']}youdao-secret',
            ),
          )
          .toString();
      expect(form['signType'], 'v3');
      expect(form['sign'], expected);
      expect(form['from'], 'ja');
      expect(form['to'], 'zh-CHS');
    });

    test(
      'background queue deduplicates and limits concurrent requests',
      () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final release = Completer<void>();
        var requestCount = 0;
        var active = 0;
        var maxActive = 0;
        server.listen((request) async {
          requestCount++;
          active++;
          if (active > maxActive) maxActive = active;
          final body =
              jsonDecode(await utf8.decoder.bind(request).join()) as Map;
          await release.future;
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            jsonEncode({'output_text': '译:${body['input']}'}),
          );
          await request.response.close();
          active--;
        });

        final directory = await Directory.systemTemp.createTemp(
          'translation-queue-test-',
        );
        final service = await TextTranslationService.create(
          settings: TranslationSettings(
            mode: TranslationMode.online,
            provider: TranslationProvider.openAi,
            endpoint:
                'http://${server.address.address}:${server.port}/v1/responses',
            apiKey: 'key',
            model: 'model',
          ),
          patchPath: '',
          cacheFile: File('${directory.path}/cache.pb'),
        );
        final results = <Completer<String?>>[];
        void add(String source) {
          final result = Completer<String?>();
          results.add(result);
          service.enqueue(source, onComplete: result.complete);
        }

        try {
          add('A');
          add('A');
          add('B');
          add('C');
          add('D');
          add('E');
          for (var i = 0; i < 100 && requestCount < 3; i++) {
            await Future<void>.delayed(const Duration(milliseconds: 5));
          }
          expect(requestCount, 3);
          expect(maxActive, 3);
          expect(results.every((result) => !result.isCompleted), isTrue);

          release.complete();
          final translated = await Future.wait(
            results.map((result) => result.future),
          ).timeout(const Duration(seconds: 5));
          expect(requestCount, 5, reason: '重复的 A 应共享同一条 HTTP 请求');
          expect(maxActive, lessThanOrEqualTo(3));
          expect(translated, ['译:A', '译:A', '译:B', '译:C', '译:D', '译:E']);
        } finally {
          if (!release.isCompleted) release.complete();
          await service.dispose();
          await server.close(force: true);
          await directory.delete(recursive: true);
        }
      },
    );

    test('online translations persist in a protobuf cache', () async {
      final mock = await _MockApi.start({'output_text': '水豚'});
      final directory = await Directory.systemTemp.createTemp(
        'translation-protobuf-test-',
      );
      final cacheFile = File('${directory.path}/cache.pb');
      final service = await TextTranslationService.create(
        settings: TranslationSettings(
          mode: TranslationMode.online,
          provider: TranslationProvider.openAi,
          endpoint: mock.endpoint,
          apiKey: 'key',
          model: 'model',
        ),
        patchPath: '',
        cacheFile: cacheFile,
      );

      try {
        expect(await service.translate('鬼天竺鼠'), '水豚');
        await mock.request.timeout(const Duration(seconds: 5));
        await service.dispose();

        final cache = TranslationCache.fromBuffer(
          await cacheFile.readAsBytes(),
        );
        expect(cache.entries.values, contains('水豚'));
      } finally {
        await service.dispose();
        await mock.close();
        await directory.delete(recursive: true);
      }
    });
  });
}

Future<_TranslationResult> _translate(
  _MockApi mock,
  TranslationSettings settings,
  String source, {
  String? ruby,
}) async {
  final directory = await Directory.systemTemp.createTemp('translation-test-');
  final service = await TextTranslationService.create(
    settings: settings,
    patchPath: '',
    cacheFile: File('${directory.path}/cache.pb'),
  );
  try {
    final translation = await service.translate(source, ruby: ruby);
    final request = await mock.request.timeout(const Duration(seconds: 5));
    return _TranslationResult(translation, request);
  } finally {
    await service.dispose();
    await mock.close();
    await directory.delete(recursive: true);
  }
}

class _TranslationResult {
  const _TranslationResult(this.translation, this.request);

  final String? translation;
  final _CapturedRequest request;
}

class _CapturedRequest {
  const _CapturedRequest(this.uri, this.headers, this.body);

  final Uri uri;
  final Map<String, String> headers;
  final String body;
}

class _MockApi {
  _MockApi._(this._server, this.endpoint, this.request);

  final HttpServer _server;
  final String endpoint;
  final Future<_CapturedRequest> request;

  static Future<_MockApi> start(
    Object responseBody, {
    String path = '/translate',
  }) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final completer = Completer<_CapturedRequest>();
    server.listen((request) async {
      final body = await utf8.decoder.bind(request).join();
      final headers = <String, String>{};
      request.headers.forEach((name, values) {
        headers[name] = values.join(',');
      });
      completer.complete(_CapturedRequest(request.uri, headers, body));
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode(responseBody));
      await request.response.close();
    });
    return _MockApi._(
      server,
      'http://${server.address.address}:${server.port}$path',
      completer.future,
    );
  }

  Future<void> close() => _server.close(force: true);
}
