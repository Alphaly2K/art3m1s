import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/game_entry.dart';
import '../models/input_gate.dart';
import '../services/game_importer.dart';
import '../services/game_manifest.dart';
import '../services/logger.dart';
import '../services/storage_service.dart';

final storageServiceProvider = Provider<StorageService>((ref) {
  return StorageService.instance;
});

final libraryProvider = StateNotifierProvider<LibraryNotifier, List<GameEntry>>(
  (ref) {
    final storage = ref.read(storageServiceProvider);
    return LibraryNotifier(storage);
  },
);

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
        final sandboxPath = await GameImporter.importToSandbox(
          entry.path,
          gameId: entry.id,
        );
        if (sandboxPath != entry.path) {
          finalEntry = GameEntry(
            id: entry.id,
            name: entry.name,
            path: sandboxPath,
            source: entry.source,
            addedAt: entry.addedAt,
            displayName: entry.displayName,
            coverPath: entry.coverPath,
            translationEnabled: entry.translationEnabled,
            translationPatchPath: entry.translationPatchPath,
            environmentPatchEnabled: entry.environmentPatchEnabled,
            experimentalElunaEnabled: entry.experimentalElunaEnabled,
            inputGate: entry.inputGate,
            vndbId: entry.vndbId,
            fontOverridePath: entry.fontOverridePath,
            reportedOs: entry.reportedOs,
            runtimePlatform: entry.runtimePlatform,
            manifestPath: null,
          );
          Log.info('[Library] 已切换到沙箱路径: $sandboxPath');
        }
      } catch (e) {
        Log.error('[Library] 沙箱导入失败: $e');
        // 回退到原路径 —— 可能能工作，也可能不行，由用户承担。
      }
    }
    try {
      final manifestPath = await GameManifest.writeForProject(
        finalEntry.path,
        finalEntry.source,
        GameManifest.fromGameEntry(finalEntry),
      );
      finalEntry = finalEntry.copyWith(manifestPath: manifestPath);
    } catch (e) {
      Log.warn('[Library] 游戏 manifest 保存失败: $e');
    }
    await _storage.addToLibrary(finalEntry);
    state = _storage.getLibrary();
  }

  Future<void> remove(String path) async {
    // Android 导入副本随项目一起删；iOS 只移除资料库条目，不删 Files 里的游戏。
    try {
      final retainedPaths = state
          .where((game) => !GameImporter.isSameLibraryPath(game.path, path))
          .map((game) => game.path);
      await GameImporter.removeImportedGameFiles(
        path,
        retainedPaths: retainedPaths,
      );
    } catch (e) {
      debugPrint('[Library] 导入文件清理失败: $e');
    }
    await _storage.removeFromLibrary(path);
    state = _storage.getLibrary();
  }

  Future<void> update(
    String path, {
    String? displayName,
    String? coverPath,
    bool? translationEnabled,
    String? translationPatchPath,
    bool? environmentPatchEnabled,
    bool? experimentalElunaEnabled,
    InputGatePolicy? inputGate,
    String? reportedOs,
    String? runtimePlatform,
  }) async {
    final lib = _storage.getLibrary();
    final i = lib.indexWhere((g) => g.path == path);
    if (i < 0) return;
    final updated = lib[i].copyWith(
      displayName: displayName,
      coverPath: coverPath,
      translationEnabled: translationEnabled,
      translationPatchPath: translationPatchPath,
      environmentPatchEnabled: environmentPatchEnabled,
      experimentalElunaEnabled: experimentalElunaEnabled,
      inputGate: inputGate,
      reportedOs: reportedOs,
      runtimePlatform: runtimePlatform,
    );
    try {
      final manifestPath = await GameManifest.writeForProject(
        updated.path,
        updated.source,
        GameManifest.fromGameEntry(updated),
        manifestPath: updated.manifestPath,
      );
      lib[i] = updated.copyWith(manifestPath: manifestPath);
    } catch (e) {
      Log.warn('[Library] 游戏 manifest 保存失败: $e');
      lib[i] = updated;
    }
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
