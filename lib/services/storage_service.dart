import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/game_entry.dart';

class StorageService {
  static const _libraryKey = 'game_library';
  static StorageService? _instance;
  SharedPreferences? _prefs;

  StorageService._();

  static StorageService get instance {
    _instance ??= StorageService._();
    return _instance!;
  }

  static Future<void> ensureInitialized() async {
    if (instance._prefs != null) return;
    instance._prefs = await SharedPreferences.getInstance();
    await instance._migrateLibraryIds();
  }

  /// 旧版条目没有独立 ID。无 basename 冲突时沿用旧存档目录；冲突项才按
  /// 完整路径分配隔离 ID。迁移结果立即写回，后续不再受映射规则变化影响。
  Future<void> _migrateLibraryIds() async {
    final raw = _prefs?.getString(_libraryKey);
    if (raw == null) return;
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      final needsMigration = decoded.any(
        (entry) =>
            entry is Map &&
            (entry['id'] == null || entry['id'].toString().trim().isEmpty),
      );
      if (!needsMigration) return;
      final entries = decoded
          .map(
            (entry) =>
                Map<String, dynamic>.from(entry as Map<dynamic, dynamic>),
          )
          .toList();
      final legacyIdCounts = <String, int>{};
      for (final entry in entries) {
        final path = entry['path'] as String;
        final legacyId = GameEntry.legacySaveIdForPath(path);
        legacyIdCounts[legacyId] = (legacyIdCounts[legacyId] ?? 0) + 1;
      }
      final library = entries.map((entry) {
        final persistedId = entry['id']?.toString().trim() ?? '';
        if (persistedId.isEmpty) {
          final path = entry['path'] as String;
          final legacyId = GameEntry.legacySaveIdForPath(path);
          entry['id'] = legacyIdCounts[legacyId] == 1
              ? legacyId
              : GameEntry.legacyIdForPath(path);
        }
        return GameEntry.fromJson(entry);
      }).toList();
      await _saveLibrary(library);
    } catch (_) {
      // 保持 getLibrary 的既有兼容行为：损坏数据由读取端返回空库，不在迁移时覆盖。
    }
  }

  List<GameEntry> getLibrary() {
    final json = _prefs?.getString(_libraryKey);
    if (json == null) return [];

    try {
      final list = jsonDecode(json) as List<dynamic>;
      return list
          .map((e) => GameEntry.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> addToLibrary(GameEntry entry) async {
    final library = getLibrary();
    library.removeWhere((g) => g.path == entry.path);
    library.add(entry);
    await _saveLibrary(library);
  }

  Future<void> removeFromLibrary(String path) async {
    final library = getLibrary();
    library.removeWhere((g) => g.path == path);
    await _saveLibrary(library);
  }

  Future<void> updateLastPlayed(String path) async {
    final library = getLibrary();
    final index = library.indexWhere((g) => g.path == path);
    if (index >= 0) {
      library[index] = library[index].copyWith(lastPlayedAt: DateTime.now());
      await _saveLibrary(library);
    }
  }

  bool isInLibrary(String path) {
    return getLibrary().any((g) => g.path == path);
  }

  Future<void> saveLibrary(List<GameEntry> library) async {
    await _saveLibrary(library);
  }

  Future<void> _saveLibrary(List<GameEntry> library) async {
    final json = jsonEncode(library.map((g) => g.toJson()).toList());
    await _prefs?.setString(_libraryKey, json);
  }
}
