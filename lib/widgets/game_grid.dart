import 'dart:io';
import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:macos_ui/macos_ui.dart';

import '../adaptive/context_menu.dart';
import '../adaptive/miuix_chrome.dart';
import '../models/game_entry.dart';

/// 资料库网格：列数随窗口宽度自适应，卡片外观跟当前壳走。
class GameGrid extends StatelessWidget {
  final List<GameEntry> games;
  final void Function(GameEntry) onOpen;
  final void Function(GameEntry) onEdit;
  final void Function(GameEntry) onDelete;
  final ScrollController? controller;
  final EdgeInsets padding;

  const GameGrid({
    super.key,
    required this.games,
    required this.onOpen,
    required this.onEdit,
    required this.onDelete,
    this.controller,
    this.padding = const EdgeInsets.all(20),
  });

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      controller: controller,
      padding: padding,
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 200,
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
        childAspectRatio: 0.68,
      ),
      itemCount: games.length,
      itemBuilder: (_, index) {
        final entry = games[index];
        return GameCard(
          entry: entry,
          onOpen: () => onOpen(entry),
          onEdit: () => onEdit(entry),
          onDelete: () => onDelete(entry),
        );
      },
    );
  }
}

class GameCard extends StatelessWidget {
  final GameEntry entry;
  final VoidCallback onOpen;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const GameCard({
    super.key,
    required this.entry,
    required this.onOpen,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    if (Platform.isMacOS) {
      return _MacosGameCard(
        entry: entry,
        onOpen: onOpen,
        onEdit: onEdit,
        onDelete: onDelete,
      );
    }
    if (Platform.isWindows) {
      return _FluentGameCard(
        entry: entry,
        onOpen: onOpen,
        onEdit: onEdit,
        onDelete: onDelete,
      );
    }
    if (Platform.isIOS) {
      return _CupertinoGameCard(
        entry: entry,
        onOpen: onOpen,
        onEdit: onEdit,
        onDelete: onDelete,
      );
    }
    if (usesMiuixChrome(context)) {
      return _MiuixGameCard(
        entry: entry,
        onOpen: onOpen,
        onEdit: onEdit,
        onDelete: onDelete,
      );
    }
    return _MaterialGameCard(
      entry: entry,
      onOpen: onOpen,
      onEdit: onEdit,
      onDelete: onDelete,
    );
  }
}

List<ContextMenuAction> _gameActions({
  required VoidCallback onOpen,
  required VoidCallback onEdit,
  required VoidCallback onDelete,
}) {
  return [
    ContextMenuAction(label: '开始游戏', onSelected: onOpen),
    ContextMenuAction(label: '编辑…', onSelected: onEdit),
    ContextMenuAction(label: '从库中移除…', destructive: true, onSelected: onDelete),
  ];
}

void _openGameMenu(
  BuildContext context,
  Offset globalPosition, {
  required VoidCallback onOpen,
  required VoidCallback onEdit,
  required VoidCallback onDelete,
}) {
  showAdaptiveContextMenu(
    context,
    globalPosition,
    _gameActions(onOpen: onOpen, onEdit: onEdit, onDelete: onDelete),
  );
}

class _CoverImage extends StatelessWidget {
  const _CoverImage({required this.entry, this.placeholder});

  final GameEntry entry;
  final Widget? placeholder;

  @override
  Widget build(BuildContext context) {
    final path = entry.coverPath;
    if (path != null && File(path).existsSync()) {
      return Image.file(File(path), fit: BoxFit.cover, width: double.infinity);
    }
    return placeholder ??
        ColoredBox(
          color: const Color(0xFFE8E8ED),
          child: Icon(
            entry.source == GameSource.pfsArchive
                ? Icons.inventory_2_outlined
                : Icons.folder_outlined,
            size: 42,
            color: const Color(0xFF8E8E93),
          ),
        );
  }
}

String _relativeTime(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return '刚刚';
  if (d.inHours < 1) return '${d.inMinutes} 分钟前';
  if (d.inDays < 1) return '${d.inHours} 小时前';
  if (d.inDays < 30) return '${d.inDays} 天前';
  return '${t.year}/${t.month}/${t.day}';
}

String _sourceLabel(GameEntry entry) =>
    entry.source == GameSource.pfsArchive ? 'PFS' : '目录';

class _HoverActions extends StatelessWidget {
  const _HoverActions({
    required this.visible,
    required this.onEdit,
    required this.onDelete,
  });

  final bool visible;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    if (!visible) return const SizedBox.shrink();
    return Positioned(
      top: 8,
      right: 8,
      child: Row(
        children: [
          _RoundIconButton(icon: Icons.edit_outlined, onTap: onEdit),
          const SizedBox(width: 6),
          _RoundIconButton(icon: Icons.close, onTap: onDelete),
        ],
      ),
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xCC111111),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(icon, size: 14, color: Colors.white),
        ),
      ),
    );
  }
}

