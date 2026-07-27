import 'dart:convert';

import 'package:crypto/crypto.dart';

class GameEntry {
  /// 资料库内部的稳定身份。资源路径和显示名都可变化，存档/封面等仍按此 ID 隔离。
  final String id;
  final String name;
  final String path;
  final GameSource source;
  final DateTime addedAt;
  final DateTime? lastPlayedAt;
  final String? displayName;
  final String? coverPath;
  final bool translationEnabled;
  final bool environmentPatchEnabled;

  GameEntry({
    String? id,
    required this.name,
    required this.path,
    required this.source,
    required this.addedAt,
    this.lastPlayedAt,
    this.displayName,
    this.coverPath,
    this.translationEnabled = false,
    this.environmentPatchEnabled = false,
  }) : id = _normalizeId(id, path);

  String get displayNameOrName => displayName ?? name;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'path': path,
    'source': source.name,
    'addedAt': addedAt.toIso8601String(),
    'lastPlayedAt': lastPlayedAt?.toIso8601String(),
    'displayName': displayName,
    'coverPath': coverPath,
    'translationEnabled': translationEnabled,
    'environmentPatchEnabled': environmentPatchEnabled,
  };

  factory GameEntry.fromJson(Map<String, dynamic> json) => GameEntry(
    id: json['id'] as String?,
    name: json['name'] as String,
    path: json['path'] as String,
    source: GameSource.values.byName(json['source'] as String),
    addedAt: DateTime.parse(json['addedAt'] as String),
    lastPlayedAt: json['lastPlayedAt'] != null
        ? DateTime.parse(json['lastPlayedAt'] as String)
        : null,
    displayName: json['displayName'] as String?,
    coverPath: json['coverPath'] as String?,
    translationEnabled: json['translationEnabled'] == true,
    environmentPatchEnabled: json['environmentPatchEnabled'] == true,
  );

  GameEntry copyWith({
    DateTime? lastPlayedAt,
    String? displayName,
    String? coverPath,
    bool? translationEnabled,
    bool? environmentPatchEnabled,
  }) => GameEntry(
    id: id,
    name: name,
    path: path,
    source: source,
    addedAt: addedAt,
    lastPlayedAt: lastPlayedAt ?? this.lastPlayedAt,
    displayName: displayName ?? this.displayName,
    coverPath: coverPath ?? this.coverPath,
    translationEnabled: translationEnabled ?? this.translationEnabled,
    environmentPatchEnabled:
        environmentPatchEnabled ?? this.environmentPatchEnabled,
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
