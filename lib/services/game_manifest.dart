import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import '../models/game_entry.dart';
import '../models/input_gate.dart';
import 'logger.dart';
import 'pfs_bridge.dart';

/// 项目清单（manifest）：游戏目录或 PFS 归档内的 `art3m1s.json`，记录游戏信息
/// 与宿主侧默认配置——VNDB ID、功能开关默认值、覆盖字体与输入门控。
///
/// 发现规则：在归档/目录内按路径深度至多两级（根目录与一级子目录）查找
/// `art3m1s.json`（文件名不区分大小写），取第一个命中。清单提供的是**默认值**：
/// 导入时种入资料库条目，之后以条目为准，用户仍可在编辑对话框里改。
///
/// 示例：
/// ```json
/// {
///   "name": "NekoMiko",
///   "vndbId": "v23658",
///   "translationEnabled": true,
///   "translationPatchPath": "patch/zh.json",
///   "environmentPatchEnabled": true,
///   "experimentalElunaEnabled": false,
///   "fontOverride": "font/sourcehansans-regular.otf",
///   "inputGate": { "keyboard": false }
/// }
/// ```
class GameManifest {
  const GameManifest({
    this.name,
    this.vndbId,
    this.translationEnabled,
    this.translationPatchPath,
    this.environmentPatchEnabled,
    this.experimentalElunaEnabled,
    this.fontOverride,
    this.inputGate,
    this.reportedOs,
  });

  /// 游戏名（导入时预填显示名）。
  final String? name;

  /// VNDB ID（如 `v23658`），导入时用于精确查询标题/封面。
  final String? vndbId;

  /// 默认功能开关。
  final bool? translationEnabled;
  final bool? environmentPatchEnabled;
  final bool? experimentalElunaEnabled;

  /// 默认翻译对照文件（游戏内相对路径）。
  final String? translationPatchPath;

  /// 默认覆盖字体（游戏内相对路径，TTF/OTF）。
  final String? fontOverride;

  /// 默认输入门控策略（结构见 InputGatePolicy.toJson）。
  final InputGatePolicy? inputGate;

  /// 上报给脚本的机种串覆盖（如 `switch`/`ps4`）。部分移植版游戏把关键
  /// 功能（存档、额外内容）开关在机种判断上，桌面运行时按此伪装。
  final String? reportedOs;

  static const String fileName = 'art3m1s.json';

  /// 从条目相对路径集合里挑清单文件：深度至多两级、文件名不区分大小写。
  /// 纯函数，目录遍历与 PFS 条目列表共用这一判定。
  static String? selectManifestPath(Iterable<String> entryPaths) {
    for (final raw in entryPaths) {
      final normalized = raw.replaceAll('\\', '/');
      final segments = normalized.split('/');
      if (segments.length > 2) continue;
      if (segments.last.toLowerCase() != fileName) continue;
      return normalized;
    }
    return null;
  }

  factory GameManifest.fromJson(Map<String, dynamic> json) {
    bool? optionalBool(String key) =>
        json[key] is bool ? json[key] as bool : null;
    String? optionalString(String key) {
      final value = json[key]?.toString().trim();
      return value == null || value.isEmpty ? null : value;
    }

    return GameManifest(
      name: optionalString('name'),
      vndbId: optionalString('vndbId'),
      translationEnabled: optionalBool('translationEnabled'),
      translationPatchPath: optionalString('translationPatchPath'),
      environmentPatchEnabled: optionalBool('environmentPatchEnabled'),
      experimentalElunaEnabled: optionalBool('experimentalElunaEnabled'),
      fontOverride: optionalString('fontOverride'),
      inputGate: json['inputGate'] is Map
          ? InputGatePolicy.fromJson(
              (json['inputGate'] as Map).cast<String, dynamic>(),
            )
          : null,
      reportedOs: optionalString('reportedOs'),
    );
  }

