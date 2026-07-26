import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:crypto/crypto.dart';

import '../models/translation_settings.dart';
import 'logger.dart';

class TextTranslationService {
  TextTranslationService._({
    required this.settings,
    required this.cacheFile,
    required this._patch,
    required this._cache,
  });

  final TranslationSettings settings;
  final File cacheFile;
  final Map<String, String> _patch;
  final Map<String, String> _cache;
  final HttpClient _client = HttpClient();
  final Queue<_TranslationJob> _queue = Queue();
  final Map<String, _TranslationJob> _jobs = {};
  int _activeJobs = 0;
  Timer? _cacheWriteTimer;
  bool _disposed = false;

  int get _maxConcurrent => switch (settings.provider) {
    TranslationProvider.baidu || TranslationProvider.youdao => 2,
    TranslationProvider.openAi || TranslationProvider.anthropic => 3,
    TranslationProvider.deepL || TranslationProvider.google => 4,
  };

  static Future<TextTranslationService> create({
    required TranslationSettings settings,
    required File cacheFile,
  }) async {
    final patch = await _loadPatch(settings.patchPath);
    final cache = await _loadStringMap(cacheFile);
    Log.info(
      '[Translation] mode=${settings.mode.name} '
      'provider=${settings.provider.name} '
      'patch=${patch.length} cache=${cache.length}',
    );
    return TextTranslationService._(
      settings: settings,
      cacheFile: cacheFile,
      patch: patch,
      cache: cache,
    );
  }

  int inject(String source, Pointer<Uint8> output, int capacity) {
    if (_disposed || settings.mode == TranslationMode.off) return -1;
    final translated =
        _patch[source] ?? _cache[_cacheKey(source)] ?? _cache[source];
    if (translated != null) {
      return _writeUtf8(translated, output, capacity);
    }
    if (settings.mode == TranslationMode.patch || source.trim().isEmpty) {
      return -1;
    }
    return -2;
  }

  Future<String?> translate(String source, {String? ruby}) async {
    if (_disposed) return null;
    final known =
        _patch[source] ??
        _cache[_cacheKey(source, ruby: ruby)] ??
        _cache[_cacheKey(source)] ??
        _cache[source];
    if (known != null) return known;
    if (settings.mode != TranslationMode.online) return null;

    try {
      final translated = await _TranslationApiClient(
        settings,
        _client,
      ).translate(source, ruby: ruby);
      if (_disposed || translated == null || translated.isEmpty) return null;
      _cache[_cacheKey(source, ruby: ruby)] = translated;
      _scheduleCacheWrite();
      return translated;
    } catch (error, stackTrace) {
      Log.error('[Translation:${settings.provider.label}] 在线翻译失败: $error');
      Log.debug(stackTrace.toString());
      return null;
    }
  }

  /// 把在线翻译放入去重的有限并发队列并立即返回。
  ///
  /// Dart 的 HttpClient 本身是异步 I/O，无需为网络请求创建 isolate；并发槽位
  /// 可以同时等待多个服务响应，又不会无限制地触发供应商限流。
  void enqueue(
    String source, {
    String? ruby,
    required void Function(String? translation) onComplete,
  }) {
    if (_disposed) {
      scheduleMicrotask(() => onComplete(null));
      return;
    }
    final known =
        _patch[source] ??
        _cache[_cacheKey(source, ruby: ruby)] ??
        _cache[_cacheKey(source)] ??
        _cache[source];
    if (known != null || settings.mode != TranslationMode.online) {
      scheduleMicrotask(() => onComplete(known));
      return;
    }

    final key = _cacheKey(source, ruby: ruby);
    final existing = _jobs[key];
    if (existing != null) {
      existing.callbacks.add(onComplete);
      return;
    }
    if (_jobs.length >= 512) {
      Log.warn('[Translation] 后台队列已满，暂时保留原文');
      scheduleMicrotask(() => onComplete(null));
      return;
    }

    final job = _TranslationJob(key, source, ruby, onComplete);
    _jobs[key] = job;
    _queue.add(job);
    scheduleMicrotask(_pumpQueue);
  }

  void _pumpQueue() {
    if (_disposed) return;
    while (_activeJobs < _maxConcurrent && _queue.isNotEmpty) {
      final job = _queue.removeFirst();
      _activeJobs++;
      unawaited(_runJob(job));
    }
  }

