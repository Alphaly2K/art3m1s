import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/translation_settings.dart';
import '../services/logger.dart';

final settingsProvider = StateNotifierProvider<SettingsNotifier, SettingsState>(
  (ref) {
    return SettingsNotifier();
  },
);

class SettingsState {
  final bool debugMode;
  final bool debugOverlay;
  final bool showFps;
  final bool mobileTouchpadEnabled;
  final int backend; // 0 = CGL, 1 = ANGLE
  final String runtimePlatform;
  final TranslationSettings translation;

  const SettingsState({
    this.debugMode = false,
    this.debugOverlay = false,
    this.showFps = false,
    this.mobileTouchpadEnabled = false,
    this.backend = 0,
    this.runtimePlatform = 'WINDOWS',
    this.translation = const TranslationSettings(),
  });

  SettingsState copyWith({
    bool? debugMode,
    bool? debugOverlay,
    bool? showFps,
    bool? mobileTouchpadEnabled,
    int? backend,
    String? runtimePlatform,
    TranslationSettings? translation,
  }) {
    return SettingsState(
      debugMode: debugMode ?? this.debugMode,
      debugOverlay: debugOverlay ?? this.debugOverlay,
      showFps: showFps ?? this.showFps,
      mobileTouchpadEnabled:
          mobileTouchpadEnabled ?? this.mobileTouchpadEnabled,
      backend: backend ?? this.backend,
      runtimePlatform: runtimePlatform ?? this.runtimePlatform,
      translation: translation ?? this.translation,
    );
  }
}

class SettingsNotifier extends StateNotifier<SettingsState> {
  static const _translationApiKey = 'translation_api_key';
  final Completer<void> _ready = Completer<void>();
  final Map<TranslationProvider, TranslationProviderConfig>
  _translationProviderConfigs = {};

  SettingsNotifier() : super(const SettingsState()) {
    _load();
  }

  Future<void> get ready => _ready.future;

