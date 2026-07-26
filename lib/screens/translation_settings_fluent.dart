import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/translation_settings.dart';
import '../providers/settings_provider.dart';

/// 翻译设置页的 Windows Fluent 实现（fluent_ui）。照 fluent_shell 的 `_FluentSection`
/// 分组卡片 + `_FluentSettingRow` 单行结构；被 push 出来的子页照 `_FluentLicensesPage`
/// 包一层 `NavigationView(titleBar: TitleBar(onBackRequested: pop))`。
class FluentTranslationSettingsScreen extends ConsumerStatefulWidget {
  const FluentTranslationSettingsScreen({super.key});

  @override
  ConsumerState<FluentTranslationSettingsScreen> createState() =>
      _FluentTranslationSettingsScreenState();
}

class _FluentTranslationSettingsScreenState
    extends ConsumerState<FluentTranslationSettingsScreen> {
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
    _save('patch', (value) => value.copyWith(patchPath: file.path), immediate: true);
  }

  @override
  Widget build(BuildContext context) {
    final value = ref.watch(settingsProvider).translation;
    return NavigationView(
      titleBar: TitleBar(
        title: const Text('文本翻译'),
        onBackRequested: () => Navigator.of(context).pop(),
      ),
      content: ScaffoldPage.scrollable(
        header: const PageHeader(title: Text('文本翻译')),
        children: _buildSections(value),
      ),
    );
  }

  List<Widget> _buildSections(TranslationSettings value) {
    return [
      _FluentSection(
        title: '模式',
        children: [
          _FluentSettingRow(
            label: '翻译模式',
            control: ComboBox<TranslationMode>(
              value: value.mode,
              items: [
                for (final mode in TranslationMode.values)
                  ComboBoxItem(value: mode, child: Text(mode.label)),
              ],
              onChanged: (mode) {
                if (mode == null) return;
                _save('mode', (v) => v.copyWith(mode: mode), immediate: true);
              },
            ),
          ),
        ],
      ),
      if (value.mode != TranslationMode.off)
        _FluentSection(
          title: '对照文件',
          children: [
            _FluentSettingRow(
              label: '对照文件',
              caption: value.patchPath.isEmpty
                  ? '未选择 · JSON / JSONL / TSV'
                  : value.patchPath,
              control: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (value.patchPath.isNotEmpty) ...[
                    Button(
                      onPressed: () => _save(
                        'patch',
                        (v) => v.copyWith(patchPath: ''),
                        immediate: true,
                      ),
                      child: const Text('清除'),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Button(onPressed: _pickPatch, child: const Text('选择')),
                ],
              ),
            ),
          ],
        ),
      if (value.mode == TranslationMode.online) ...[
        _FluentSection(
          title: '在线服务',
          children: [
            _FluentSettingRow(
              label: '服务提供商',
              control: ComboBox<TranslationProvider>(
                value: value.provider,
                items: [
                  for (final provider in TranslationProvider.values)
                    ComboBoxItem(value: provider, child: Text(provider.label)),
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
        _FluentSection(
          title: '语言',
          children: [
            _FieldRow(
              key: const ValueKey('translation-source-language'),
              label: '源语言 / 代码',
              initialValue: value.sourceLanguage,
              onChanged: (text) =>
                  _save('sourceLanguage', (v) => v.copyWith(sourceLanguage: text)),
            ),
            _FieldRow(
              key: const ValueKey('translation-target-language'),
              label: '目标语言 / 代码',
              initialValue: value.targetLanguage,
              onChanged: (text) =>
                  _save('targetLanguage', (v) => v.copyWith(targetLanguage: text)),
            ),
          ],
        ),
      ],
    ];
  }
}

/// 分组卡片，照 fluent_shell 的 `_FluentSection`。
class _FluentSection extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _FluentSection({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 2, bottom: 8),
            child: Text(title, style: theme.typography.bodyStrong),
          ),
          Card(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (var i = 0; i < children.length; i++) ...[
                  if (i > 0) const Divider(),
                  children[i],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 单行，照 fluent_shell 的 `_FluentSettingRow`。
class _FluentSettingRow extends StatelessWidget {
  final String label;
  final String? caption;
  final Widget control;

  const _FluentSettingRow({
    required this.label,
    this.caption,
    required this.control,
  });

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: theme.typography.body),
                if (caption != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    caption!,
                    style: theme.typography.caption?.copyWith(
                      color: theme.resources.textFillColorSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 16),
          control,
        ],
      ),
    );
  }
}

/// 文本输入行：`InfoLabel` + `TextBox`（controller 自持，供 provider 切换时重建）。
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
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialValue);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: InfoLabel(
        label: widget.label,
        child: TextBox(
          controller: _controller,
          obscureText: widget.obscureText,
          maxLines: 1,
          onChanged: widget.onChanged,
        ),
      ),
    );
  }
}