  Future<void> _runJob(_TranslationJob job) async {
    String? translated;
    try {
      translated = await translate(job.source, ruby: job.ruby);
    } finally {
      _activeJobs--;
      if (identical(_jobs.remove(job.key), job)) {
        for (final callback in job.callbacks) {
          try {
            callback(translated);
          } catch (error) {
            Log.warn('[Translation] 回填回调失败: $error');
          }
        }
      }
      _pumpQueue();
    }
  }

  String _cacheKey(String source, {String? ruby}) {
    return [
      'v2',
      settings.provider.name,
      settings.sourceLanguage,
      settings.targetLanguage,
      ruby ?? '',
      source,
    ].join('\u0000');
  }

  void _scheduleCacheWrite() {
    _cacheWriteTimer?.cancel();
    _cacheWriteTimer = Timer(const Duration(milliseconds: 500), () {
      unawaited(_writeCache());
    });
  }

  Future<void> _writeCache() async {
    if (_disposed && _cache.isEmpty) return;
    try {
      await cacheFile.parent.create(recursive: true);
      final temporary = File('${cacheFile.path}.tmp');
      await temporary.writeAsString(
        const JsonEncoder.withIndent('  ').convert(_cache),
        flush: true,
      );
      if (await cacheFile.exists()) await cacheFile.delete();
      await temporary.rename(cacheFile.path);
    } catch (error) {
      Log.warn('[Translation] 写入缓存失败: $error');
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _cacheWriteTimer?.cancel();
    _queue.clear();
    _jobs.clear();
    await _writeCache();
    _client.close(force: true);
  }

  static int _writeUtf8(String value, Pointer<Uint8> output, int capacity) {
    final bytes = utf8.encode(value);
    if (bytes.length > capacity) {
      Log.warn('[Translation] 译文超过 core 注入缓冲区，保持原文');
      return -1;
    }
    output.asTypedList(capacity).setRange(0, bytes.length, bytes);
    return bytes.length;
  }

  static Future<Map<String, String>> _loadPatch(String path) async {
    if (path.trim().isEmpty) return {};
    final file = File(path);
    if (!await file.exists()) {
      Log.warn('[Translation] 对照文件不存在: $path');
      return {};
    }
    try {
      final content = await file.readAsString();
      final lower = path.toLowerCase();
      if (lower.endsWith('.tsv')) return _parseTsv(content);
      if (lower.endsWith('.jsonl')) return _parseJsonLines(content);
      return _parseJson(content);
    } catch (error) {
      Log.error('[Translation] 读取对照文件失败: $error');
      return {};
    }
  }

  static Future<Map<String, String>> _loadStringMap(File file) async {
    if (!await file.exists()) return {};
    try {
      return _parseJson(await file.readAsString());
    } catch (error) {
      Log.warn('[Translation] 忽略损坏的翻译缓存: $error');
      return {};
    }
  }

  static Map<String, String> _parseJson(String content) {
    final decoded = jsonDecode(content);
    if (decoded is Map) {
      return {
        for (final entry in decoded.entries)
          if (entry.value is String)
            entry.key.toString(): entry.value as String,
      };
    }
    if (decoded is List) {
      return {
        for (final item in decoded)
          if (item is Map &&
              item['source'] is String &&
              (item['translation'] is String || item['target'] is String))
            item['source'] as String:
                (item['translation'] ?? item['target']) as String,
      };
    }
    throw const FormatException('JSON 必须是字符串映射或条目数组');
  }

  static Map<String, String> _parseJsonLines(String content) {
    final result = <String, String>{};
    for (final line in const LineSplitter().convert(content)) {
      if (line.trim().isEmpty) continue;
      final item = jsonDecode(line);
      if (item is Map && item['source'] is String) {
        final target = item['translation'] ?? item['target'];
        if (target is String) result[item['source'] as String] = target;
      }
    }
    return result;
  }

  static Map<String, String> _parseTsv(String content) {
    final result = <String, String>{};
    for (final line in const LineSplitter().convert(content)) {
      if (line.trim().isEmpty || line.trimLeft().startsWith('#')) continue;
      final tab = line.indexOf('\t');
      if (tab <= 0) continue;
      result[line.substring(0, tab)] = line.substring(tab + 1);
    }
    return result;
  }
}

class _TranslationJob {
  _TranslationJob(
    this.key,
    this.source,
    this.ruby,
    void Function(String? translation) callback,
  ) : callbacks = [callback];

