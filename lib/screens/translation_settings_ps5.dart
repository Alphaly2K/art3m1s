import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../adaptive/ps5_chrome.dart';
import '../models/translation_settings.dart';
import '../providers/settings_provider.dart';

class Ps5TranslationSettingsScreen extends ConsumerStatefulWidget {
  const Ps5TranslationSettingsScreen({super.key});

  @override
  ConsumerState<Ps5TranslationSettingsScreen> createState() =>
      _Ps5TranslationSettingsScreenState();
}

class _Ps5TranslationSettingsScreenState
    extends ConsumerState<Ps5TranslationSettingsScreen> {
  late TranslationSettings _value;
  late final TextEditingController _endpoint;
  late final TextEditingController _apiKey;
  late final TextEditingController _appId;
  late final TextEditingController _appSecret;
  late final TextEditingController _model;
  Timer? _saveTimer;

  @override
  void initState() {
    super.initState();
    _value = ref.read(settingsProvider).translation;
    _endpoint = TextEditingController(text: _value.endpoint);
    _apiKey = TextEditingController(text: _value.apiKey);
    _appId = TextEditingController(text: _value.appId);
    _appSecret = TextEditingController(text: _value.appSecret);
    _model = TextEditingController(text: _value.model);
  }

  @override
  void dispose() {
    if (_saveTimer?.isActive ?? false) {
      final notifier = ref.read(settingsProvider.notifier);
      unawaited(notifier.setTranslation(_value));
    }
    _saveTimer?.cancel();
    _endpoint.dispose();
    _apiKey.dispose();
    _appId.dispose();
    _appSecret.dispose();
    _model.dispose();
    super.dispose();
  }

  void _apply(TranslationSettings value, {bool immediate = false}) {
    setState(() => _value = value);
    _saveTimer?.cancel();
    if (immediate) {
      unawaited(ref.read(settingsProvider.notifier).setTranslation(value));
      return;
    }
    _saveTimer = Timer(const Duration(milliseconds: 320), () {
      unawaited(ref.read(settingsProvider.notifier).setTranslation(_value));
    });
  }

  void _syncControllers(TranslationSettings value) {
    _endpoint.text = value.endpoint;
    _apiKey.text = value.apiKey;
    _appId.text = value.appId;
    _appSecret.text = value.appSecret;
    _model.text = value.model;
  }

  Future<void> _pickProvider() async {
    final provider = await showPs5OptionPicker<TranslationProvider>(
      context,
      title: '翻译服务',
      selected: _value.provider,
      options: [
        for (final provider in TranslationProvider.values)
          (
            value: provider,
            label: provider.label,
            caption: provider.defaultEndpoint,
          ),
      ],
    );
    if (provider == null || !mounted || provider == _value.provider) return;
    _saveTimer?.cancel();
    await ref
        .read(settingsProvider.notifier)
        .selectTranslationProvider(provider);
    if (!mounted) return;
    final value = ref.read(settingsProvider).translation;
    _syncControllers(value);
    setState(() => _value = value);
  }

  Future<void> _pickLanguage({
    required String title,
    required String current,
    required List<TranslationLanguageOption> options,
    required TranslationSettings Function(
      TranslationSettings value,
      String language,
    )
    update,
  }) async {
    final selected = await showPs5OptionPicker<TranslationLanguageOption>(
      context,
      title: title,
      selected: options.firstWhere(
        (option) =>
            option.value == translationLanguageSelection(current, options),
      ),
      options: [
        for (final option in options)
          (value: option, label: option.label, caption: null),
      ],
    );
    if (selected == null || !mounted) return;
    _apply(update(_value, selected.value), immediate: true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Ps5Colors.background,
      body: SafeArea(
        child: Column(
          children: [
            SizedBox(
              height: 82,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Row(
                  children: [
                    Ps5IconButton(
                      icon: Icons.arrow_back_rounded,
                      tooltip: '返回',
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    const SizedBox(width: 16),
                    const Text(
                      '文本翻译',
                      style: TextStyle(
                        color: Ps5Colors.text,
                        fontSize: 27,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const Divider(height: 1, color: Ps5Colors.line),
            Expanded(
              child: Scrollbar(
                thumbVisibility: true,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(30, 28, 42, 42),
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 980),
                      child: Column(
                        children: [
                          Ps5Section(
                            title: '翻译模式',
                            children: [
                              Ps5SettingRow(
                                label: '工作模式',
                                caption: '选择关闭、使用对照文件或在线服务',
                                control: Ps5SegmentedControl<TranslationMode>(
                                  value: _value.mode,
                                  onChanged: (mode) => _apply(
                                    _value.copyWith(mode: mode),
                                    immediate: true,
                                  ),
                                  options: [
                                    for (final mode in TranslationMode.values)
                                      (value: mode, label: mode.label),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          if (_value.mode == TranslationMode.online) ...[
                            const SizedBox(height: 26),
                            Ps5Section(
                              title: '在线服务',
                              children: [
                                Ps5SettingRow(
                                  label: '服务提供商',
                                  caption: _value.provider.label,
                                  control: Ps5Button(
                                    icon: Icons.cloud_outlined,
                                    onPressed: _pickProvider,
                                    child: const Text('更换服务'),
                                  ),
                                ),
                                if (_value.provider.endpointEditable)
                                  _FieldSetting(
                                    label: 'Endpoint',
                                    controller: _endpoint,
                                    hintText: 'API endpoint',
                                    onChanged: (text) =>
                                        _apply(_value.copyWith(endpoint: text)),
                                  ),
                                if (_value.provider.usesApiKey)
                                  _FieldSetting(
                                    label: switch (_value.provider) {
                                      TranslationProvider.google =>
                                        'Google API Key',
                                      TranslationProvider.deepL =>
                                        'DeepL Auth Key',
                                      _ => 'API Key',
                                    },
                                    controller: _apiKey,
                                    hintText: '输入密钥',
                                    obscureText: true,
                                    onChanged: (text) =>
                                        _apply(_value.copyWith(apiKey: text)),
                                  ),
                                if (_value.provider.usesAppCredentials) ...[
                                  _FieldSetting(
                                    label:
                                        _value.provider ==
                                            TranslationProvider.baidu
                                        ? 'APP ID'
                                        : '应用 ID / App Key',
                                    controller: _appId,
                                    hintText: '输入应用 ID',
                                    onChanged: (text) =>
                                        _apply(_value.copyWith(appId: text)),
                                  ),
                                  _FieldSetting(
                                    label:
                                        _value.provider ==
                                            TranslationProvider.baidu
                                        ? '密钥'
                                        : '应用密钥',
                                    controller: _appSecret,
                                    hintText: '输入应用密钥',
                                    obscureText: true,
                                    onChanged: (text) => _apply(
                                      _value.copyWith(appSecret: text),
                                    ),
                                  ),
                                ],
                                if (_value.provider.usesModel)
                                  _FieldSetting(
                                    label: 'Model',
                                    controller: _model,
                                    hintText: '输入模型名',
                                    onChanged: (text) =>
                                        _apply(_value.copyWith(model: text)),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 26),
                            Ps5Section(
                              title: '语言',
                              children: [
                                Ps5SettingRow(
                                  label: '源语言',
                                  caption: _value.sourceLanguage,
                                  control: Ps5Button(
                                    icon: Icons.language_rounded,
                                    onPressed: () => _pickLanguage(
                                      title: '源语言',
                                      current: _value.sourceLanguage,
                                      options: translationSourceLanguages,
                                      update: (value, language) => value
                                          .copyWith(sourceLanguage: language),
                                    ),
                                    child: const Text('选择'),
                                  ),
                                ),
                                Ps5SettingRow(
                                  label: '目标语言',
                                  caption: _value.targetLanguage,
                                  control: Ps5Button(
                                    icon: Icons.translate_rounded,
                                    onPressed: () => _pickLanguage(
                                      title: '目标语言',
                                      current: _value.targetLanguage,
                                      options: translationTargetLanguages,
                                      update: (value, language) => value
                                          .copyWith(targetLanguage: language),
                                    ),
                                    child: const Text('选择'),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FieldSetting extends StatelessWidget {
  const _FieldSetting({
    required this.label,
    required this.controller,
    required this.hintText,
    required this.onChanged,
    this.obscureText = false,
  });

  final String label;
  final TextEditingController controller;
  final String hintText;
  final ValueChanged<String> onChanged;
  final bool obscureText;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Ps5Field(
        controller: controller,
        label: label,
        hintText: hintText,
        obscureText: obscureText,
        onChanged: onChanged,
      ),
    );
  }
}
