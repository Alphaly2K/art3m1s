import 'dart:convert';

import 'package:art3m1s/models/game_entry.dart';
import 'package:art3m1s/models/translation_settings.dart';
import 'package:art3m1s/providers/settings_provider.dart';
import 'package:art3m1s/services/storage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('legacy library entries receive and persist path-based IDs', () async {
    SharedPreferences.setMockInitialValues({
      'game_library': jsonEncode([
        {
          'name': 'sakura',
          'path': '/games/sakura/root.pfs',
          'source': 'pfsArchive',
          'addedAt': '2026-01-01T00:00:00.000',
          'coverPath': '/covers/root.jpg',
        },
        {
          'name': 'nukitashi',
          'path': '/games/nukitashi/root.pfs',
          'source': 'pfsArchive',
          'addedAt': '2026-01-01T00:00:00.000',
          'coverPath': '/covers/root.jpg',
        },
        {
          'name': 'unique',
          'path': '/games/unique',
          'source': 'directory',
          'addedAt': '2026-01-01T00:00:00.000',
        },
      ]),
    });

    await StorageService.ensureInitialized();
    final library = StorageService.instance.getLibrary();
    expect(library, hasLength(3));
    expect(library[0].id, isNot(library[1].id));
    expect(library[0].id, isNot('root.pfs'));
    expect(library[1].id, isNot('root.pfs'));
    expect(library[2].id, 'unique');
    expect(library[0].coverPath, '/covers/root.jpg');

    final prefs = await SharedPreferences.getInstance();
    final persisted =
        jsonDecode(prefs.getString('game_library')!) as List<dynamic>;
    expect((persisted[0] as Map<String, dynamic>)['id'], library[0].id);
    expect((persisted[1] as Map<String, dynamic>)['id'], library[1].id);
    expect((persisted[2] as Map<String, dynamic>)['id'], 'unique');
  });

  group('GameEntry feature compatibility', () {
    test('old library entries default optional features to disabled', () {
      final entry = GameEntry.fromJson({
        'name': 'legacy',
        'path': '/games/legacy',
        'source': 'directory',
        'addedAt': '2026-01-01T00:00:00.000',
      });

      expect(entry.translationEnabled, isFalse);
      expect(entry.translationPatchPath, isEmpty);
      expect(entry.environmentPatchEnabled, isFalse);
      expect(entry.id, startsWith('legacy_'));
    });

    test('per-project opt-ins survive serialization', () {
      final entry = GameEntry(
        id: 'a1b2c3d4',
        name: 'translated',
        path: '/games/translated',
        source: GameSource.pfsArchive,
        addedAt: DateTime(2026),
        translationEnabled: true,
        translationPatchPath: '/patches/translated.jsonl',
        environmentPatchEnabled: true,
      );

      final restored = GameEntry.fromJson(entry.toJson());
      expect(restored.translationEnabled, isTrue);
      expect(restored.translationPatchPath, '/patches/translated.jsonl');
      expect(restored.environmentPatchEnabled, isTrue);
      expect(restored.id, 'a1b2c3d4');
    });

    test(
      'same basename in different directories gets different legacy IDs',
      () {
        final first = GameEntry.legacyIdForPath('/games/sakura/root.pfs');
        final second = GameEntry.legacyIdForPath('/games/nukitashi/root.pfs');

        expect(first, isNot(second));
        expect(first, GameEntry.legacyIdForPath('/games/sakura/root.pfs'));
      },
    );
  });

  group('TranslationSettings compatibility', () {
    test('legacy online settings still default to OpenAI', () {
      const settings = TranslationSettings();

      expect(settings.provider, TranslationProvider.openAi);
      expect(settings.endpoint, TranslationSettings.defaultEndpoint);
    });

    test('providers expose their required credential shape', () {
      expect(TranslationProvider.deepL.usesApiKey, isTrue);
      expect(TranslationProvider.baidu.usesAppCredentials, isTrue);
      expect(TranslationProvider.youdao.usesAppCredentials, isTrue);
      expect(TranslationProvider.anthropic.usesModel, isTrue);
      expect(TranslationProvider.google.usesModel, isFalse);
    });

    test('provider credentials round-trip independently', () {
      const config = TranslationProviderConfig(
        endpoint: 'https://example.test/translate',
        apiKey: 'key',
        appId: 'app',
        appSecret: 'secret',
        model: 'model',
      );

      final restored = TranslationProviderConfig.fromJson(
        TranslationProvider.openAi,
        config.toJson(),
      );
      expect(restored.endpoint, config.endpoint);
      expect(restored.apiKey, config.apiKey);
      expect(restored.appId, config.appId);
      expect(restored.appSecret, config.appSecret);
      expect(restored.model, config.model);
    });

    test(
      'new settings use Responses while legacy flat settings keep chat',
      () async {
        SharedPreferences.setMockInitialValues({});
        final fresh = SettingsNotifier();
        await fresh.ready;
        expect(
          fresh.state.translation.endpoint,
          TranslationSettings.defaultEndpoint,
        );
        fresh.dispose();

        SharedPreferences.setMockInitialValues({
          'translation_api_key': 'legacy-key',
        });
        final legacy = SettingsNotifier();
        await legacy.ready;
        expect(
          legacy.state.translation.endpoint,
          TranslationSettings.legacyDefaultEndpoint,
        );
        legacy.dispose();
      },
    );

    test('switching providers keeps credentials isolated', () async {
      SharedPreferences.setMockInitialValues({});
      final notifier = SettingsNotifier();
      await notifier.ready;

      await notifier.setTranslation(
        notifier.state.translation.copyWith(apiKey: 'openai-key'),
      );
      await notifier.selectTranslationProvider(TranslationProvider.deepL);
      expect(notifier.state.translation.apiKey, isEmpty);
      expect(
        notifier.state.translation.endpoint,
        TranslationProvider.deepL.defaultEndpoint,
      );

      await notifier.setTranslation(
        notifier.state.translation.copyWith(apiKey: 'deepl-key'),
      );
      await notifier.selectTranslationProvider(TranslationProvider.openAi);
      expect(notifier.state.translation.apiKey, 'openai-key');
      expect(
        notifier.state.translation.endpoint,
        TranslationSettings.defaultEndpoint,
      );
      notifier.dispose();
    });
  });
}