  final String key;
  final String source;
  final String? ruby;
  final List<void Function(String? translation)> callbacks;
}

class _TranslationApiClient {
  const _TranslationApiClient(this.settings, this.client);

  final TranslationSettings settings;
  final HttpClient client;

  Future<String?> translate(String source, {String? ruby}) {
    return switch (settings.provider) {
      TranslationProvider.openAi => _translateOpenAi(source, ruby),
      TranslationProvider.anthropic => _translateAnthropic(source, ruby),
      TranslationProvider.deepL => _translateDeepL(source, ruby),
      TranslationProvider.google => _translateGoogle(source),
      TranslationProvider.baidu => _translateBaidu(source),
      TranslationProvider.youdao => _translateYoudao(source),
    };
  }

  Future<String?> _translateOpenAi(String source, String? ruby) async {
    final endpoint = _endpoint();
    final headers = <String, String>{};
    if (settings.apiKey.trim().isNotEmpty) {
      headers[HttpHeaders.authorizationHeader] =
          'Bearer ${settings.apiKey.trim()}';
    }
    final prompt = _systemPrompt(ruby);
    final useResponses = endpoint.path.endsWith('/responses');
    final body = useResponses
        ? <String, dynamic>{
            'model': _required(settings.model, 'Model'),
            'instructions': prompt,
            'input': source,
            'max_output_tokens': 1024,
          }
        : <String, dynamic>{
            'model': _required(settings.model, 'Model'),
            'temperature': 0,
            'messages': [
              {'role': 'system', 'content': prompt},
              {'role': 'user', 'content': source},
            ],
          };
    final decoded = await _postJson(endpoint, body, headers: headers);
    _throwApiError(decoded);
    return _extractOpenAi(decoded);
  }

  Future<String?> _translateAnthropic(String source, String? ruby) async {
    final decoded = await _postJson(
      _endpoint(),
      {
        'model': _required(settings.model, 'Model'),
        'max_tokens': 1024,
        'system': _systemPrompt(ruby),
        'messages': [
          {'role': 'user', 'content': source},
        ],
      },
      headers: {
        'x-api-key': _required(settings.apiKey, 'API Key'),
        'anthropic-version': '2023-06-01',
      },
    );
    _throwApiError(decoded);
    final content = decoded is Map ? decoded['content'] : null;
    if (content is List) {
      for (final block in content) {
        if (block is Map &&
            block['type'] == 'text' &&
            block['text'] is String) {
          return (block['text'] as String).trim();
        }
      }
    }
    return null;
  }

  Future<String?> _translateDeepL(String source, String? ruby) async {
    final body = <String, dynamic>{
      'text': [source],
      'target_lang': _providerLanguage(settings.targetLanguage, target: true),
      'preserve_formatting': true,
    };
    if (ruby != null && ruby.isNotEmpty) {
      // DeepL does not translate context, but uses it to disambiguate the text.
      body['context'] = 'Ruby reading: $ruby';
    }
    final sourceLanguage = _providerLanguage(
      settings.sourceLanguage,
      target: false,
    );
    if (sourceLanguage != 'AUTO') body['source_lang'] = sourceLanguage;
    final decoded = await _postJson(
      _endpoint(),
      body,
      headers: {
        HttpHeaders.authorizationHeader:
            'DeepL-Auth-Key ${_required(settings.apiKey, 'API Key')}',
      },
    );
    _throwApiError(decoded);
    final translations = decoded is Map ? decoded['translations'] : null;
    if (translations is List &&
        translations.isNotEmpty &&
        translations.first is Map) {
      return (translations.first as Map)['text']?.toString().trim();
    }
    return null;
  }

  Future<String?> _translateGoogle(String source) async {
    final endpoint = _endpoint().replace(
      queryParameters: {
        ..._endpoint().queryParameters,
        'key': _required(settings.apiKey, 'API Key'),
      },
    );
    final body = <String, dynamic>{
      'q': source,
      'target': _providerLanguage(settings.targetLanguage, target: true),
      'format': 'text',
    };
    final sourceLanguage = _providerLanguage(
      settings.sourceLanguage,
      target: false,
    );
    if (sourceLanguage != 'auto') body['source'] = sourceLanguage;
    final decoded = await _postJson(endpoint, body);
    _throwApiError(decoded);
    final data = decoded is Map ? decoded['data'] : null;
    final translations = data is Map ? data['translations'] : null;
    if (translations is List &&
        translations.isNotEmpty &&
        translations.first is Map) {
      final translated = (translations.first as Map)['translatedText'];
      if (translated is String) return _decodeHtmlEntities(translated).trim();
    }
    return null;
  }

