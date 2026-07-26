import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/translation_settings.dart';
import '../providers/settings_provider.dart';
import 'translation_settings_cupertino.dart';
import 'translation_settings_fluent.dart';
import 'translation_settings_macos.dart';

/// 文本翻译设置页。按平台分发到对应的原生实现，与其它设置页保持一致的观感：
/// macOS → macos_ui、Windows → fluent_ui、iOS → cupertino、Linux/Android → Material。
class TranslationSettingsScreen extends StatelessWidget {
  const TranslationSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    if (Platform.isMacOS) return const MacosTranslationSettingsScreen();
    if (Platform.isWindows) return const FluentTranslationSettingsScreen();
    if (Platform.isIOS) return const CupertinoTranslationSettingsScreen();
    return const MaterialTranslationSettingsScreen();
  }
}

/// 通用 Material 实现（Linux/Android 直接使用；Windows/iOS 暂时回退到此）。
class MaterialTranslationSettingsScreen extends ConsumerStatefulWidget {
  const MaterialTranslationSettingsScreen({super.key});

  @override
  ConsumerState<MaterialTranslationSettingsScreen> createState() =>
      _MaterialTranslationSettingsScreenState();
}

class _MaterialTranslationSettingsScreenState
    extends ConsumerState<MaterialTranslationSettingsScreen> {
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

  Future<void> _pickPatch() async {
    const types = XTypeGroup(
      label: '翻译对照文件',
      extensions: ['json', 'jsonl', 'tsv'],
    );
    final file = await openFile(acceptedTypeGroups: [types]);
    if (file == null || !mounted) return;
    _save(
      'patch',
      (value) => value.copyWith(patchPath: file.path),
      immediate: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final value = ref.watch(settingsProvider).translation;
    return Scaffold(
      appBar: AppBar(title: const Text('文本翻译')),
      body: ListView(
        children: [
          const _SectionHeader('模式'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SegmentedButton<TranslationMode>(
              segments: [
                for (final mode in TranslationMode.values)
                  ButtonSegment(value: mode, label: Text(mode.label)),
              ],
              selected: {value.mode},
              onSelectionChanged: (selected) {
                _save(
                  'mode',
                  (value) => value.copyWith(mode: selected.first),
                  immediate: true,
                );
              },
            ),
          ),
          if (value.mode != TranslationMode.off) ...[
            const Divider(height: 32),
            const _SectionHeader('对照文件'),
            ListTile(
              leading: const Icon(Icons.table_rows_outlined),
              title: Text(
                value.patchPath.isEmpty ? '未选择' : value.patchPath,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: const Text('JSON / JSONL / TSV'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (value.patchPath.isNotEmpty)
                    IconButton(
                      tooltip: '清除',
                      icon: const Icon(Icons.close),
                      onPressed: () => _save(
                        'patch',
                        (value) => value.copyWith(patchPath: ''),
                        immediate: true,
                      ),
                    ),
                  IconButton(
                    tooltip: '选择文件',
                    icon: const Icon(Icons.folder_open),
                    onPressed: _pickPatch,
                  ),
                ],
              ),
            ),
          ],
          if (value.mode == TranslationMode.online) ...[
            const Divider(height: 32),
            const _SectionHeader('在线服务'),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
              child: DropdownButtonFormField<TranslationProvider>(
                initialValue: value.provider,
                decoration: const InputDecoration(
                  labelText: '服务提供商',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final provider in TranslationProvider.values)
                    DropdownMenuItem(
                      value: provider,
                      child: Text(provider.label),
                    ),
                ],
                onChanged: (provider) async {
                  if (provider == null || provider == value.provider) return;
                  await _flushPendingSaves();
                  await ref
                      .read(settingsProvider.notifier)
                      .selectTranslationProvider(provider);
                },
              ),
            ),
            if (value.provider.endpointEditable)
              _SettingField(
                key: ValueKey('${value.provider.name}-endpoint'),
                label: 'Endpoint',
                initialValue: value.endpoint,
                keyboardType: TextInputType.url,
                onChanged: (text) => _save(
                  'endpoint',
                  (value) => value.copyWith(endpoint: text),
                ),
              ),
            if (value.provider.usesApiKey)
              _SettingField(
                key: ValueKey('${value.provider.name}-api-key'),
                label: switch (value.provider) {
                  TranslationProvider.google => 'Google API Key',
                  TranslationProvider.deepL => 'DeepL Auth Key',
                  _ => 'API Key',
                },
                initialValue: value.apiKey,
                obscureText: true,
                onChanged: (text) =>
                    _save('apiKey', (value) => value.copyWith(apiKey: text)),
              ),
            if (value.provider.usesAppCredentials) ...[
              _SettingField(
                key: ValueKey('${value.provider.name}-app-id'),
                label: value.provider == TranslationProvider.baidu
                    ? 'APP ID'
                    : '应用 ID / App Key',
                initialValue: value.appId,
                onChanged: (text) =>
                    _save('appId', (value) => value.copyWith(appId: text)),
              ),
              _SettingField(
                key: ValueKey('${value.provider.name}-app-secret'),
                label: value.provider == TranslationProvider.baidu
                    ? '密钥'
                    : '应用密钥',
                initialValue: value.appSecret,
                obscureText: true,
                onChanged: (text) => _save(
                  'appSecret',
                  (value) => value.copyWith(appSecret: text),
                ),
              ),
            ],
            if (value.provider.usesModel)
              _SettingField(
                key: ValueKey('${value.provider.name}-model'),
                label: 'Model',
                initialValue: value.model,
                onChanged: (text) =>
                    _save('model', (value) => value.copyWith(model: text)),
              ),
            const Divider(height: 32),
            const _SectionHeader('语言'),
            _SettingField(
              key: const ValueKey('translation-source-language'),
              label: '源语言 / 代码',
              initialValue: value.sourceLanguage,
              onChanged: (text) => _save(
                'sourceLanguage',
                (value) => value.copyWith(sourceLanguage: text),
              ),
            ),
            _SettingField(
              key: const ValueKey('translation-target-language'),
              label: '目标语言 / 代码',
              initialValue: value.targetLanguage,
              onChanged: (text) => _save(
                'targetLanguage',
                (value) => value.copyWith(targetLanguage: text),
              ),
            ),
          ],
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _SettingField extends StatelessWidget {
  const _SettingField({
    super.key,
    required this.label,
    required this.initialValue,
    required this.onChanged,
    this.keyboardType,
    this.obscureText = false,
  });

  final String label;
  final String initialValue;
  final ValueChanged<String> onChanged;
  final TextInputType? keyboardType;
  final bool obscureText;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      child: TextFormField(
        initialValue: initialValue,
        keyboardType: keyboardType,
        obscureText: obscureText,
        enableSuggestions: !obscureText,
        autocorrect: false,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
        onChanged: onChanged,
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Text(title, style: Theme.of(context).textTheme.labelLarge),
    );
  }
}