  int getDefaultBackend() {
    if (Platform.isIOS || Platform.isMacOS) {
      return 3; // Metal
    } else {
      if (Platform.isAndroid) {
        return 1; // OpenGLES
      } else {
        return 2; // Vulkan
      }
    }
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final debugMode = prefs.getBool('debug_mode') ?? false;
      Log.setDebugEnabled(debugMode);
      final modeName = prefs.getString('translation_mode');
      final mode = TranslationMode.values
          .where((value) => value.name == modeName)
          .firstOrNull;
      final providerName = prefs.getString('translation_provider');
      final provider = TranslationProvider.values
          .where((value) => value.name == providerName)
          .firstOrNull;
      final selectedProvider = provider ?? TranslationProvider.openAi;
      _loadTranslationProviderConfigs(
        prefs.getString('translation_provider_configs'),
      );
      final hasFlatProviderConfig =
          providerName != null ||
          prefs.containsKey('translation_endpoint') ||
          prefs.containsKey(_translationApiKey) ||
          prefs.containsKey('translation_app_id') ||
          prefs.containsKey('translation_app_secret') ||
          prefs.containsKey('translation_model');
      final legacyConfig = TranslationProviderConfig(
        endpoint:
            prefs.getString('translation_endpoint') ??
            TranslationSettings.legacyDefaultEndpoint,
        apiKey: prefs.getString(_translationApiKey) ?? '',
        appId: prefs.getString('translation_app_id') ?? '',
        appSecret: prefs.getString('translation_app_secret') ?? '',
        model:
            prefs.getString('translation_model') ??
            TranslationSettings.defaultModel,
      );
      _translationProviderConfigs.putIfAbsent(
        selectedProvider,
        () => hasFlatProviderConfig
            ? legacyConfig
            : TranslationProviderConfig.defaults(selectedProvider),
      );
      final providerConfig =
          _translationProviderConfigs[selectedProvider] ??
          TranslationProviderConfig.defaults(selectedProvider);
      state = SettingsState(
        debugMode: debugMode,
        debugOverlay:
            prefs.getBool('debug_overlay') ??
            prefs.getBool('debugOverlay') ??
            false,
        showFps: prefs.getBool('show_fps') ?? false,
        mobileTouchpadEnabled:
            prefs.getBool('mobile_touchpad_enabled') ?? false,
        backend:
            prefs.getInt('gfx_backend') ??
            getDefaultBackend(), // default: ANGLE Vulkan
        runtimePlatform: _normalizeRuntimePlatform(
          prefs.getString('runtime_platform'),
        ),
        translation: TranslationSettings(
          mode: mode ?? TranslationMode.off,
          patchPath: prefs.getString('translation_patch_path') ?? '',
          // First-generation online settings had no provider field and used
          // the OpenAI-compatible endpoint, so missing values map to OpenAI.
          provider: selectedProvider,
          endpoint: providerConfig.endpoint,
          apiKey: providerConfig.apiKey,
          appId: providerConfig.appId,
          appSecret: providerConfig.appSecret,
          model: providerConfig.model,
          sourceLanguage:
              prefs.getString('translation_source_language') ?? '日语',
          targetLanguage:
              prefs.getString('translation_target_language') ?? '简体中文',
        ),
      );
    } finally {
      if (!_ready.isCompleted) _ready.complete();
    }
  }

  Future<void> setDebugMode(bool v) async {
    Log.setDebugEnabled(v);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('debug_mode', v);
    state = state.copyWith(debugMode: v);
  }

  Future<void> setDebugOverlay(bool v) async {
    Log.setOverlay(v);
    state = state.copyWith(debugOverlay: v);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('debug_overlay', v);
  }

  Future<void> setShowFps(bool v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('show_fps', v);
    state = state.copyWith(showFps: v);
  }

  Future<void> setMobileTouchpadEnabled(bool v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('mobile_touchpad_enabled', v);
    state = state.copyWith(mobileTouchpadEnabled: v);
  }

  Future<void> setBackend(int v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('gfx_backend', v);
    state = state.copyWith(backend: v);
  }

  Future<void> setRuntimePlatform(String v) async {
    final platform = _normalizeRuntimePlatform(v);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('runtime_platform', platform);
    state = state.copyWith(runtimePlatform: platform);
  }

  Future<void> setTranslation(TranslationSettings value) async {
    // 先更新内存态，避免多个输入框的异步持久化互相读到旧值并覆盖。
    state = state.copyWith(translation: value);
    _translationProviderConfigs[value.provider] =
        TranslationProviderConfig.fromSettings(value);
    final prefs = await SharedPreferences.getInstance();
    await Future.wait([
      prefs.setString('translation_mode', value.mode.name),
      prefs.setString('translation_patch_path', value.patchPath),
      prefs.setString('translation_provider', value.provider.name),
      prefs.setString('translation_endpoint', value.endpoint),
      prefs.setString('translation_model', value.model),
      prefs.setString('translation_source_language', value.sourceLanguage),
      prefs.setString('translation_target_language', value.targetLanguage),
      prefs.setString(_translationApiKey, value.apiKey),
      prefs.setString('translation_app_id', value.appId),
      prefs.setString('translation_app_secret', value.appSecret),
      prefs.setString(
        'translation_provider_configs',
        jsonEncode({
          for (final entry in _translationProviderConfigs.entries)
            entry.key.name: entry.value.toJson(),
        }),
      ),
    ]);
  }

  Future<void> selectTranslationProvider(TranslationProvider provider) async {
    final current = state.translation;
    if (current.provider == provider) return;
    _translationProviderConfigs[current.provider] =
        TranslationProviderConfig.fromSettings(current);
    final config =
        _translationProviderConfigs[provider] ??
        TranslationProviderConfig.defaults(provider);
    await setTranslation(
      current.copyWith(
        provider: provider,
        endpoint: config.endpoint,
        apiKey: config.apiKey,
        appId: config.appId,
        appSecret: config.appSecret,
        model: config.model,
      ),
    );
  }

  void _loadTranslationProviderConfigs(String? raw) {
    if (raw == null || raw.isEmpty) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      for (final provider in TranslationProvider.values) {
        final config = decoded[provider.name];
        if (config is Map) {
          _translationProviderConfigs[provider] =
              TranslationProviderConfig.fromJson(
                provider,
                config.map((key, value) => MapEntry(key.toString(), value)),
              );
        }
      }
    } on FormatException {
      Log.warn('[Settings] 忽略损坏的翻译服务配置');
    }
  }

  static String _normalizeRuntimePlatform(String? value) {
    final platform = value?.trim().toUpperCase();
    return switch (platform) {
      'WINDOWS' || 'ANDROID' || 'IOS' || 'WASM' => platform!,
      _ => 'WINDOWS',
    };
  }
}
