import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'game_engine.dart';
import 'input_gate.dart';

class GameEntry {
  /// 资料库内部的稳定身份。资源路径和显示名都可变化，存档/封面等仍按此 ID 隔离。
  final String id;
  final String name;
  final String path;
  final GameSource source;
  final GameEngineKind engine;
  final DateTime addedAt;
  final DateTime? lastPlayedAt;
  final String? displayName;
  final String? coverPath;
  final bool translationEnabled;
  final String translationPatchPath;
  final bool environmentPatchEnabled;
  final bool experimentalElunaEnabled;

  /// 输入门控策略（环境/平台特化的输入过滤与转发），默认全放行。
  /// 项目补丁可经 JSON 携带自定义规则。
  final InputGatePolicy inputGate;

  /// VNDB ID（如 `v23658`），由项目清单提供；空串表示未知。
  final String vndbId;

  /// 项目清单指定的覆盖字体（游戏内相对路径）；空串表示无。
  final String fontOverridePath;

  /// 上报给脚本的机种串覆盖（如 `switch`/`ps4`）；空串表示跟随项目平台。
  /// 移植版游戏把存档等功能开关在机种判断上时用它伪装。
  final String reportedOs;

  /// system.ini 使用的启动段；这是游戏自己的配置，不是宿主全局设置。
  final String runtimePlatform;

  /// 游戏配置 manifest 的直接路径。目录项目为根目录下的 art3m1s.json，
  /// PFS 项目为归档旁的 sidecar 文件。
  final String? manifestPath;

  GameEntry({
    String? id,
    required this.name,
    required this.path,
    required this.source,
    this.engine = GameEngineKind.art3m1s,
    required this.addedAt,
    this.lastPlayedAt,
    this.displayName,
    this.coverPath,
    this.translationEnabled = false,
    this.translationPatchPath = '',
    this.environmentPatchEnabled = false,
    this.experimentalElunaEnabled = false,
    this.inputGate = InputGatePolicy.full,
    this.vndbId = '',
    this.fontOverridePath = '',
    this.reportedOs = '',
    this.runtimePlatform = 'WINDOWS',
    this.manifestPath,
  }) : id = _normalizeId(id, path);

  String get displayNameOrName => displayName ?? name;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'path': path,
    'source': source.name,
    'engine': engine.id,
    'addedAt': addedAt.toIso8601String(),
    'lastPlayedAt': lastPlayedAt?.toIso8601String(),
    'displayName': displayName,
    'coverPath': coverPath,
    'translationEnabled': translationEnabled,
    'translationPatchPath': translationPatchPath,
    'environmentPatchEnabled': environmentPatchEnabled,
    'experimentalElunaEnabled': experimentalElunaEnabled,
    // 全放行默认不落盘，保持旧资料库 JSON 干净；fromJson 缺字段即回默认。
    if (!inputGate.isFull) 'inputGate': inputGate.toJson(),
    if (vndbId.isNotEmpty) 'vndbId': vndbId,
    if (fontOverridePath.isNotEmpty) 'fontOverridePath': fontOverridePath,
    if (reportedOs.isNotEmpty) 'reportedOs': reportedOs,
    'runtimePlatform': runtimePlatform,
    if (manifestPath != null) 'manifestPath': manifestPath,
  };

  factory GameEntry.fromJson(Map<String, dynamic> json) => GameEntry(
    id: json['id'] as String?,
    name: json['name'] as String,
    path: json['path'] as String,
    source: GameSource.values.byName(json['source'] as String),
    engine: GameEngineKind.fromId(json['engine']),
    addedAt: DateTime.parse(json['addedAt'] as String),
    lastPlayedAt: json['lastPlayedAt'] != null
        ? DateTime.parse(json['lastPlayedAt'] as String)
        : null,
    displayName: json['displayName'] as String?,
    coverPath: json['coverPath'] as String?,
    translationEnabled: json['translationEnabled'] == true,
    translationPatchPath: json['translationPatchPath']?.toString() ?? '',
    environmentPatchEnabled: json['environmentPatchEnabled'] == true,
    experimentalElunaEnabled: json['experimentalElunaEnabled'] == true,
    inputGate: InputGatePolicy.fromJson(
      (json['inputGate'] as Map?)?.cast<String, dynamic>(),
    ),
    vndbId: json['vndbId']?.toString() ?? '',
    fontOverridePath: json['fontOverridePath']?.toString() ?? '',
    reportedOs: json['reportedOs']?.toString() ?? '',
    runtimePlatform:
        json['runtimePlatform']?.toString().trim().isNotEmpty == true
        ? json['runtimePlatform'].toString().trim().toUpperCase()
        : 'WINDOWS',
    manifestPath: json['manifestPath']?.toString(),
  );

  GameEntry copyWith({
    DateTime? lastPlayedAt,
    String? displayName,
    String? coverPath,
    GameEngineKind? engine,
    bool? translationEnabled,
    String? translationPatchPath,
    bool? environmentPatchEnabled,
    bool? experimentalElunaEnabled,
    InputGatePolicy? inputGate,
    String? vndbId,
    String? fontOverridePath,
    String? reportedOs,
    String? runtimePlatform,
    String? manifestPath,
  }) => GameEntry(
    id: id,
    name: name,
    path: path,
    source: source,
    engine: engine ?? this.engine,
    addedAt: addedAt,
    lastPlayedAt: lastPlayedAt ?? this.lastPlayedAt,
    displayName: displayName ?? this.displayName,
    coverPath: coverPath ?? this.coverPath,
    translationEnabled: translationEnabled ?? this.translationEnabled,
    translationPatchPath: translationPatchPath ?? this.translationPatchPath,
    environmentPatchEnabled:
        environmentPatchEnabled ?? this.environmentPatchEnabled,
    experimentalElunaEnabled:
        experimentalElunaEnabled ?? this.experimentalElunaEnabled,
    inputGate: inputGate ?? this.inputGate,
    vndbId: vndbId ?? this.vndbId,
    fontOverridePath: fontOverridePath ?? this.fontOverridePath,
    reportedOs: reportedOs ?? this.reportedOs,
    runtimePlatform: runtimePlatform ?? this.runtimePlatform,
    manifestPath: manifestPath ?? this.manifestPath,
  );

  static String _normalizeId(String? id, String path) {
    final cleaned = (id ?? '').replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '');
    return cleaned.isNotEmpty ? cleaned : legacyIdForPath(path);
  }

  /// 旧前端实际使用过的存档目录名，仅用于无冲突资料库的兼容迁移。
  static String legacySaveIdForPath(String path) {
    final normalized = path
        .replaceAll('\\', '/')
        .replaceAll(RegExp(r'/+$'), '');
    final segments = normalized.split('/').where((part) => part.isNotEmpty);
    final basename = segments.isEmpty ? '' : segments.last;
    final cleaned = basename.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    if (cleaned.isNotEmpty) return cleaned;
    return legacyIdForPath(path);
  }

  /// 旧资料库没有 ID 时按完整路径生成稳定兼容值。
  ///
  /// 不能只取 basename：不同目录下的 root.pfs 必须得到不同身份。
  static String legacyIdForPath(String path) {
    final normalized = path.replaceAll('\\', '/');
    final digest = sha256.convert(utf8.encode(normalized)).toString();
    return 'legacy_${digest.substring(0, 16)}';
  }
}

enum GameSource { directory, pfsArchive }
