import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/translation_settings.dart';
import '../providers/settings_provider.dart';

/// 翻译设置页的 iOS Cupertino 实现。照 cupertino_shell 的
/// `CupertinoListSection.insetGrouped` + `CupertinoListTile.notched` 分组结构；
/// 选择项（模式/服务商）用 `_pickOption` 的 ActionSheet；文本输入用 `CupertinoTextField`。
/// 经 `CupertinoPageRoute` push，导航栏自动带返回。
class CupertinoTranslationSettingsScreen extends ConsumerStatefulWidget {
  const CupertinoTranslationSettingsScreen({super.key});

  @override
  ConsumerState<CupertinoTranslationSettingsScreen> createState() =>
      _CupertinoTranslationSettingsScreenState();
}

class _CupertinoTranslationSettingsScreenState
    extends ConsumerState<CupertinoTranslationSettingsScreen> {
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

  Future<T?> _pickOption<T>({
    required String title,
    required List<(T, String)> options,
  }) {
    return showCupertinoModalPopup<T>(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: Text(title),
        actions: [
          for (final (value, label) in options)
            CupertinoActionSheetAction(
              onPressed: () => Navigator.of(ctx).pop(value),
              child: Text(label),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('取消'),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final value = ref.watch(settingsProvider).translation;
    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(middle: Text('文本翻译')),
      child: SafeArea(child: ListView(children: _buildSections(value))),
    );
  }

  List<Widget> _buildSections(TranslationSettings value) {
    return [
      CupertinoListSection.insetGrouped(
        header: const Text('模式'),
        children: [
          CupertinoListTile.notched(
            title: const Text('翻译模式'),
            additionalInfo: Text(value.mode.label),
            trailing: const CupertinoListTileChevron(),
            onTap: () async {
              final mode = await _pickOption<TranslationMode>(
                title: '翻译模式',
                options: [for (final m in TranslationMode.values) (m, m.label)],
              );
              if (mode != null) {
                _save('mode', (v) => v.copyWith(mode: mode), immediate: true);
              }
            },
          ),
        ],
      ),
      if (value.mode == TranslationMode.online) ...[
        CupertinoListSection.insetGrouped(
          header: const Text('在线服务'),
          children: [
            CupertinoListTile.notched(
              title: const Text('服务提供商'),
              additionalInfo: Text(value.provider.label),
              trailing: const CupertinoListTileChevron(),
              onTap: () async {
                final provider = await _pickOption<TranslationProvider>(
                  title: '服务提供商',
                  options: [
                    for (final p in TranslationProvider.values) (p, p.label),
                  ],
                );
                if (provider == null || provider == value.provider) return;
                await _flushPendingSaves();
                await ref
                    .read(settingsProvider.notifier)
                    .selectTranslationProvider(provider);
              },
            ),
            if (value.provider.endpointEditable)
              _FieldRow(
                key: ValueKey('${value.provider.name}-endpoint'),
                label: 'Endpoint',
                initialValue: value.endpoint,
                onChanged: (text) =>
                    _save('endpoint', (v) => v.copyWith(endpoint: text)),
              ),
            if (value.provider.usesApiKey)
              _FieldRow(
                key: ValueKey('${value.provider.name}-api-key'),
                label: switch (value.provider) {
                  TranslationProvider.google => 'Google API Key',
                  TranslationProvider.deepL => 'DeepL Auth Key',
                  _ => 'API Key',
                },
                initialValue: value.apiKey,
                obscureText: true,
                onChanged: (text) =>
                    _save('apiKey', (v) => v.copyWith(apiKey: text)),
              ),
            if (value.provider.usesAppCredentials) ...[
              _FieldRow(
                key: ValueKey('${value.provider.name}-app-id'),
                label: value.provider == TranslationProvider.baidu
                    ? 'APP ID'
                    : '应用 ID / App Key',
                initialValue: value.appId,
                onChanged: (text) =>
                    _save('appId', (v) => v.copyWith(appId: text)),
              ),
              _FieldRow(
                key: ValueKey('${value.provider.name}-app-secret'),
                label: value.provider == TranslationProvider.baidu
                    ? '密钥'
                    : '应用密钥',
                initialValue: value.appSecret,
                obscureText: true,
                onChanged: (text) =>
                    _save('appSecret', (v) => v.copyWith(appSecret: text)),
              ),
            ],
            if (value.provider.usesModel)
              _FieldRow(
                key: ValueKey('${value.provider.name}-model'),
                label: 'Model',
                initialValue: value.model,
                onChanged: (text) =>
                    _save('model', (v) => v.copyWith(model: text)),
              ),
          ],
        ),
        CupertinoListSection.insetGrouped(
          header: const Text('语言'),
          children: [
            _FieldRow(
              key: const ValueKey('translation-source-language'),
              label: '源语言 / 代码',
              initialValue: value.sourceLanguage,
              onChanged: (text) => _save(
                'sourceLanguage',
                (v) => v.copyWith(sourceLanguage: text),
              ),
            ),
            _FieldRow(
              key: const ValueKey('translation-target-language'),
              label: '目标语言 / 代码',
              initialValue: value.targetLanguage,
              onChanged: (text) => _save(
                'targetLanguage',
                (v) => v.copyWith(targetLanguage: text),
              ),
            ),
          ],
        ),
      ],
    ];
  }
}

/// 文本输入行：左侧灰色 label 前缀 + `CupertinoTextField`（controller 自持，
/// provider 切换时经 ValueKey 重建以重新填值）。
class _FieldRow extends StatefulWidget {
  const _FieldRow({
    super.key,
    required this.label,
    required this.initialValue,
    required this.onChanged,
    this.obscureText = false,
  });

  final String label;
  final String initialValue;
  final ValueChanged<String> onChanged;
  final bool obscureText;

  @override
  State<_FieldRow> createState() => _FieldRowState();
}

class _FieldRowState extends State<_FieldRow> {
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
    return CupertinoTextField.borderless(
      controller: _controller,
      obscureText: widget.obscureText,
      maxLines: 1,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      prefix: Padding(
        padding: const EdgeInsets.only(right: 12),
        child: Text(
          widget.label,
          style: const TextStyle(color: CupertinoColors.secondaryLabel),
        ),
      ),
      textAlign: TextAlign.end,
      onChanged: widget.onChanged,
    );
  }
}
