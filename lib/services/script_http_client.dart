import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Executes the core's single pending HTTP request and suppresses stale replies.
class ScriptHttpClient {
  ScriptHttpClient({this.timeout = const Duration(seconds: 30)});

  final Duration timeout;
  HttpClient? _client;
  int? _serial;

  void start(
    Map<String, dynamic> payload, {
    required Uint8List? Function(String path) readFile,
    required void Function(int status, Uint8List body) onComplete,
  }) {
    cancel();
    final client = HttpClient()..connectionTimeout = timeout;
    _client = client;
    final serial = payload['serial'];
    _serial = serial is num ? serial.toInt() : null;
    unawaited(_run(client, payload, readFile, onComplete));
  }

  void cancel([int? serial]) {
    if (serial != null && serial != _serial) return;
    _client?.close(force: true);
    _client = null;
    _serial = null;
  }

  Future<void> _run(
    HttpClient client,
    Map<String, dynamic> payload,
    Uint8List? Function(String) readFile,
    void Function(int, Uint8List) onComplete,
  ) async {
    var status = 0;
    var body = Uint8List(0);
    try {
      final uri = Uri.parse(payload['url'] as String);
      if (!{'http', 'https'}.contains(uri.scheme) || uri.host.isEmpty) {
        throw const FormatException('HTTP URL required');
      }
      final method = (payload['method'] as String).toUpperCase();
      if (method != 'GET' && method != 'POST') {
        throw const FormatException('GET or POST required');
      }
      final fields = _pairs(payload['data']);
      for (final entry in _pairs(payload['file_data']).entries) {
        final bytes = readFile(entry.value);
        if (bytes == null) {
          throw const FileSystemException('HTTP form file missing');
        }
        fields[entry.key] = utf8.decode(bytes, allowMalformed: true);
      }
      final request = await client.openUrl(method, uri).timeout(timeout);
      _pairs(payload['headers']).forEach(request.headers.set);
      if (method == 'POST') {
        request.headers.contentType ??= ContentType(
          'application',
          'x-www-form-urlencoded',
          charset: 'utf-8',
        );
        request.write(Uri(queryParameters: fields).query);
      }
      final response = await request.close().timeout(timeout);
      final bytes = BytesBuilder(copy: false);
      await (() async {
        await for (final chunk in response) {
          if (bytes.length + chunk.length > 32 * 1024 * 1024) {
            throw const HttpException('HTTP response too large');
          }
          bytes.add(chunk);
        }
      })().timeout(timeout);
      status = response.statusCode;
      body = bytes.takeBytes();
    } catch (_) {
      // Status zero is the core's failure result, including invalid input.
    } finally {
      client.close(force: true);
    }
    if (!identical(_client, client)) return;
    _client = null;
    _serial = null;
    onComplete(status, body);
  }

  static Map<String, String> _pairs(dynamic value) {
    if (value == null) return {};
    if (value is! List) {
      throw const FormatException('Expected HTTP field pairs');
    }
    return {
      for (final pair in value)
        if (pair is List && pair.length == 2)
          pair[0].toString(): pair[1].toString(),
    };
  }
}
