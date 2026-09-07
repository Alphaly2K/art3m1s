import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../adaptive/miuix_chrome.dart';
import '../models/translation_settings.dart';
import '../providers/settings_provider.dart';
import 'translation_font_picker.dart';

class MiuixTranslationSettingsScreen extends ConsumerStatefulWidget {
  const MiuixTranslationSettingsScreen({super.key});

  @override
  ConsumerState<MiuixTranslationSettingsScreen> createState() =>
      _MiuixTranslationSettingsScreenState();
}

class _MiuixTranslationSettingsScreenState
    extends ConsumerState<MiuixTranslationSettingsScreen> {
  final Map<String, Timer> _saveTimers = {};
  final Map<String, TranslationSettings Function(TranslationSettings)>
  _pendingUpdates = {};

  @override
  void dispose() {
    unawaited(_flushPendingSaves());
    super.dispose();
  }

  void _save(
    String key,
    TranslationSettings Function(TranslationSettings current) update, {
    bool immediate = false,
  }) {
    _saveTimers.remove(key)?.cancel();
    _pendingUpdates[key] = update;
    void persist() {
      final pending = _pendingUpdates.remove(key);
      if (pending == null) return;
      final current = ref.read(settingsProvider).translation;
      unawaited(
        ref.read(settingsProvider.notifier).setTranslation(pending(current)),
      );
    }

    if (immediate) {
      persist();
      return;
    }
    _saveTimers[key] = Timer(const Duration(milliseconds: 350), () {
      _saveTimers.remove(key);
      persist();
    });
  }

  Future<void> _flushPendingSaves() async {
    for (final timer in _saveTimers.values) {
      timer.cancel();
    }
    _saveTimers.clear();
    if (_pendingUpdates.isEmpty) return;
    var current = ref.read(settingsProvider).translation;
    for (final update in _pendingUpdates.values) {
      current = update(current);
    }
    _pendingUpdates.clear();
    await ref.read(settingsProvider.notifier).setTranslation(current);
  }

  @override
  Widget build(BuildContext context) {
    final value = ref.watch(settingsProvider).translation;
    return MiuixScaffold(
      topBar: MiuixTopAppBar(
        title: '文本翻译',
        navigationIcon: miuixBarAction(
          icon: 'back',
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      content: (padding) {
        return ListView(
          padding: padding.add(const EdgeInsets.fromLTRB(12, 0, 12, 32)),
          children: [
            MiuixSettingsGroup(
              title: '模式',
              children: [
                for (final mode in TranslationMode.values)
                  MiuixRadioButtonPreference(
                    title: mode.label,
                    selected: value.mode == mode,
                    onClick: () => _save(
                      'mode',
                      (current) => current.copyWith(mode: mode),
                      immediate: true,
                    ),
                  ),
              ],
            ),
            if (value.mode == TranslationMode.online) ...[
              const SizedBox(height: 8),
              MiuixSettingsGroup(
                title: '在线服务',
                children: [
                  MiuixOverlayDropdownPreference(
                    title: '服务提供商',
                    items: [
                      for (final provider in TranslationProvider.values)
                        provider.label,
                    ],
                    selectedIndex: value.provider.index,
                    onSelectedIndexChange: (index) async {
                      final provider = TranslationProvider.values[index];
                      if (provider == value.provider) return;
                      await _flushPendingSaves();
                      await ref
                          .read(settingsProvider.notifier)
                          .selectTranslationProvider(provider);
                    },
                  ),
                ],
              ),
              if (value.provider.endpointEditable ||
                  value.provider.usesApiKey ||
                  value.provider.usesAppCredentials ||
                  value.provider.usesModel) ...[
                const SizedBox(height: 8),
                MiuixSettingsGroup(
                  title: '凭据',
                  children: [
                    if (value.provider.endpointEditable)
                      _FieldPreference(
                        key: ValueKey('${value.provider.name}-endpoint'),
                        title: 'Endpoint',
                        initialValue: value.endpoint,
                        keyboardType: TextInputType.url,
                        onChanged: (text) => _save(
                          'endpoint',
                          (current) => current.copyWith(endpoint: text),
                        ),
                      ),
                    if (value.provider.usesApiKey)
                      _FieldPreference(
                        key: ValueKey('${value.provider.name}-api-key'),
                        title: switch (value.provider) {
                          TranslationProvider.google => 'Google API Key',
                          TranslationProvider.deepL => 'DeepL Auth Key',
                          _ => 'API Key',
                        },
                        initialValue: value.apiKey,
                        obscureText: true,
                        onChanged: (text) => _save(
                          'apiKey',
                          (current) => current.copyWith(apiKey: text),
                        ),
                      ),
                    if (value.provider.usesAppCredentials) ...[
                      _FieldPreference(
                        key: ValueKey('${value.provider.name}-app-id'),
                        title: value.provider == TranslationProvider.baidu
                            ? 'APP ID'
                            : '应用 ID / App Key',
                        initialValue: value.appId,
                        onChanged: (text) => _save(
                          'appId',
                          (current) => current.copyWith(appId: text),
                        ),
                      ),
                      _FieldPreference(
                        key: ValueKey('${value.provider.name}-app-secret'),
                        title: value.provider == TranslationProvider.baidu
                            ? '密钥'
                            : '应用密钥',
                        initialValue: value.appSecret,
                        obscureText: true,
                        onChanged: (text) => _save(
                          'appSecret',
                          (current) => current.copyWith(appSecret: text),
                        ),
                      ),
                    ],
                    if (value.provider.usesModel)
                      _FieldPreference(
                        key: ValueKey('${value.provider.name}-model'),
                        title: 'Model',
                        initialValue: value.model,
                        onChanged: (text) => _save(
                          'model',
                          (current) => current.copyWith(model: text),
                        ),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 8),
              MiuixSettingsGroup(
                title: '语言',
                children: [
                  MiuixOverlayDropdownPreference(
                    title: '源语言',
                    items: [
                      for (final option in translationSourceLanguages)
                        option.label,
                    ],
                    selectedIndex: _languageIndex(
                      value.sourceLanguage,
                      translationSourceLanguages,
                    ),
                    onSelectedIndexChange: (index) => _save(
                      'sourceLanguage',
                      (current) => current.copyWith(
                        sourceLanguage: translationSourceLanguages[index].value,
                      ),
                      immediate: true,
                    ),
                  ),
                  MiuixOverlayDropdownPreference(
                    title: '目标语言',
                    items: [
                      for (final option in translationTargetLanguages)
                        option.label,
                    ],
                    selectedIndex: _languageIndex(
                      value.targetLanguage,
                      translationTargetLanguages,
                    ),
                    onSelectedIndexChange: (index) => _save(
                      'targetLanguage',
                      (current) => current.copyWith(
                        targetLanguage: translationTargetLanguages[index].value,
                      ),
                      immediate: true,
                    ),
                  ),
                ],
              ),
            ],
            if (value.mode != TranslationMode.off) ...[
              const SizedBox(height: 8),
              MiuixSettingsGroup(
                title: '字体',
                children: [
                  MiuixArrowPreference(
                    title: value.fontPath.isEmpty
                        ? '使用游戏脚本字体'
                        : overrideFontDisplayName(value.fontPath),
                    summary: '译文缺字时覆盖游戏字体',
                    onClick: () async {
                      final path = await pickOverrideFont();
                      if (path != null) {
                        _save(
                          'fontPath',
                          (current) => current.copyWith(fontPath: path),
                          immediate: true,
                        );
                      }
                    },
                  ),
                  if (value.fontPath.isNotEmpty)
                    MiuixArrowPreference(
                      title: '清除覆盖字体',
                      onClick: () => _save(
                        'fontPath',
                        (current) => current.copyWith(fontPath: ''),
                        immediate: true,
                      ),
                    ),
                ],
              ),
            ],
          ],
        );
      },
    );
  }

  int _languageIndex(String value, List<TranslationLanguageOption> options) {
    final selected = translationLanguageSelection(value, options);
    final index = options.indexWhere((option) => option.value == selected);
    return index < 0 ? 0 : index;
  }
}

class _FieldPreference extends StatefulWidget {
  const _FieldPreference({
    super.key,
    required this.title,
    required this.initialValue,
    required this.onChanged,
    this.keyboardType,
    this.obscureText = false,
  });

  final String title;
  final String initialValue;
  final ValueChanged<String> onChanged;
  final TextInputType? keyboardType;
  final bool obscureText;

  @override
  State<_FieldPreference> createState() => _FieldPreferenceState();
}

class _FieldPreferenceState extends State<_FieldPreference> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialValue,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: MiuixTextField(
        controller: _controller,
        label: widget.title,
        useLabelAsPlaceholder: true,
        keyboardType: widget.keyboardType,
        obscureText: widget.obscureText,
        singleLine: true,
        onChanged: widget.onChanged,
      ),
    );
  }
}
