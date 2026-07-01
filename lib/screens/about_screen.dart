import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  static const _appRepository = 'https://github.com/Alphaly2K/art3m1s';
  static const _coreRepository = 'https://github.com/Alphaly2K/art3m1s-core';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('关于')),
      body: ListView(
        children: [
          const _AppHeader(),
          const Divider(),
          const _SectionHeader('许可证'),
          const ListTile(
            leading: Icon(Icons.gavel_outlined),
            title: Text('Art3m1s'),
            subtitle: Text('GNU Affero General Public License v3.0'),
          ),
          ListTile(
            leading: const Icon(Icons.article_outlined),
            title: const Text('第三方许可证'),
            subtitle: const Text('查看 Flutter 与依赖包许可证'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              showLicensePage(
                context: context,
                applicationName: 'Art3m1s',
                applicationVersion: '1.0.0+1',
                applicationLegalese: 'AGPL-3.0',
              );
            },
          ),
          const Divider(),
          const _SectionHeader('仓库'),
          const _CopyTile(
            icon: Icons.phone_iphone_outlined,
            title: 'Flutter App',
            value: _appRepository,
          ),
          const _CopyTile(
            icon: Icons.memory_outlined,
            title: 'Rust Core',
            value: _coreRepository,
          ),
          const Divider(),
          const _SectionHeader('主要依赖'),
          const _DependencyGroup(
            title: 'Flutter',
            items: [
              'flutter_riverpod',
              'path_provider',
              'shared_preferences',
              'ffi',
              'file_selector',
              'flutter_file_dialog',
              'audioplayers',
              'media_kit / media_kit_video',
            ],
          ),
          const _DependencyGroup(
            title: 'Rust / Native',
            items: [
              'art3m1s-core',
              'asb-interpreter',
              'asb-decrypt',
              'pfs-upk-rust',
              'mlua / Lua 5.1',
              'glow',
              'image',
              'encoding_rs',
              'MetalANGLE',
            ],
          ),
        ],
      ),
    );
  }
}

class _AppHeader extends StatelessWidget {
  const _AppHeader();

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 20),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              'A3',
              style: textTheme.titleLarge?.copyWith(
                color: Theme.of(context).colorScheme.onPrimaryContainer,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Art3m1s',
                  style: textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Artemis 视觉小说引擎前端',
                  style: textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '版本 1.0.0+1',
                  style: textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CopyTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;

  const _CopyTile({
    required this.icon,
    required this.title,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: SelectableText(value),
      trailing: IconButton(
        tooltip: '复制',
        icon: const Icon(Icons.copy_outlined),
        onPressed: () async {
          await Clipboard.setData(ClipboardData(text: value));
          if (context.mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('已复制')));
          }
        },
      ),
    );
  }
}

class _DependencyGroup extends StatelessWidget {
  final String title;
  final List<String> items;

  const _DependencyGroup({required this.title, required this.items});

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      leading: const Icon(Icons.inventory_2_outlined),
      title: Text(title),
      children: [
        for (final item in items)
          ListTile(
            dense: true,
            contentPadding: const EdgeInsets.only(left: 72, right: 16),
            title: Text(item),
          ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}
