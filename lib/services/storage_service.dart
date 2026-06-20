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