  Future<String?> _translateBaidu(String source) async {
    final appId = _required(settings.appId, 'APP ID');
    final secret = _required(settings.appSecret, '密钥');
    final salt = DateTime.now().microsecondsSinceEpoch.toString();
    final sign = md5
        .convert(utf8.encode('$appId$source$salt$secret'))
        .toString();
    final decoded = await _postForm(_endpoint(), {
      'q': source,
      'from': _providerLanguage(settings.sourceLanguage, target: false),
      'to': _providerLanguage(settings.targetLanguage, target: true),
      'appid': appId,
      'salt': salt,
      'sign': sign,
    });
    if (decoded is Map && decoded['error_code'] != null) {
      throw FormatException(
        '百度错误 ${decoded['error_code']}: ${decoded['error_msg'] ?? ''}',
      );
    }
    final results = decoded is Map ? decoded['trans_result'] : null;
    if (results is List) {
      return results
          .whereType<Map>()
          .map((item) => item['dst']?.toString())
          .whereType<String>()
          .join('\n')
          .trim();
    }
    return null;
  }

  Future<String?> _translateYoudao(String source) async {
    final appId = _required(settings.appId, '应用 ID');
    final secret = _required(settings.appSecret, '应用密钥');
    final now = DateTime.now();
    final salt = now.microsecondsSinceEpoch.toString();
    final curtime = (now.millisecondsSinceEpoch ~/ 1000).toString();
    final input = source.length <= 20
        ? source
        : '${source.substring(0, 10)}${source.length}'
              '${source.substring(source.length - 10)}';
    final sign = sha256
        .convert(utf8.encode('$appId$input$salt$curtime$secret'))
        .toString();
    final decoded = await _postForm(_endpoint(), {
      'q': source,
      'from': _providerLanguage(settings.sourceLanguage, target: false),
      'to': _providerLanguage(settings.targetLanguage, target: true),
      'appKey': appId,
      'salt': salt,
      'sign': sign,
      'signType': 'v3',
      'curtime': curtime,
    });
    if (decoded is Map && decoded['errorCode']?.toString() != '0') {
      throw FormatException('有道错误 ${decoded['errorCode']}');
    }
    final translations = decoded is Map ? decoded['translation'] : null;
    if (translations is List) {
      return translations.map((item) => item.toString()).join('\n').trim();
    }
    return null;
  }

  Uri _endpoint() {
    final raw = settings.endpoint.trim().isEmpty
        ? settings.provider.defaultEndpoint
        : settings.endpoint.trim();
    final endpoint = Uri.tryParse(raw);
    if (endpoint == null || !endpoint.hasScheme || !endpoint.hasAuthority) {
      throw const FormatException('翻译 API 地址无效');
    }
    return endpoint;
  }

  String _systemPrompt(String? ruby) {
    final rubyContext = ruby == null || ruby.isEmpty
        ? ''
        : ' The source span has ruby reading "$ruby"; translate only the base '
              'text and do not repeat the ruby reading.';
    return 'Translate visual novel dialogue from ${settings.sourceLanguage} '
        'to ${settings.targetLanguage}. Preserve names, punctuation, line '
        'breaks, formatting markers, and control-like tokens.$rubyContext '
        'Return only the translated text.';
  }

  String _providerLanguage(String raw, {required bool target}) {
    final canonical = _canonicalLanguage(raw);
    return switch (settings.provider) {
      TranslationProvider.deepL => switch (canonical) {
        'auto' => 'AUTO',
        'zh-CN' => target ? 'ZH-HANS' : 'ZH',
        'zh-TW' => target ? 'ZH-HANT' : 'ZH',
        'en' => target ? 'EN-US' : 'EN',
        _ => canonical.toUpperCase(),
      },
      TranslationProvider.baidu => switch (canonical) {
        'ja' => 'jp',
        'zh-CN' => 'zh',
        'zh-TW' => 'cht',
        _ => canonical,
      },
      TranslationProvider.youdao => switch (canonical) {
        'zh-CN' => 'zh-CHS',
        'zh-TW' => 'zh-CHT',
        _ => canonical,
      },
      _ => canonical,
    };
  }

