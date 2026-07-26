import 'package:art3m1s/models/game_entry.dart';
import 'package:art3m1s/models/translation_settings.dart';
import 'package:art3m1s/providers/settings_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('GameEntry translation compatibility', () {
    test('old library entries default translation to disabled', () {
      final entry = GameEntry.fromJson({
        'name': 'legacy',
        'path': '/games/legacy',
        'source': 'directory',
        'addedAt': '2026-01-01T00:00:00.000',
      });

      expect(entry.translationEnabled, isFalse);
    });

    test('translation opt-in survives serialization', () {
      final entry = GameEntry(
        name: 'translated',
        path: '/games/translated',
        source: GameSource.pfsArchive,
        addedAt: DateTime(2026),
        translationEnabled: true,
      );

      expect(GameEntry.fromJson(entry.toJson()).translationEnabled, isTrue);
    });
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
