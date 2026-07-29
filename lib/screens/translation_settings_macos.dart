import 'dart:async';

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:macos_ui/macos_ui.dart';

import '../models/translation_settings.dart';
import '../providers/settings_provider.dart';
import '../widgets/inset_scrollbar.dart';
import '../widgets/macos_circle_button.dart';

/// 翻译设置页的 macOS 原生实现（macos_ui）。与其它设置页一致：
/// 被 push 出来的无侧栏页面 → 页头照 `_LicensePageHeader` 让开红绿灯（84px 左内边距
/// + `MacosCircleButton` 返回钮）；分组卡片 + 单行结构照 macos_shell 的 `_Section`/
/// `_SettingRow`；文本框用 `MacosTextField`、选择用 `MacosPopupButton`、按钮用 `PushButton`。
class MacosTranslationSettingsScreen extends ConsumerStatefulWidget {
  const MacosTranslationSettingsScreen({super.key});

  @override
  ConsumerState<MacosTranslationSettingsScreen> createState() =>
      _MacosTranslationSettingsScreenState();
}

class _MacosTranslationSettingsScreenState
    extends ConsumerState<MacosTranslationSettingsScreen> {
  // 各字段 350ms 防抖保存；离散选择（模式/服务商/文件）用 immediate。
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
    final theme = MacosTheme.of(context);
    final value = ref.watch(settingsProvider).translation;
    return MacosScaffold(
      children: [
        ContentArea(
          builder: (context, scrollController) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 被 push 的页面无侧栏，红绿灯（x≈14–68）悬浮左上，左侧让宽 + 返回钮。
              Padding(
                padding: const EdgeInsets.fromLTRB(84, 14, 20, 6),
                child: Row(
                  children: [
                    MacosCircleButton(
                      icon: CupertinoIcons.chevron_left,
                      tooltip: '返回',
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        '文本翻译',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.typography.title2.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: InsetScrollbar(
                  controller: scrollController,
                  child: SingleChildScrollView(
                    controller: scrollController,
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 560),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: _buildSections(value),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  List<Widget> _buildSections(TranslationSettings value) {
    return [
      _Section(
        title: '模式',
        children: [
          _SettingRow(
            label: '翻译模式',
            control: MacosPopupButton<TranslationMode>(
              value: value.mode,
              items: [
                for (final mode in TranslationMode.values)
                  MacosPopupMenuItem(value: mode, child: Text(mode.label)),
              ],
              onChanged: (mode) {
                if (mode == null) return;
                _save('mode', (v) => v.copyWith(mode: mode), immediate: true);
              },
            ),
          ),
        ],
      ),
      if (value.mode == TranslationMode.online) ...[
        _Section(
          title: '在线服务',
          children: [
            _SettingRow(
              label: '服务提供商',
              control: MacosPopupButton<TranslationProvider>(
                value: value.provider,
                items: [
                  for (final provider in TranslationProvider.values)
                    MacosPopupMenuItem(
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
        _Section(
          title: '语言',
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

/// macOS 系统设置风格的分组卡片（照 macos_shell 的 `_Section`）。
class _Section extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _Section({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    final theme = MacosTheme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 2, bottom: 6),
            child: Text(
              title,
              style: theme.typography.subheadline.copyWith(
                fontWeight: FontWeight.w600,
                color: MacosColors.systemGrayColor,
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: dark ? const Color(0x1AFFFFFF) : const Color(0xFFFFFFFF),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: dark ? const Color(0x26FFFFFF) : const Color(0x1A000000),
                width: 0.5,
              ),
            ),
            child: Column(
              children: [
                for (var i = 0; i < children.length; i++) ...[
                  if (i > 0)
                    Container(
                      height: 0.5,
                      margin: const EdgeInsets.only(left: 14),
                      color: dark
                          ? const Color(0x26FFFFFF)
                          : const Color(0x1A000000),
                    ),
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

/// 左 label，右侧 control。照 macos_shell 的 `_SettingRow`。
class _SettingRow extends StatelessWidget {
  final String label;
  final Widget control;

  const _SettingRow({required this.label, required this.control});

  @override
  Widget build(BuildContext context) {
    final theme = MacosTheme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          Expanded(child: Text(label, style: theme.typography.body)),
          const SizedBox(width: 16),
          control,
        ],
      ),
    );
  }
}

/// 文本输入行：label 在上、`MacosTextField` 在下（横排放不下长输入，故竖排）。
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
    final theme = MacosTheme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.label,
            style: theme.typography.caption1.copyWith(
              color: MacosColors.systemGrayColor,
            ),
          ),
          const SizedBox(height: 6),
          MacosTextField(
            controller: _controller,
            placeholder: widget.label,
            obscureText: widget.obscureText,
            maxLines: 1,
            onChanged: widget.onChanged,
          ),
        ],
      ),
    );
  }
}