  static String _canonicalLanguage(String raw) {
    return switch (raw.trim().toLowerCase()) {
      'auto' || '自动' || '自动检测' => 'auto',
      'ja' || 'jp' || '日语' || '日本語' || 'japanese' => 'ja',
      'zh' ||
      'zh-cn' ||
      'zh-hans' ||
      'zh-chs' ||
      '中文' ||
      '简体中文' ||
      'chinese' => 'zh-CN',
      'zh-tw' || 'zh-hant' || 'zh-cht' || '繁体中文' => 'zh-TW',
      'en' || '英语' || '英文' || 'english' => 'en',
      'ko' || '韩语' || '朝鲜语' || 'korean' => 'ko',
      'fr' || '法语' || 'french' => 'fr',
      'de' || '德语' || 'german' => 'de',
      'es' || '西班牙语' || 'spanish' => 'es',
      'ru' || '俄语' || 'russian' => 'ru',
      'pt' || '葡萄牙语' || 'portuguese' => 'pt',
      final value => value,
    };
  }

  Future<dynamic> _postJson(
    Uri endpoint,
    Map<String, dynamic> body, {
    Map<String, String> headers = const {},
  }) async {
    final request = await client
        .postUrl(endpoint)
        .timeout(const Duration(seconds: 15));
    request.headers.contentType = ContentType.json;
    headers.forEach(request.headers.set);
    request.write(jsonEncode(body));
    return _readResponse(request, endpoint);
  }

  Future<dynamic> _postForm(Uri endpoint, Map<String, String> fields) async {
    final request = await client
        .postUrl(endpoint)
        .timeout(const Duration(seconds: 15));
    request.headers.contentType = ContentType(
      'application',
      'x-www-form-urlencoded',
      charset: 'utf-8',
    );
    request.write(Uri(queryParameters: fields).query);
    return _readResponse(request, endpoint);
  }

  Future<dynamic> _readResponse(HttpClientRequest request, Uri endpoint) async {
    final response = await request.close().timeout(const Duration(seconds: 60));
    final body = await utf8.decoder.bind(response).join();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        'HTTP ${response.statusCode}: ${_shorten(body, 400)}',
        uri: endpoint,
      );
    }
    try {
      return jsonDecode(body);
    } on FormatException {
      throw FormatException('API 返回的不是 JSON: ${_shorten(body, 200)}');
    }
  }

  static void _throwApiError(dynamic decoded) {
    if (decoded is! Map || decoded['error'] == null) return;
    final error = decoded['error'];
    if (error is Map) {
      throw FormatException(
        '${error['type'] ?? error['code'] ?? 'API error'}: '
        '${error['message'] ?? error}',
      );
    }
    throw FormatException(error.toString());
  }

  static String? _extractOpenAi(dynamic decoded) {
    if (decoded is! Map) return null;
    final direct = decoded['output_text'];
    if (direct is String) return direct.trim();

    final choices = decoded['choices'];
    if (choices is List && choices.isNotEmpty && choices.first is Map) {
      final message = (choices.first as Map)['message'];
      if (message is Map && message['content'] is String) {
        return (message['content'] as String).trim();
      }
      if ((choices.first as Map)['text'] is String) {
        return ((choices.first as Map)['text'] as String).trim();
      }
    }

    final output = decoded['output'];
    if (output is List) {
      for (final item in output) {
        if (item is! Map || item['content'] is! List) continue;
        for (final content in item['content'] as List) {
          if (content is Map && content['text'] is String) {
            return (content['text'] as String).trim();
          }
        }
      }
    }
    return null;
  }

  static String _required(String value, String field) {
    final result = value.trim();
    if (result.isEmpty) throw FormatException('$field 未填写');
    return result;
  }

  static String _decodeHtmlEntities(String value) {
    return value
        .replaceAllMapped(RegExp(r'&#(x?[0-9A-Fa-f]+);'), (match) {
          final raw = match.group(1)!;
          final radix = raw.startsWith('x') ? 16 : 10;
          final digits = raw.startsWith('x') ? raw.substring(1) : raw;
          final codePoint = int.tryParse(digits, radix: radix);
          return codePoint == null
              ? match.group(0)!
              : String.fromCharCode(codePoint);
        })
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&apos;', "'")
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&amp;', '&');
  }

  static String _shorten(String value, int maxLength) {
    return value.length <= maxLength
        ? value
        : '${value.substring(0, maxLength)}...';
  }
}
