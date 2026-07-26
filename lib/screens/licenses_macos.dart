import 'package:flutter/cupertino.dart' show CupertinoIcons, CupertinoPageRoute;
import 'package:flutter/material.dart' show SelectableText;
import 'package:flutter/widgets.dart';
import 'package:macos_ui/macos_ui.dart';

import '../widgets/inset_scrollbar.dart';
import '../widgets/license_data.dart';
import '../widgets/macos_circle_button.dart';

/// macOS 风格的第三方许可证列表页。
///
/// 不用 macos_ui 的 ToolBar：它挂载/卸载时会注册原生 wallpaper-tint
/// 区域，在被 push 的路由里 pop 后可能在标题栏区域残留白色背景。
class MacosLicensesPage extends StatefulWidget {
  const MacosLicensesPage({super.key});

  @override
  State<MacosLicensesPage> createState() => _MacosLicensesPageState();
}

class _MacosLicensesPageState extends State<MacosLicensesPage> {
  late final Future<List<PackageLicenses>> _licenses = collectLicenses();
  final ScrollController _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MacosScaffold(
      children: [
        ContentArea(
          builder: (context, scrollController) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _LicensePageHeader(title: '第三方许可证'),
              Expanded(
                child: FutureBuilder<List<PackageLicenses>>(
                  future: _licenses,
                  builder: (context, snapshot) {
                    final data = snapshot.data;
                    if (data == null) {
                      return const Center(child: ProgressCircle());
                    }
                    return InsetScrollbar(
                      controller: _scroll,
                      child: ListView.builder(
                        controller: _scroll,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 8,
                        ),
                        itemCount: data.length,
                        itemBuilder: (context, index) {
                          final item = data[index];
                          return _LicenseRow(
                            title: item.package,
                            subtitle: '${item.licenses.length} 条许可证',
                            onTap: () {
                              Navigator.of(context).push(
                                CupertinoPageRoute<void>(
                                  builder: (_) =>
                                      MacosLicenseDetailPage(item: item),
                                ),
                              );
                            },
                          );
                        },
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 带返回圆钮的页头（被 push 的页面用）。
class _LicensePageHeader extends StatelessWidget {
  final String title;

  const _LicensePageHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    final theme = MacosTheme.of(context);
    return Padding(
      // 被 push 的页面没有侧栏，红绿灯（x≈14–68）悬浮在窗口左上角，
      // 左侧让出其宽度，返回按钮紧随其后。
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
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.typography.title2.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LicenseRow extends StatefulWidget {
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _LicenseRow({
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  State<_LicenseRow> createState() => _LicenseRowState();
}

class _LicenseRowState extends State<_LicenseRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final theme = MacosTheme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: _hover
                ? (dark ? const Color(0x1AFFFFFF) : const Color(0x0D000000))
                : null,
            borderRadius: BorderRadius.circular(7),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.title, style: theme.typography.body),
                    const SizedBox(height: 1),
                    Text(
                      widget.subtitle,
                      style: theme.typography.caption1.copyWith(
                        color: MacosColors.systemGrayColor,
                      ),
                    ),
                  ],
                ),
              ),
              const MacosIcon(
                CupertinoIcons.chevron_right,
                size: 13,
                color: MacosColors.systemGrayColor,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 单个包的许可证全文。
class MacosLicenseDetailPage extends StatefulWidget {
  final PackageLicenses item;

  const MacosLicenseDetailPage({super.key, required this.item});

  @override
  State<MacosLicenseDetailPage> createState() => _MacosLicenseDetailPageState();
}

class _MacosLicenseDetailPageState extends State<MacosLicenseDetailPage> {
  final ScrollController _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = MacosTheme.of(context);
    return MacosScaffold(
      children: [
        ContentArea(
          builder: (context, scrollController) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _LicensePageHeader(title: widget.item.package),
              Expanded(
                child: InsetScrollbar(
                  controller: _scroll,
                  child: ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                    itemCount: widget.item.licenses.length,
                    itemBuilder: (context, index) => Padding(
                      padding: const EdgeInsets.only(bottom: 28),
                      child: SelectableText(
                        licenseText(widget.item.licenses[index]),
                        style: theme.typography.callout.copyWith(height: 1.45),
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
}
