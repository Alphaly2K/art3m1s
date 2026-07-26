import 'dart:io';

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/widgets.dart';

import '../adaptive/context_menu.dart';
import '../models/game_entry.dart';

/// 三个壳共用的资料库网格：列数随窗口宽度自适应。
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

/// 单张游戏卡片：整卡点击启动，hover 显示快捷按钮，右键/长按出菜单。
class GameCard extends StatefulWidget {
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
  State<GameCard> createState() => _GameCardState();
}

class _GameCardState extends State<GameCard> {
  bool _hover = false;

  void _showMenu(Offset globalPosition) {
    showAdaptiveContextMenu(context, globalPosition, [
      ContextMenuAction(
        label: '开始游戏',
        icon: CupertinoIcons.play,
        onSelected: widget.onOpen,
      ),
      ContextMenuAction(
        label: '编辑…',
        icon: CupertinoIcons.pencil,
        onSelected: widget.onEdit,
      ),
      ContextMenuAction(
        label: '从库中移除…',
        icon: CupertinoIcons.trash,
        destructive: true,
        onSelected: widget.onDelete,
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final dark = MediaQuery.platformBrightnessOf(context) == Brightness.dark;
    final entry = widget.entry;

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onOpen,
        onSecondaryTapUp: (d) => _showMenu(d.globalPosition),
        onLongPressStart: (d) => _showMenu(d.globalPosition),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: dark ? const Color(0xFF2C2C2E) : const Color(0xFFFFFFFF),
            borderRadius: BorderRadius.circular(10),
            boxShadow: [
              BoxShadow(
                color: const Color(0x28000000),
                blurRadius: _hover ? 14 : 5,
                offset: Offset(0, _hover ? 5 : 2),
              ),
            ],
          ),
          // 边框画在前景层：位于封面图之上，圆角处不会被内容截断。
          foregroundDecoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: _hover
                  ? const Color(0xFF0A64D0)
                  : (dark ? const Color(0x26FFFFFF) : const Color(0x1A000000)),
              width: _hover ? 1.5 : 0.5,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _buildCover(dark)),
              _buildInfoBar(dark, entry),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCover(bool dark) {
    final entry = widget.entry;
    Widget cover;
    if (entry.coverPath != null && File(entry.coverPath!).existsSync()) {
      cover = Image.file(File(entry.coverPath!), fit: BoxFit.cover);
    } else {
      cover = Container(
        color: dark ? const Color(0xFF3A3A3C) : const Color(0xFFE9E9EE),
        child: Center(
          child: Icon(
            entry.source == GameSource.pfsArchive
                ? CupertinoIcons.archivebox
                : CupertinoIcons.folder,
            size: 44,
            color: dark ? const Color(0xFF98989D) : const Color(0xFF8E8E93),
          ),
        ),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        cover,
        // hover 快捷按钮（桌面）：编辑 / 移除，热区 28px。
        if (_hover)
          Positioned(
            top: 6,
            right: 6,
            child: Row(
              children: [
                _QuickAction(
                  icon: CupertinoIcons.pencil,
                  tooltip: '编辑',
                  onTap: widget.onEdit,
                ),
                const SizedBox(width: 5),
                _QuickAction(
                  icon: CupertinoIcons.xmark,
                  tooltip: '移除',
                  onTap: widget.onDelete,
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildInfoBar(bool dark, GameEntry entry) {
    final secondary =
        dark ? const Color(0xFF98989D) : const Color(0xFF6E6E73);
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 9),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            entry.displayNameOrName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: dark ? const Color(0xFFF2F2F7) : const Color(0xFF1C1C1E),
              decoration: TextDecoration.none,
            ),
          ),
          const SizedBox(height: 3),
          Row(
            children: [
              Icon(
                entry.source == GameSource.pfsArchive
                    ? CupertinoIcons.archivebox
                    : CupertinoIcons.folder,
                size: 11,
                color: secondary,
              ),
              const SizedBox(width: 4),
              Text(
                entry.source == GameSource.pfsArchive ? 'PFS' : '目录',
                style: TextStyle(
                  fontSize: 11,
                  color: secondary,
                  decoration: TextDecoration.none,
                  fontWeight: FontWeight.w400,
                ),
              ),
              const Spacer(),
              if (entry.lastPlayedAt != null)
                Text(
                  _relativeTime(entry.lastPlayedAt!),
                  style: TextStyle(
                    fontSize: 11,
                    color: secondary,
                    decoration: TextDecoration.none,
                    fontWeight: FontWeight.w400,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  static String _relativeTime(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return '刚刚';
    if (d.inHours < 1) return '${d.inMinutes} 分钟前';
    if (d.inDays < 1) return '${d.inHours} 小时前';
    if (d.inDays < 30) return '${d.inDays} 天前';
    return '${t.year}/${t.month}/${t.day}';
  }
}

class _QuickAction extends StatefulWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  const _QuickAction({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  @override
  State<_QuickAction> createState() => _QuickActionState();
}

class _QuickActionState extends State<_QuickAction> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: _hover ? const Color(0xE6000000) : const Color(0x99000000),
            shape: BoxShape.circle,
          ),
          child: Icon(widget.icon, size: 14, color: const Color(0xFFFFFFFF)),
        ),
      ),
    );
  }
}

/// 空资料库占位。`action` 由各壳传入平台风格的按钮。
class LibraryEmptyState extends StatelessWidget {
  final Widget action;

  const LibraryEmptyState({super.key, required this.action});

  @override
  Widget build(BuildContext context) {
    final dark = MediaQuery.platformBrightnessOf(context) == Brightness.dark;
    final secondary =
        dark ? const Color(0xFF98989D) : const Color(0xFF6E6E73);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            CupertinoIcons.game_controller,
            size: 64,
            color: secondary,
          ),
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