class _MaterialGameCard extends StatefulWidget {
  const _MaterialGameCard({
    required this.entry,
    required this.onOpen,
    required this.onEdit,
    required this.onDelete,
  });

  final GameEntry entry;
  final VoidCallback onOpen;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  State<_MaterialGameCard> createState() => _MaterialGameCardState();
}

class _MaterialGameCardState extends State<_MaterialGameCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final desktop = !Platform.isAndroid && !Platform.isIOS;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Card(
        clipBehavior: Clip.antiAlias,
        elevation: _hover ? 2 : 0,
        color: scheme.surfaceContainerLow,
        child: InkWell(
          onTap: widget.onOpen,
          onLongPress: () => _openGameMenu(
            context,
            Offset.zero,
            onOpen: widget.onOpen,
            onEdit: widget.onEdit,
            onDelete: widget.onDelete,
          ),
          onSecondaryTapUp: desktop
              ? (d) => _openGameMenu(
                  context,
                  d.globalPosition,
                  onOpen: widget.onOpen,
                  onEdit: widget.onEdit,
                  onDelete: widget.onDelete,
                )
              : null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _CoverImage(
                      entry: widget.entry,
                      placeholder: ColoredBox(
                        color: scheme.surfaceContainerHighest,
                        child: Icon(
                          widget.entry.source == GameSource.pfsArchive
                              ? Icons.inventory_2_outlined
                              : Icons.folder_outlined,
                          size: 42,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    _HoverActions(
                      visible: desktop && _hover,
                      onEdit: widget.onEdit,
                      onDelete: widget.onDelete,
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.entry.displayNameOrName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      [
                        _sourceLabel(widget.entry),
                        if (widget.entry.lastPlayedAt != null)
                          _relativeTime(widget.entry.lastPlayedAt!),
                      ].join(' · '),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MiuixGameCard extends StatelessWidget {
  const _MiuixGameCard({
    required this.entry,
    required this.onOpen,
    required this.onEdit,
    required this.onDelete,
  });

  final GameEntry entry;
  final VoidCallback onOpen;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = MiuixTheme.of(context);
    return MiuixCard(
      insideMargin: EdgeInsets.zero,
      onPressed: onOpen,
      onLongPress: () => _openGameMenu(
        context,
        Offset.zero,
        onOpen: onOpen,
        onEdit: onEdit,
        onDelete: onDelete,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(16),
              ),
              child: _CoverImage(
                entry: entry,
                placeholder: ColoredBox(
                  color: theme.colors.surfaceContainerHigh,
                  child: Icon(
                    entry.source == GameSource.pfsArchive
                        ? Icons.inventory_2_outlined
                        : Icons.folder_outlined,
                    size: 42,
                    color: theme.colors.onSurfaceVariantSummary,
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                MiuixText(
                  entry.displayNameOrName,
                  style: theme.textStyles.headline2,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                MiuixText(
                  [
                    _sourceLabel(entry),
                    if (entry.lastPlayedAt != null)
                      _relativeTime(entry.lastPlayedAt!),
                  ].join(' · '),
                  style: theme.textStyles.footnote1,
                  color: theme.colors.onSurfaceVariantSummary,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CupertinoGameCard extends StatelessWidget {
  const _CupertinoGameCard({
    required this.entry,
    required this.onOpen,
    required this.onEdit,
    required this.onDelete,
  });

  final GameEntry entry;
  final VoidCallback onOpen;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final brightness =
        CupertinoTheme.of(context).brightness ??
        MediaQuery.platformBrightnessOf(context);
    final dark = brightness == Brightness.dark;
    final background = CupertinoColors.secondarySystemGroupedBackground
        .resolveFrom(context);
    final border = dark ? const Color(0x40FFFFFF) : const Color(0x33000000);
    final titleColor = CupertinoColors.label.resolveFrom(context);
    final subtitleColor = CupertinoColors.secondaryLabel.resolveFrom(context);
    final placeholder = CupertinoColors.tertiarySystemFill.resolveFrom(context);
    final iconColor = CupertinoColors.secondaryLabel.resolveFrom(context);

    return GestureDetector(
      onTap: onOpen,
      onLongPress: () => _openGameMenu(
        context,
        Offset.zero,
        onOpen: onOpen,
        onEdit: onEdit,
        onDelete: onDelete,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: border, width: 0.5),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _CoverImage(
                  entry: entry,
                  placeholder: ColoredBox(
                    color: placeholder,
                    child: Icon(
                      entry.source == GameSource.pfsArchive
                          ? CupertinoIcons.archivebox
                          : CupertinoIcons.folder,
                      size: 42,
                      color: iconColor,
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.displayNameOrName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: titleColor,
                        decoration: TextDecoration.none,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      [
                        _sourceLabel(entry),
                        if (entry.lastPlayedAt != null)
                          _relativeTime(entry.lastPlayedAt!),
                      ].join(' · '),
                      style: TextStyle(
                        fontSize: 12,
                        color: subtitleColor,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MacosGameCard extends StatefulWidget {
  const _MacosGameCard({
    required this.entry,
    required this.onOpen,
    required this.onEdit,
    required this.onDelete,
  });

  final GameEntry entry;
  final VoidCallback onOpen;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  State<_MacosGameCard> createState() => _MacosGameCardState();
}

class _MacosGameCardState extends State<_MacosGameCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final theme = MacosTheme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onOpen,
        onSecondaryTapUp: (d) => _openGameMenu(
          context,
          d.globalPosition,
          onOpen: widget.onOpen,
          onEdit: widget.onEdit,
          onDelete: widget.onDelete,
        ),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: _hover
                ? (dark ? const Color(0x22FFFFFF) : const Color(0xFFFFFFFF))
                : (dark ? const Color(0x14FFFFFF) : const Color(0xFFF7F7F8)),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: _hover
                  ? const Color(0xFF0A82FF)
                  : (dark ? const Color(0x26FFFFFF) : const Color(0x1A000000)),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _CoverImage(
                      entry: widget.entry,
                      placeholder: ColoredBox(
                        color: dark
                            ? const Color(0xFF3A3A3C)
                            : const Color(0xFFE8E8ED),
                        child: MacosIcon(
                          widget.entry.source == GameSource.pfsArchive
                              ? CupertinoIcons.archivebox
                              : CupertinoIcons.folder,
                          size: 36,
                          color: MacosColors.systemGrayColor,
                        ),
                      ),
                    ),
                    _HoverActions(
                      visible: _hover,
                      onEdit: widget.onEdit,
                      onDelete: widget.onDelete,
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.entry.displayNameOrName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.typography.body.copyWith(
                        fontWeight: FontWeight.w600,
                        decoration: TextDecoration.none,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [
                        _sourceLabel(widget.entry),
                        if (widget.entry.lastPlayedAt != null)
                          _relativeTime(widget.entry.lastPlayedAt!),
                      ].join(' · '),
                      style: theme.typography.caption1.copyWith(
                        color: MacosColors.systemGrayColor,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FluentGameCard extends StatefulWidget {
  const _FluentGameCard({
    required this.entry,
    required this.onOpen,
    required this.onEdit,
    required this.onDelete,
  });

  final GameEntry entry;
  final VoidCallback onOpen;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  State<_FluentGameCard> createState() => _FluentGameCardState();
}

class _FluentGameCardState extends State<_FluentGameCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final theme = fluent.FluentTheme.of(context);
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onSecondaryTapUp: (d) => _openGameMenu(
          context,
          d.globalPosition,
          onOpen: widget.onOpen,
          onEdit: widget.onEdit,
          onDelete: widget.onDelete,
        ),
        child: fluent.Card(
          padding: EdgeInsets.zero,
          child: fluent.HoverButton(
            onPressed: widget.onOpen,
            builder: (context, states) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        _CoverImage(
                          entry: widget.entry,
                          placeholder: ColoredBox(
                            color: theme.resources.controlFillColorDefault,
                            child: Icon(
                              widget.entry.source == GameSource.pfsArchive
                                  ? fluent.FluentIcons.archive
                                  : fluent.FluentIcons.folder_open,
                              size: 36,
                              color: theme.resources.textFillColorSecondary,
                            ),
                          ),
                        ),
                        _HoverActions(
                          visible: _hover,
                          onEdit: widget.onEdit,
                          onDelete: widget.onDelete,
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.entry.displayNameOrName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.typography.bodyStrong,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          [
                            _sourceLabel(widget.entry),
                            if (widget.entry.lastPlayedAt != null)
                              _relativeTime(widget.entry.lastPlayedAt!),
                          ].join(' · '),
                          style: theme.typography.caption?.copyWith(
                            color: theme.resources.textFillColorSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class LibraryEmptyState extends StatelessWidget {
  final Widget action;

  const LibraryEmptyState({super.key, required this.action});

  @override
  Widget build(BuildContext context) {
    final dark = MediaQuery.platformBrightnessOf(context) == Brightness.dark;
    final secondary = dark ? const Color(0xFF98989D) : const Color(0xFF6E6E73);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(CupertinoIcons.game_controller, size: 64, color: secondary),
          const SizedBox(height: 16),
          Text(
            '库中暂无项目',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: dark ? const Color(0xFFF2F2F7) : const Color(0xFF1C1C1E),
              decoration: TextDecoration.none,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '添加已解包的工程目录或 PFS 归档',
            style: TextStyle(
              fontSize: 13,
              color: secondary,
              decoration: TextDecoration.none,
              fontWeight: FontWeight.w400,
            ),
          ),
          const SizedBox(height: 20),
          action,
        ],
      ),
    );
  }
}
