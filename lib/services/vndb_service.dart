import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import 'logger.dart';

/// VNDB（vndb.org）查询结果：标题 + 封面 URL。
class VndbGameInfo {
  const VndbGameInfo({required this.title, this.imageUrl});

  final String title;
  final String? imageUrl;
}

/// VNDB Kana HTTP API 客户端（https://api.vndb.org/kana）。
///
/// 导入游戏时用推导出的游戏名（目录名 / .pfs 文件名，通常是日文/罗马名）作关键词
/// 查询，拿官方标题 + 封面自动预填进「添加项目」对话框。全部 best-effort：任何
/// 网络/解析失败都返回 null，导入回退到手动填名，不打断流程。无第三方依赖，沿用
/// `dart:io HttpClient`（与 text_translation_service 一致）。
class VndbService {
  VndbService._();

  static const String _vnEndpoint = 'https://api.vndb.org/kana/vn';
  static const Duration _timeout = Duration(seconds: 8);

  static final HttpClient _client = HttpClient()
    ..connectionTimeout = _timeout;

  /// 用 [query] 查 VNDB，返回首个匹配的标题 + 封面 URL；无匹配或失败返回 null。
  static Future<VndbGameInfo?> lookup(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return null;
    try {
      final request = await _client
          .postUrl(Uri.parse(_vnEndpoint))
          .timeout(_timeout);
      request.headers.contentType = ContentType.json;
      request.write(
        jsonEncode({
          'filters': ['search', '=', trimmed],
          'fields': 'title, image.url',
          'results': 1,
        }),
      );
      final response = await request.close().timeout(_timeout);
      if (response.statusCode != 200) {
        Log.warn('[VNDB] 查询返回 ${response.statusCode}: $trimmed');
        await response.drain<void>();
        return null;
      }
      final text = await response.transform(utf8.decoder).join();
      final decoded = jsonDecode(text);
      final results = decoded is Map ? decoded['results'] : null;
      if (results is! List || results.isEmpty) return null;
      final first = results.first;
      if (first is! Map) return null;
      final title = first['title']?.toString();
      if (title == null || title.isEmpty) return null;
      final image = first['image'];
      final imageUrl = image is Map ? image['url']?.toString() : null;
      return VndbGameInfo(title: title, imageUrl: imageUrl);
    } catch (e) {
      Log.warn('[VNDB] 查询失败: $e');
      return null;
    }
  }

  /// 下载封面到 app support 的 covers/ 目录，返回本地路径；失败返回 null。
  /// [keyHint] 用来生成稳定文件名（同一游戏重复导入覆盖同一文件）。
  static Future<String?> downloadCover(String imageUrl, String keyHint) async {
    try {
      final request = await _client
          .getUrl(Uri.parse(imageUrl))
          .timeout(_timeout);
      final response = await request.close().timeout(_timeout);
      if (response.statusCode != 200) {
        await response.drain<void>();
        return null;
      }
      final builder = BytesBuilder(copy: false);
      await for (final chunk in response) {
        builder.add(chunk);
      }
      final bytes = builder.takeBytes();
      if (bytes.isEmpty) return null;

      final supportDir = await getApplicationSupportDirectory();
      final coversDir = Directory('${supportDir.path}/covers');
      if (!coversDir.existsSync()) {
        coversDir.createSync(recursive: true);
      }
      final safe = keyHint.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
      final file = File('${coversDir.path}/$safe${_extFromUrl(imageUrl)}');
      await file.writeAsBytes(bytes);
      return file.path;
    } catch (e) {
      Log.warn('[VNDB] 封面下载失败: $e');
      return null;
    }
  }

  static String _extFromUrl(String url) {
    final path = Uri.tryParse(url)?.path ?? url;
    final dot = path.lastIndexOf('.');
    if (dot < 0) return '.jpg';
    final ext = path.substring(dot).toLowerCase();
    const allowed = {'.jpg', '.jpeg', '.png', '.webp', '.bmp', '.gif'};
    return allowed.contains(ext) ? ext : '.jpg';
  }
}