  /// 解析清单字节；空内容/非 JSON 对象返回 null。
  static GameManifest? parse(Uint8List bytes) {
    try {
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is! Map) return null;
      return GameManifest.fromJson(decoded.cast<String, dynamic>());
    } catch (error) {
      Log.warn('[Manifest] 清单解析失败: $error');
      return null;
    }
  }

  /// 在游戏目录 / PFS 归档内发现清单（至多两级）。找不到或解析失败返回 null。
  static Future<GameManifest?> discover(
    String projectPath,
    GameSource source,
  ) async {
    try {
      return switch (source) {
        GameSource.directory => await _discoverDirectory(projectPath),
        GameSource.pfsArchive => await _discoverPfs(projectPath),
      };
    } catch (error) {
      Log.warn('[Manifest] 清单发现失败 ($projectPath): $error');
      return null;
    }
  }

  static Future<GameManifest?> _discoverDirectory(String root) async {
    final rootDir = Directory(root);
    if (!await rootDir.exists()) return null;
    final candidates = <String>[];
    await for (final entity in rootDir.list(followLinks: false)) {
      if (entity is File) {
        candidates.add(_basename(entity.path));
      } else if (entity is Directory) {
        final prefix = _basename(entity.path);
        await for (final child in entity.list(followLinks: false)) {
          if (child is File) candidates.add('$prefix/${_basename(child.path)}');
        }
      }
    }
    final selected = selectManifestPath(candidates);
    if (selected == null) return null;
    return parse(await File('$root/$selected').readAsBytes());
  }

  static Future<GameManifest?> _discoverPfs(String archivePath) async {
    final bridge = PfsBridge();
    final archive = bridge.open(archivePath);
    if (archive.address == 0) return null;
    try {
      final count = bridge.entryCount(archive);
      if (count <= 0) return null;
      final entries = <String>[
        for (var i = 0; i < count; i++) ?bridge.entryPath(archive, i),
      ];
      final selected = selectManifestPath(entries);
      if (selected == null) return null;
      final bytes = await _readPfsFile(archive, selected);
      if (bytes == null) return null;
      return parse(bytes);
    } finally {
      bridge.close(archive);
    }
  }

  /// 读取游戏内文件的绝对字节：目录直接读，PFS 走归档读取。
  /// 供启动时装载清单指定的覆盖字体等资源。失败返回 null。
  static Future<Uint8List?> readGameFile(
    String projectPath,
    GameSource source,
    String relativePath,
  ) async {
    final normalized = relativePath.replaceAll('\\', '/');
    // 拒绝目录穿越：清单是游戏侧数据，不能借此读游戏目录外的文件。
    if (normalized.split('/').contains('..')) {
      Log.warn('[Manifest] 拒绝越界路径: $relativePath');
      return null;
    }
    try {
      return switch (source) {
        GameSource.directory => await _readDirectoryFile(
          projectPath,
          normalized,
        ),
        GameSource.pfsArchive => await _readPfsFileByName(
          projectPath,
          normalized,
        ),
      };
    } catch (error) {
      Log.warn('[Manifest] 游戏内文件读取失败 ($relativePath): $error');
      return null;
    }
  }

  static Future<Uint8List?> _readDirectoryFile(
    String root,
    String relativePath,
  ) async {
    final file = File('$root/$relativePath');
    if (!await file.exists()) return null;
    return file.readAsBytes();
  }

  static Future<Uint8List?> _readPfsFileByName(
    String archivePath,
    String relativePath,
  ) async {
    final bridge = PfsBridge();
    final archive = bridge.open(archivePath);
    if (archive.address == 0) return null;
    try {
      return await _readPfsFile(archive, relativePath);
    } finally {
      bridge.close(archive);
    }
  }

  static Future<Uint8List?> _readPfsFile(
    Pointer<Void> archive,
    String path,
  ) async {
    final bridge = PfsBridge();
    final size = bridge.fileSize(archive, path);
    if (size <= 0) return null;
    final buf = malloc.allocate<Uint8>(size);
    try {
      final read = bridge.read(archive, path, 0, buf, size);
      if (read <= 0) return null;
      return Uint8List.fromList(buf.asTypedList(read));
    } finally {
      malloc.free(buf);
    }
  }

  static String _basename(String path) {
    final normalized = path.replaceAll('\\', '/');
    return normalized.substring(normalized.lastIndexOf('/') + 1);
  }
}
