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

  /// 智能查询：把「脏」标题（caption 常含汉化译名 / 版本号 / 补丁公告，或目录名含
  /// 噪音）切成候选片段、滤掉版本/公告类垃圾，逐段查 VNDB，返回第一个命中的。
  ///
  /// 例：`NekoMiko - 神社里的猫巫女 - Ver 1.0.3H 本汉化补丁仅供学习交流…` →
  /// 候选 `[NekoMiko, 神社里的猫巫女]`（两者 VNDB 都能命中），版本/公告段被丢弃。
  static Future<VndbGameInfo?> lookupGame(String rawTitle) async {
    for (final candidate in _candidateQueries(rawTitle)) {
      final info = await lookup(candidate);
      if (info != null) return info;
    }
    return null;
  }

  /// 把原始标题拆成按优先级排序的候选查询词（去重、滤垃圾、限 3 个）。
  static List<String> _candidateQueries(String raw) {
    final seen = <String>{};
    final out = <String>[];
    void add(String s) {
      final t = s.trim();
      if (t.isEmpty || t.length > 50 || _looksLikeJunk(t)) return;
      if (seen.add(t.toLowerCase())) out.add(t);
    }

    // 常见分隔符：- – — / ~ ｜ | 全角空格，以及各种括号。
    for (final seg in raw.split(
      RegExp(r'\s*[-–—/~｜|　]\s*|[「」『』【】\[\]()（）]'),
    )) {
      add(seg);
    }
    // 一个候选都没有时，退回整串 trim（多半也查不到，但聊胜于无）。
    if (out.isEmpty) add(raw);
    return out.take(3).toList();
  }

  /// 是否是版本号 / 补丁公告等非标题垃圾段。
  static bool _looksLikeJunk(String s) {
    // 版本号：Ver 1.0 / v1.0.3 / 1.0.3H 开头。
    if (RegExp(r'^[vV]er?\.?\s*\d').hasMatch(s)) return true;
    if (RegExp(r'^\d+\.\d').hasMatch(s)) return true;
    const junkWords = [
      '汉化', '補丁', '补丁', '下载', '下載', '删除', '刪除', '学习交流',
      '學習交流', '仅供', '僅供', '请于', '請於', '体験版', '體験版',
      '体验版', 'trial', 'demo', 'デモ', 'patch',
    ];
    final lower = s.toLowerCase();
    return junkWords.any((w) => lower.contains(w.toLowerCase()));
  }

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
