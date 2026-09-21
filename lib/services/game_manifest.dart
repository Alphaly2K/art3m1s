import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../engine/engine_archive.dart';
import '../models/game_engine.dart';
import '../models/game_entry.dart';
import '../models/input_gate.dart';
import 'logger.dart';

/// 项目清单（manifest）：游戏目录或 PFS 归档内的 `art3m1s.json`，记录游戏信息
/// 与宿主侧默认配置——VNDB ID、功能开关默认值、覆盖字体与输入门控。
///
/// 发现规则：启动时优先读取游戏目录根部（或 PFS 旁）的宿主清单；没有宿主清单时，
/// 才在归档/目录内按路径深度至多两级（根目录与一级子目录）查找旧的
/// `art3m1s.json`（文件名不区分大小写）。直接清单是用户配置的权威来源，旧的包内
/// 清单只负责首次导入时提供默认值。
///
/// 示例：
/// ```json
/// {
///   "name": "NekoMiko",
///   "vndbId": "v23658",
///   "engine": "art3m1s",
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
    this.engine,
    this.translationEnabled,
    this.translationPatchPath,
    this.environmentPatchEnabled,
    this.experimentalElunaEnabled,
    this.fontOverride,
    this.inputGate,
    this.reportedOs,
    this.runtimePlatform,
    this.krkrEntryXp3,
  });

  static const defaultRuntimePlatform = 'WINDOWS';

  /// 游戏名（导入时预填显示名）。
  final String? name;

  /// VNDB ID（如 `v23658`），导入时用于精确查询标题/封面。
  final String? vndbId;

  /// 项目使用的底层引擎。缺省时保持旧版 Artemis core。
  final GameEngineKind? engine;

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

  /// system.ini 使用的启动段。它属于单个游戏，不能由宿主全局偏好覆盖。
  final String? runtimePlatform;

  /// KRKR 启动 XP3 的根目录文件名，保持游戏目录作为库条目的身份。
  final String? krkrEntryXp3;

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
      engine: json['engine'] == null
          ? null
          : GameEngineKind.fromId(json['engine']),
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
      runtimePlatform: optionalString('runtimePlatform')?.toUpperCase(),
      krkrEntryXp3: optionalString('krkrEntryXp3'),
    );
  }

  /// 该键是否属于指定引擎的能力范围;通用键(name/vndbId/engine)总是允许。
  static bool _supports(GameEngineKind? engine, GameSettingField field) {
    return (engine ?? GameEngineKind.art3m1s).supportedGameSettings.contains(
      field,
    );
  }

  Map<String, dynamic> toJson() {
    // 只写当前引擎支持的键:引擎不支持的开关留在清单里只会误导。
    // engine 本身永远写入真实 id,不再省略。
    final kind = engine;
    return {
      if (name != null && name!.isNotEmpty) 'name': name,
      if (vndbId != null && vndbId!.isNotEmpty) 'vndbId': vndbId,
      if (kind != null) 'engine': kind.id,
      if (_supports(kind, GameSettingField.translationEnabled) &&
          translationEnabled != null)
        'translationEnabled': translationEnabled,
      if (_supports(kind, GameSettingField.translationPatchPath) &&
          translationPatchPath != null &&
          translationPatchPath!.isNotEmpty)
        'translationPatchPath': translationPatchPath,
      if (_supports(kind, GameSettingField.environmentPatch) &&
          environmentPatchEnabled != null)
        'environmentPatchEnabled': environmentPatchEnabled,
      if (_supports(kind, GameSettingField.experimentalEluna) &&
          experimentalElunaEnabled != null)
        'experimentalElunaEnabled': experimentalElunaEnabled,
      if (_supports(kind, GameSettingField.fontOverride) &&
          fontOverride != null &&
          fontOverride!.isNotEmpty)
        'fontOverride': fontOverride,
      if (_supports(kind, GameSettingField.inputGate) &&
          inputGate != null &&
          !inputGate!.isFull)
        'inputGate': inputGate!.toJson(),
      if (_supports(kind, GameSettingField.reportedOs) &&
          reportedOs != null &&
          reportedOs!.isNotEmpty)
        'reportedOs': reportedOs,
      if (_supports(kind, GameSettingField.runtimePlatform) &&
          runtimePlatform != null &&
          runtimePlatform!.isNotEmpty)
        'runtimePlatform': runtimePlatform!.toUpperCase(),
      if (_supports(kind, GameSettingField.krkrEntryXp3) &&
          krkrEntryXp3 != null &&
          krkrEntryXp3!.isNotEmpty)
        'krkrEntryXp3': krkrEntryXp3,
    };
  }

  factory GameManifest.fromGameEntry(GameEntry entry) => GameManifest(
    name: entry.displayNameOrName,
    vndbId: entry.vndbId.isEmpty ? null : entry.vndbId,
    engine: entry.engine,
    translationEnabled: entry.translationEnabled,
    translationPatchPath: entry.translationPatchPath,
    environmentPatchEnabled: entry.environmentPatchEnabled,
    experimentalElunaEnabled: entry.experimentalElunaEnabled,
    fontOverride: entry.fontOverridePath.isEmpty
        ? null
        : entry.fontOverridePath,
    inputGate: entry.inputGate,
    reportedOs: entry.reportedOs.isEmpty ? null : entry.reportedOs,
    runtimePlatform: entry.runtimePlatform,
    krkrEntryXp3: entry.krkrEntryXp3.isEmpty ? null : entry.krkrEntryXp3,
  );

  GameEntry applyTo(GameEntry entry, {String? manifestPath}) {
    // 按条目引擎过滤:RFVP 等引擎不支持的字段即使在旧清单里存在也不应用。
    final kind = engine ?? entry.engine;
    return entry.copyWith(
      displayName: name ?? entry.displayName,
      translationEnabled: _supports(kind, GameSettingField.translationEnabled)
          ? translationEnabled ?? entry.translationEnabled
          : entry.translationEnabled,
      translationPatchPath:
          _supports(kind, GameSettingField.translationPatchPath)
          ? translationPatchPath ?? entry.translationPatchPath
          : entry.translationPatchPath,
      environmentPatchEnabled:
          _supports(kind, GameSettingField.environmentPatch)
          ? environmentPatchEnabled ?? entry.environmentPatchEnabled
          : entry.environmentPatchEnabled,
      experimentalElunaEnabled:
          _supports(kind, GameSettingField.experimentalEluna)
          ? experimentalElunaEnabled ?? entry.experimentalElunaEnabled
          : entry.experimentalElunaEnabled,
      inputGate: _supports(kind, GameSettingField.inputGate)
          ? inputGate ?? entry.inputGate
          : entry.inputGate,
      vndbId: vndbId ?? entry.vndbId,
      engine: engine ?? entry.engine,
      fontOverridePath: _supports(kind, GameSettingField.fontOverride)
          ? fontOverride ?? entry.fontOverridePath
          : entry.fontOverridePath,
      reportedOs: _supports(kind, GameSettingField.reportedOs)
          ? reportedOs ?? entry.reportedOs
          : entry.reportedOs,
      runtimePlatform: _supports(kind, GameSettingField.runtimePlatform)
          ? runtimePlatform ?? entry.runtimePlatform
          : entry.runtimePlatform,
      krkrEntryXp3: _supports(kind, GameSettingField.krkrEntryXp3)
          ? krkrEntryXp3 ?? entry.krkrEntryXp3
          : entry.krkrEntryXp3,
      manifestPath: manifestPath ?? entry.manifestPath,
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
    GameSource source, {
    GameEngineKind engine = GameEngineKind.art3m1s,
  }) async {
    try {
      return switch (source) {
        GameSource.directory => await _discoverDirectory(projectPath),
        GameSource.pfsArchive => await _discoverPfs(projectPath, engine),
      };
    } catch (error) {
      Log.warn('[Manifest] 清单发现失败 ($projectPath): $error');
      return null;
    }
  }

  /// 返回宿主保存配置的直接路径。PFS 不可原地修改，因此使用归档旁的 sidecar。
  static String manifestPathFor(String projectPath, GameSource source) {
    return switch (source) {
      GameSource.directory => '$projectPath${Platform.pathSeparator}$fileName',
      GameSource.pfsArchive => '$projectPath.$fileName',
    };
  }

  static Future<GameManifest?> loadFromPath(String path) async {
    final file = File(path);
    if (!await file.exists()) return null;
    try {
      return parse(await file.readAsBytes());
    } catch (error) {
      Log.warn('[Manifest] 读取清单失败 ($path): $error');
      return null;
    }
  }

  /// 直接读取宿主保存的 manifest；没有 sidecar 时才回退到游戏包内的旧清单。
  static Future<GameManifest?> loadForProject(
    String projectPath,
    GameSource source, {
    String? manifestPath,
    GameEngineKind engine = GameEngineKind.art3m1s,
  }) async {
    final direct = await loadFromPath(
      manifestPath ?? manifestPathFor(projectPath, source),
    );
    return direct ?? await discover(projectPath, source, engine: engine);
  }

  static Future<String> writeForProject(
    String projectPath,
    GameSource source,
    GameManifest manifest, {
    String? manifestPath,
  }) async {
    final path = manifestPath ?? manifestPathFor(projectPath, source);
    final file = File(path);
    await file.parent.create(recursive: true);
    await file.writeAsString(
      '${JsonEncoder.withIndent('  ').convert(manifest.toJson())}\n',
    );
    Log.info('[Manifest] 已保存游戏清单: $path');
    return path;
  }

  static Future<GameEntry> loadEntrySettings(GameEntry entry) async {
    final path =
        entry.manifestPath ?? manifestPathFor(entry.path, entry.source);
    final manifest = await loadForProject(
      entry.path,
      entry.source,
      manifestPath: path,
      engine: entry.engine,
    );
    return manifest?.applyTo(entry, manifestPath: path) ??
        entry.copyWith(manifestPath: path);
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

  static Future<GameManifest?> _discoverPfs(
    String archivePath,
    GameEngineKind engine,
  ) async {
    final entries = await EngineArchive.listEntries(
      engine: engine,
      archivePath: archivePath,
    );
    final selected = selectManifestPath(entries);
    if (selected == null) return null;
    final bytes = await EngineArchive.readFile(
      engine: engine,
      archivePath: archivePath,
      relativePath: selected,
    );
    return bytes == null ? null : parse(bytes);
  }

  /// 读取游戏内文件的绝对字节：目录直接读，PFS 走归档读取。
  /// 供启动时装载清单指定的覆盖字体等资源。失败返回 null。
  static Future<Uint8List?> readGameFile(
    String projectPath,
    GameSource source,
    String relativePath, {
    GameEngineKind engine = GameEngineKind.art3m1s,
  }) async {
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
          engine,
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
    GameEngineKind engine,
  ) async {
    return EngineArchive.readFile(
      engine: engine,
      archivePath: archivePath,
      relativePath: relativePath,
    );
  }

  static String _basename(String path) {
    final normalized = path.replaceAll('\\', '/');
    return normalized.substring(normalized.lastIndexOf('/') + 1);
  }
}
