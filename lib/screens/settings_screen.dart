import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/settings_provider.dart';
import '../services/logger.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        children: [
          const _SectionHeader('渲染'),
          ListTile(
            title: const Text('图形后端'),
            subtitle: Text(_backendName(settings.backend)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SegmentedButton<int>(
              segments: _availableBackends()
                  .map((o) => ButtonSegment(value: o.value, label: Text(o.label)))
                  .toList(),
              selected: {settings.backend},
              onSelectionChanged: (v) =>
                  ref.read(settingsProvider.notifier).setBackend(v.first),
            ),
          ),
          const Divider(),
          const _SectionHeader('调试'),
          SwitchListTile(
            title: const Text('调试模式'),
            subtitle: const Text('记录详细日志，显示浮动监控面板'),
            value: settings.debugMode,
            onChanged: (v) => ref.read(settingsProvider.notifier).setDebugMode(v),
          ),
          ListTile(
            leading: const Icon(Icons.save_alt),
            title: const Text('导出日志文件'),
            onTap: () async {
              final file = await Log.exportToFile();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('已导出: ${file.path}')),
                );
              }
            },
          ),
          const Divider(),
          const _SectionHeader('显示'),
          SwitchListTile(
            title: const Text('显示帧率'),
            value: settings.showFps,
            onChanged: (v) => ref.read(settingsProvider.notifier).setShowFps(v),
          ),
          const Divider(),
          const _SectionHeader('信息'),
          const ListTile(title: Text('Art3m1s'), subtitle: Text('Artemis 视觉小说引擎前端')),
          const ListTile(title: Text('版本'), subtitle: Text('0.1.0')),
        ],
      ),
    );
  }

  List<_Option> _availableBackends() {
    final list = <_Option>[];
    if (Platform.isMacOS) {
      list.add(const _Option(3, 'Metal'));
      list.add(const _Option(0, 'CGL'));
    }
    if (Platform.isIOS) {
      list.add(const _Option(2, 'Vulkan'));
      list.add(const _Option(3, 'Metal'));
    }
    if (Platform.isLinux) {
      list.add(const _Option(2, 'Vulkan'));
    }
    if (Platform.isWindows) {
      list.add(const _Option(2, 'Vulkan'));
      list.add(const _Option(4, 'D3D11'));
    }

    list.add(const _Option(1, 'GL'));
    return list;
  }

  static String _backendName(int v) {
    return switch (v) {
      0 => 'CGL (macOS Core OpenGL)',
      1 => 'ANGLE / OpenGL ES',
      2 => 'ANGLE / Vulkan',
      3 => 'ANGLE / Metal',
      4 => 'ANGLE / D3D11',
      _ => '未知',
    };
  }
}

class _Option {
  final int value;
  final String label;
  const _Option(this.value, this.label);
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(title,
          style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.primary)),
    );
  }
}
