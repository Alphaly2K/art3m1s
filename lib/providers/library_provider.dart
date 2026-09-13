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
  /// 导入是原地的:全平台都直接登记用户选择的目录/归档路径,不复制
  /// (Android 依赖「所有文件访问」授权,iOS 依赖 App 文件夹)。
  Future<void> add(GameEntry entry) async {
    var finalEntry = entry;
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
    // 原位导入的条目只移除库记录;仅早期 Android 沙箱里的遗留导入副本
    // (托管根白名单内)会随条目一起删除。用户的原始目录绝不动。
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
    String? fontOverrideFilePath,
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
      fontOverrideFilePath: fontOverrideFilePath,
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

  Future<void> setScreenshot(String gameId, String screenshotPath) async {
    final library = _storage.getLibrary();
    final index = library.indexWhere((entry) => entry.id == gameId);
    if (index < 0) return;
    library[index] = library[index].copyWith(screenshotPath: screenshotPath);
    await _storage.saveLibrary(library);
    state = library;
  }

  void refresh() {
    state = _storage.getLibrary();
  }
}
