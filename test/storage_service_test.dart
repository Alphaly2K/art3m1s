import 'dart:convert';

import 'package:art3m1s/models/game_entry.dart';
import 'package:art3m1s/services/storage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'recovers valid records without losing legacy save IDs or damaged data',
    () async {
      final valid = GameEntry(
        name: 'Old game',
        path: '/games/old',
        source: GameSource.directory,
        addedAt: DateTime(2026),
      ).toJson()..remove('id');
      final raw = jsonEncode([
        valid,
        {'name': 'Broken'},
      ]);
      SharedPreferences.setMockInitialValues({'game_library': raw});
      await StorageService.ensureInitialized();
      final library = StorageService.instance.getLibrary();
      expect(library, hasLength(1));
      expect(library.single.id, GameEntry.legacySaveIdForPath('/games/old'));
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('game_library_recovery'), raw);
      await StorageService.instance.updateLastPlayed('/games/old/');
      expect(
        StorageService.instance.getLibrary().single.lastPlayedAt,
        isNotNull,
      );
    },
  );
}
