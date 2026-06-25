import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/game_entry.dart';
import '../services/game_importer.dart';
import '../services/logger.dart';
import '../services/storage_service.dart';

final storageServiceProvider = Provider<StorageService>((ref) {
  return StorageService.instance;
});

final libraryProvider = StateNotifierProvider<LibraryNotifier, List<GameEntry>>((ref) {
  final storage = ref.read(storageServiceProvider);
  return LibraryNotifier(storage);
});

class LibraryNotifier extends StateNotifier<List<GameEntry>> {
  final StorageService _storage;

  LibraryNotifier(this._storage) : super(_storage.getLibrary());

  /// 添加游戏到库。
  ///
  /// 移动平台 (Android/iOS) 会先把游戏数据复制到应用沙箱，
  /// 让 native 代码能直接通过文件路径读取（绕过 Scoped Storage / iOS 沙箱限制）。
  Future<void> add(GameEntry entry) async {
    var finalEntry = entry;
    if (GameImporter.needsSandbox) {
      try {
        final sandboxPath = await GameImporter.importToSandbox(entry.path);
        if (sandboxPath != entry.path) {
          finalEntry = GameEntry(
            name: entry.name,
            path: sandboxPath,
            source: entry.source,
            addedAt: entry.addedAt,
            displayName: entry.displayName,
            coverPath: entry.coverPath,
          );
          Log.info('[Library] 已切换到沙箱路径: $sandboxPath');
        }
      } catch (e) {
        Log.error('[Library] 沙箱导入失败: $e');
        // 回退到原路径 —— 可能能工作，也可能不行，由用户承担。
      }
    }
    await _storage.addToLibrary(finalEntry);
    state = _storage.getLibrary();
  }

  Future<void> remove(String path) async {
    // 清理沙箱副本（如果存在）。
    if (GameImporter.needsSandbox) {
      try {
        await GameImporter.removeFromSandbox(path);
      } catch (e) {
        debugPrint('[Library] 沙箱清理失败: $e');
      }
    }
    await _storage.removeFromLibrary(path);
    state = _storage.getLibrary();
  }

  Future<void> update(String path, {String? displayName, String? coverPath}) async {
    final lib = _storage.getLibrary();
    final i = lib.indexWhere((g) => g.path == path);
    if (i < 0) return;
    final updated = lib[i].copyWith(
      displayName: displayName,
      coverPath: coverPath,
    );
    lib[i] = updated;
    await _storage.saveLibrary(lib);
    state = lib;
  }

  Future<void> markPlayed(String path) async {
    await _storage.updateLastPlayed(path);
    state = _storage.getLibrary();
  }

  void refresh() {
    state = _storage.getLibrary();
  }
}
