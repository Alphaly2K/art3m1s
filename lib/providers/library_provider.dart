import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/game_entry.dart';
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

  Future<void> add(GameEntry entry) async {
    await _storage.addToLibrary(entry);
    state = _storage.getLibrary();
  }

  Future<void> remove(String path) async {
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
