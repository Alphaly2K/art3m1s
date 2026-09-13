import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../adaptive/feedback.dart';
import '../adaptive/ps5_chrome.dart';
import '../controllers/library_actions.dart';
import '../controllers/ps5_input.dart';
import '../models/game_entry.dart';
import '../models/render_backend.dart';
import '../models/render_output.dart';
import '../providers/library_provider.dart';
import '../providers/settings_provider.dart';
import '../screens/translation_settings_ps5.dart';
import '../services/app_info.dart';
import '../services/logger.dart';
import '../widgets/debug_overlay_host.dart';
import '../widgets/license_data.dart';

/// 桌面平台的 PS5 风格大屏壳。
///
/// 三平台共用同一套深色大屏布局，输入同时接受鼠标、键盘与手柄按键。
class Ps5ShellApp extends StatelessWidget {
  const Ps5ShellApp({super.key, this.onExitBigScreen});

  final Future<bool> Function()? onExitBigScreen;

  @override
  Widget build(BuildContext context) {
    return Ps5ChromeScope(
      enabled: true,
      child: MaterialApp(
        title: 'Art3m1s',
        debugShowCheckedModeBanner: false,
        themeMode: ThemeMode.dark,
        theme: _ps5Theme(),
        darkTheme: _ps5Theme(),
        builder: (context, child) {
          return Shortcuts(
            shortcuts: ps5GamepadShortcuts,
            child: child ?? const SizedBox.shrink(),
          );
        },
        home: DebugOverlayHost(
          child: _Ps5Home(onExitBigScreen: onExitBigScreen),
        ),
      ),
    );
  }

  ThemeData _ps5Theme() {
    final scheme = const ColorScheme.dark(
      primary: Ps5Colors.accent,
      secondary: Ps5Colors.blue,
      surface: Ps5Colors.backgroundRaised,
      error: Ps5Colors.danger,
    );
    return ThemeData(
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: Ps5Colors.background,
      useMaterial3: true,
      splashFactory: InkSparkle.splashFactory,
      dividerColor: Ps5Colors.line,
      dialogTheme: const DialogThemeData(
        backgroundColor: Ps5Colors.panelStrong,
        surfaceTintColor: Colors.transparent,
      ),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: Ps5Colors.panelStrong,
        contentTextStyle: TextStyle(color: Ps5Colors.text),
        behavior: SnackBarBehavior.floating,
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStatePropertyAll(
          Ps5Colors.textMuted.withValues(alpha: 0.45),
        ),
        trackColor: const WidgetStatePropertyAll(Colors.transparent),
        radius: const Radius.circular(99),
        thickness: const WidgetStatePropertyAll(4),
      ),
    );
  }
}

class _Ps5Home extends ConsumerStatefulWidget {
  const _Ps5Home({this.onExitBigScreen});

  final Future<bool> Function()? onExitBigScreen;

  @override
  ConsumerState<_Ps5Home> createState() => _Ps5HomeState();
}

class _Ps5HomeState extends ConsumerState<_Ps5Home>
    with SingleTickerProviderStateMixin {
  int _tab = 0;
  bool _searchOpen = false;
  String _searchQuery = '';
  late final AnimationController _intro;
  late final Animation<double> _introFade;
  late final Animation<Offset> _introSlide;

  @override
  void initState() {
    super.initState();
    _intro = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 620),
    )..forward();
    _introFade = CurvedAnimation(
      parent: _intro,
      curve: const Interval(0, 0.72, curve: Curves.easeOutCubic),
    );
    _introSlide = Tween<Offset>(
      begin: const Offset(0, 0.025),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _intro, curve: Curves.easeOutCubic));
  }

  @override
  void dispose() {
    _intro.dispose();
    super.dispose();
  }

  void _openSettings() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const _Ps5SettingsPage(showBack: true),
      ),
    );
  }

  void _openAbout() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const _Ps5AboutPage(showBack: true),
      ),
    );
  }

  KeyEventResult _handleRootKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final action = ps5InputAction(event.logicalKey);
    if (_searchOpen && action == Ps5InputAction.back) {
      setState(() => _searchOpen = false);
      return KeyEventResult.handled;
    }
    if (action == Ps5InputAction.back && widget.onExitBigScreen != null) {
      unawaited(widget.onExitBigScreen!());
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final games = ref.watch(libraryProvider);
    return Actions(
      actions: {
        Ps5PreviousSectionIntent: CallbackAction<Ps5PreviousSectionIntent>(
          onInvoke: (_) {
            setState(() => _tab = (_tab - 1) % 2);
            return null;
          },
        ),
        Ps5NextSectionIntent: CallbackAction<Ps5NextSectionIntent>(
          onInvoke: (_) {
            setState(() => _tab = (_tab + 1) % 2);
            return null;
          },
        ),
        Ps5MenuIntent: CallbackAction<Ps5MenuIntent>(
          onInvoke: (_) {
            _openSettings();
            return null;
          },
        ),
      },
      child: Focus(
        autofocus: true,
        onKeyEvent: _handleRootKey,
        child: Scaffold(
          backgroundColor: Ps5Colors.background,
          body: Stack(
            children: [
              const Positioned.fill(
                child: ColoredBox(color: Ps5Colors.background),
              ),
              FadeTransition(
                opacity: _introFade,
                child: SlideTransition(
                  position: _introSlide,
                  child: SafeArea(
                    child: Column(
                      children: [
                        _Ps5TopBar(
                          tab: _tab,
                          onTab: (value) => setState(() => _tab = value),
                          onSearch: () => setState(() => _searchOpen = true),
                          onSettings: _openSettings,
                          onProfile: _openAbout,
                          onExitBigScreen: widget.onExitBigScreen,
                        ),
                        Expanded(
                          child: ClipRect(
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 260),
                              switchInCurve: Curves.easeOutCubic,
                              switchOutCurve: Curves.easeInCubic,
                              child: _tab == 0
                                  ? _Ps5LibraryPage(
                                      key: const ValueKey('games'),
                                      query: _searchQuery,
                                    )
                                  : const _Ps5MediaPage(key: ValueKey('media')),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (_searchOpen)
                Positioned.fill(
                  child: _Ps5SearchOverlay(
                    games: games,
                    onDismiss: () => setState(() => _searchOpen = false),
                    onSelected: (entry) {
                      setState(() {
                        _searchQuery = entry.displayNameOrName;
                        _searchOpen = false;
                        _tab = 0;
                      });
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Ps5TopBar extends StatefulWidget {
  const _Ps5TopBar({
    required this.tab,
    required this.onTab,
    required this.onSearch,
    required this.onSettings,
    required this.onProfile,
    this.onExitBigScreen,
  });

  final int tab;
  final ValueChanged<int> onTab;
  final VoidCallback onSearch;
  final VoidCallback onSettings;
  final VoidCallback onProfile;
  final Future<bool> Function()? onExitBigScreen;

  @override
  State<_Ps5TopBar> createState() => _Ps5TopBarState();
}

class _Ps5TopBarState extends State<_Ps5TopBar> {
  late DateTime _now;
  Timer? _clock;

  @override
  void initState() {
    super.initState();
    _now = DateTime.now();
    _clock = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hour = _now.hour == 0
        ? 12
        : _now.hour > 12
        ? _now.hour - 12
        : _now.hour;
    final minute = _now.minute.toString().padLeft(2, '0');
    final period = _now.hour >= 12 ? 'PM' : 'AM';
    return SizedBox(
      height: 96,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 980;
          return Padding(
            padding: EdgeInsets.fromLTRB(
              Platform.isMacOS ? (compact ? 82 : 104) : (compact ? 20 : 34),
              0,
              compact ? 20 : 34,
              0,
            ),
            child: Row(
              children: [
                _Ps5TopTab(
                  label: 'Games',
                  selected: widget.tab == 0,
                  compact: compact,
                  onPressed: () => widget.onTab(0),
                ),
                SizedBox(width: compact ? 16 : 30),
                _Ps5TopTab(
                  label: 'Media',
                  selected: widget.tab == 1,
                  compact: compact,
                  onPressed: () => widget.onTab(1),
                ),
                const Spacer(),
                if (widget.onExitBigScreen != null) ...[
                  _TopIconAction(
                    icon: Icons.fullscreen_exit_rounded,
                    tooltip: '退出大屏模式',
                    onPressed: () {
                      unawaited(widget.onExitBigScreen!());
                    },
                  ),
                  const SizedBox(width: 10),
                ],
                _TopIconAction(
                  icon: Icons.search_rounded,
                  tooltip: '搜索',
                  onPressed: widget.onSearch,
                ),
                const SizedBox(width: 10),
                _TopIconAction(
                  icon: Icons.settings_rounded,
                  tooltip: '设置',
                  onPressed: widget.onSettings,
                ),
                if (!compact) ...[
                  const SizedBox(width: 18),
                  Tooltip(
                    message: '关于 Art3m1s',
                    child: InkWell(
                      onTap: widget.onProfile,
                      customBorder: const CircleBorder(),
                      child: Container(
                        width: 40,
                        height: 40,
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: Ps5Colors.line),
                        ),
                        child: ClipOval(
                          child: Image.asset(
                            AppInfo.logoAsset,
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 22),
                  Text(
                    '$hour:$minute $period',
                    style: const TextStyle(
                      color: Ps5Colors.text,
                      fontSize: 28,
                      fontWeight: FontWeight.w400,
                      letterSpacing: -0.5,
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Ps5TopTab extends StatefulWidget {
  const _Ps5TopTab({
    required this.label,
    required this.selected,
    required this.compact,
    required this.onPressed,
  });

  final String label;
  final bool selected;
  final bool compact;
  final VoidCallback onPressed;

  @override
  State<_Ps5TopTab> createState() => _Ps5TopTabState();
}

class _Ps5TopTabState extends State<_Ps5TopTab> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return FocusableActionDetector(
      onFocusChange: (value) => setState(() => _focused = value),
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.numpadEnter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.gameButtonA): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.gameButton8): ActivateIntent(),
      },
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            widget.onPressed();
            return null;
          },
        ),
      },
      child: GestureDetector(
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: widget.selected || _focused
                    ? Ps5Colors.text
                    : Colors.transparent,
                width: 3,
              ),
            ),
          ),
          child: Text(
            widget.label,
            style: TextStyle(
              color: widget.selected
                  ? Ps5Colors.text
                  : Ps5Colors.textMuted.withValues(alpha: 0.72),
              fontSize: widget.compact ? 24 : 31,
              fontWeight: widget.selected ? FontWeight.w700 : FontWeight.w400,
              height: 1,
            ),
          ),
        ),
      ),
    );
  }
}

class _TopIconAction extends StatelessWidget {
  const _TopIconAction({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Ps5IconButton(
      icon: icon,
      tooltip: tooltip,
      onPressed: onPressed,
      size: 44,
    );
  }
}

class _Ps5LibraryPage extends ConsumerStatefulWidget {
  const _Ps5LibraryPage({super.key, required this.query});

  final String query;

  @override
  ConsumerState<_Ps5LibraryPage> createState() => _Ps5LibraryPageState();
}

class _Ps5LibraryPageState extends ConsumerState<_Ps5LibraryPage> {
  static const double _carouselSlotExtent = 158;
  static const double _carouselFocusX = 152;
  static const double _carouselTileSize = 156;
  static const double _selectedTileScale = 1.22;

  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    final library = ref.watch(libraryProvider);
    final sorted = List<GameEntry>.from(library)
      ..sort((a, b) => b.addedAt.compareTo(a.addedAt));
    if (sorted.isEmpty) {
      return _EmptyLibrary(
        onAdd: () => LibraryActions(context, ref).pickDirectory(),
      );
    }
    final query = widget.query.trim().toLowerCase();
    final games = query.isEmpty
        ? sorted
        : sorted
              .where(
                (entry) =>
                    entry.displayNameOrName.toLowerCase().contains(query) ||
                    entry.name.toLowerCase().contains(query),
              )
              .toList();
    if (games.isEmpty) {
      return const _NoSearchResults();
    }
    if (_selectedIndex > games.length) {
      _selectedIndex = games.length;
    }
    final addSelected = _selectedIndex == games.length;
    final selected = games[addSelected ? games.length - 1 : _selectedIndex];
    final actions = LibraryActions(context, ref);

    return Stack(
      children: [
        Positioned.fill(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 460),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            layoutBuilder: (currentChild, previousChildren) => Stack(
              fit: StackFit.expand,
              children: [...previousChildren, ?currentChild],
            ),
            transitionBuilder: (child, animation) {
              final scale = Tween<double>(
                begin: 1.025,
                end: 1,
              ).animate(animation);
              return FadeTransition(
                opacity: animation,
                child: ScaleTransition(scale: scale, child: child),
              );
            },
            child: KeyedSubtree(
              key: ValueKey('ps5-hero-${selected.path}'),
              child: _HeroBackdrop(entry: selected),
            ),
          ),
        ),
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  Ps5Colors.background.withValues(alpha: 0.92),
                  Ps5Colors.background.withValues(alpha: 0.44),
                  Colors.transparent,
                ],
                stops: const [0, 0.43, 0.9],
              ),
            ),
          ),
        ),
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [
                  Ps5Colors.background,
                  Ps5Colors.background.withValues(alpha: 0.42),
                  Colors.transparent,
                ],
                stops: const [0, 0.32, 0.72],
              ),
            ),
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 216,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final selectedExpansion =
                      _carouselTileSize * (_selectedTileScale - 1);
                  final sideShift = selectedExpansion / 2 + 6;
                  const top = 14.0;
                  final labelTop =
                      top + _carouselTileSize * _selectedTileScale - 26;
                  return Stack(
                    clipBehavior: Clip.hardEdge,
                    children: [
                      for (var index = 0; index <= games.length; index++)
                        AnimatedPositioned(
                          key: ValueKey('ps5-carousel-slot-$index'),
                          duration: const Duration(milliseconds: 220),
                          curve: Curves.easeOutCubic,
                          top: top,
                          left:
                              _carouselFocusX +
                              (index - _selectedIndex) * _carouselSlotExtent +
                              (index == _selectedIndex
                                  ? 0
                                  : index < _selectedIndex
                                  ? -sideShift
                                  : sideShift) -
                              _carouselTileSize / 2,
                          width: _carouselTileSize,
                          height: _carouselTileSize,
                          child: index == games.length
                              ? _AddGameTile(
                                  selected: index == _selectedIndex,
                                  autofocus: index == _selectedIndex,
                                  onFocus: () {
                                    if (_selectedIndex != index) {
                                      setState(() => _selectedIndex = index);
                                    }
                                  },
                                  onPressed: actions.pickDirectory,
                                )
                              : _GameTile(
                                  key: ValueKey(
                                    'ps5-game-tile-slot-${games[index].path}',
                                  ),
                                  entry: games[index],
                                  selected: index == _selectedIndex,
                                  autofocus: index == _selectedIndex,
                                  onFocus: () {
                                    if (_selectedIndex != index) {
                                      setState(() => _selectedIndex = index);
                                    }
                                  },
                                  onOpen: () => actions.launch(games[index]),
                                ),
                        ),
                      AnimatedPositioned(
                        duration: const Duration(milliseconds: 220),
                        curve: Curves.easeOutCubic,
                        left:
                            _carouselFocusX +
                            _carouselTileSize * _selectedTileScale / 2 +
                            18,
                        right: 34,
                        top: labelTop,
                        height: 30,
                        child: Align(
                          alignment: Alignment.bottomLeft,
                          child: _CarouselTitle(
                            text: addSelected
                                ? '添加游戏'
                                : selected.displayNameOrName,
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.fromLTRB(56, 20, 56, 58),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 680),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 340),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0, 0.045),
                        end: Offset.zero,
                      ).animate(animation),
                      child: child,
                    ),
                  ),
                  child: Column(
                    key: ValueKey('ps5-hero-copy-${selected.path}'),
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        selected.displayNameOrName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Ps5Colors.text,
                          fontSize: 48,
                          height: 0.98,
                          fontWeight: FontWeight.w700,
                          shadows: [
                            Shadow(
                              color: Color(0xAA000000),
                              blurRadius: 18,
                              offset: Offset(0, 3),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 9,
                        runSpacing: 8,
                        children: [
                          _MetaChip(
                            icon: Icons.memory_rounded,
                            label: selected.engine.label,
                          ),
                          _MetaChip(
                            icon: selected.source == GameSource.directory
                                ? Icons.folder_rounded
                                : Icons.archive_rounded,
                            label: selected.source == GameSource.directory
                                ? '工程目录'
                                : 'PFS',
                          ),
                          if (selected.translationEnabled)
                            const _MetaChip(
                              icon: Icons.translate_rounded,
                              label: '翻译',
                            ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          _HeroActionButton(
                            label: 'Play',
                            icon: Icons.play_arrow_rounded,
                            onPressed: () => actions.launch(selected),
                            wide: true,
                          ),
                          const SizedBox(width: 12),
                          _HeroActionButton(
                            icon: Icons.more_horiz_rounded,
                            tooltip: '项目操作',
                            onPressed: () =>
                                showPs5OptionPicker<int>(
                                  context,
                                  title: selected.displayNameOrName,
                                  selected: 0,
                                  options: const [
                                    (
                                      value: 0,
                                      label: '开始游戏',
                                      caption: '启动当前项目',
                                    ),
                                    (
                                      value: 1,
                                      label: '编辑项目',
                                      caption: '名称、封面与运行参数',
                                    ),
                                    (
                                      value: 2,
                                      label: '从库中移除',
                                      caption: '不会删除原始游戏目录',
                                    ),
                                  ],
                                ).then((value) {
                                  if (!context.mounted) return;
                                  switch (value) {
                                    case 1:
                                      actions.editGame(selected);
                                    case 2:
                                      actions.confirmDelete(selected);
                                  }
                                }),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// 轮播选中项标题：文本变化时先完整淡出旧文本，再重建为新文本并播放进入
/// 动画，避免交叉叠化期间新旧文本同帧排版造成的瞬移。
class _CarouselTitle extends StatefulWidget {
  const _CarouselTitle({required this.text});

  final String text;

  @override
  State<_CarouselTitle> createState() => _CarouselTitleState();
}

class _CarouselTitleState extends State<_CarouselTitle>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;
  late String _shown = widget.text;
  bool _swapping = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 240),
      reverseDuration: const Duration(milliseconds: 150),
    )..forward();
    final curved = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    _fade = curved;
    _slide = Tween<Offset>(
      begin: const Offset(0.025, 0),
      end: Offset.zero,
    ).animate(curved);
  }

  @override
  void didUpdateWidget(_CarouselTitle oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.text == _shown || _swapping) return;
    _swapping = true;
    _controller.reverse().then((_) {
      if (!mounted) return;
      setState(() => _shown = widget.text);
      _swapping = false;
      _controller.forward(from: 0);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(
        position: _slide,
        child: Text(
          _shown,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: Ps5Colors.text.withValues(alpha: 0.86),
            fontSize: 22,
            fontWeight: FontWeight.w400,
            shadows: const [
              Shadow(
                color: Color(0x99000000),
                blurRadius: 12,
                offset: Offset(0, 2),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeroBackdrop extends StatelessWidget {
  const _HeroBackdrop({required this.entry});

  final GameEntry entry;

  @override
  Widget build(BuildContext context) {
    final coverPath = entry.coverPath;
    if (coverPath != null && File(coverPath).existsSync()) {
      return Stack(
        fit: StackFit.expand,
        children: [
          Image.file(
            File(coverPath),
            fit: BoxFit.cover,
            alignment: Alignment.center,
            colorBlendMode: BlendMode.srcOver,
            color: const Color(0x24000000),
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(0.58, -0.08),
                radius: 0.92,
                colors: [Color(0x08000000), Color(0x77000000)],
              ),
            ),
          ),
        ],
      );
    }
    return _CoverBackdropFallback(title: entry.displayNameOrName);
  }
}

class _CoverBackdropFallback extends StatelessWidget {
  const _CoverBackdropFallback({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final initial = title.trim().isEmpty ? 'A' : title.trim()[0].toUpperCase();
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [Color(0xFF10253A), Color(0xFF05080D)],
        ),
      ),
      child: Center(
        child: Text(
          initial,
          style: TextStyle(
            color: Ps5Colors.accent.withValues(alpha: 0.13),
            fontSize: 420,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}

class _HeroActionButton extends StatefulWidget {
  const _HeroActionButton({
    required this.onPressed,
    this.icon,
    this.label,
    this.tooltip,
    this.wide = false,
  });

  final VoidCallback onPressed;
  final IconData? icon;
  final String? label;
  final String? tooltip;
  final bool wide;

  @override
  State<_HeroActionButton> createState() => _HeroActionButtonState();
}

class _HeroActionButtonState extends State<_HeroActionButton> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final button = FocusableActionDetector(
      onFocusChange: (value) => setState(() => _focused = value),
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.numpadEnter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.gameButtonA): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.gameButton8): ActivateIntent(),
      },
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            widget.onPressed();
            return null;
          },
        ),
      },
      child: Material(
        color: _focused ? const Color(0xFFE9F2FF) : const Color(0xCC20242A),
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          onTap: widget.onPressed,
          borderRadius: BorderRadius.circular(999),
          child: SizedBox(
            width: widget.wide ? 268 : 68,
            height: 64,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (widget.icon != null)
                  Icon(
                    widget.icon,
                    color: _focused ? Ps5Colors.background : Ps5Colors.text,
                    size: 25,
                  ),
                if (widget.label != null) ...[
                  const SizedBox(width: 10),
                  Text(
                    widget.label!,
                    style: TextStyle(
                      color: _focused ? Ps5Colors.background : Ps5Colors.text,
                      fontSize: 19,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
    if (widget.tooltip == null) return button;
    return Tooltip(message: widget.tooltip!, child: button);
  }
}

class _EmptyLibrary extends StatelessWidget {
  const _EmptyLibrary({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 580),
        child: Ps5Panel(
          padding: const EdgeInsets.all(34),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset(
                AppInfo.logoAsset,
                width: 104,
                height: 104,
                fit: BoxFit.cover,
              ),
              const SizedBox(height: 22),
              const Text(
                '库中暂无项目',
                style: TextStyle(
                  color: Ps5Colors.text,
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                '选择一个包含游戏工程的文件夹，Art3m1s 会原地识别并导入。',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Ps5Colors.textMuted,
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 24),
              Ps5Button(
                primary: true,
                icon: Icons.folder_open_rounded,
                onPressed: onAdd,
                child: const Text('选择游戏文件夹'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NoSearchResults extends StatelessWidget {
  const _NoSearchResults();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.search_off_rounded, color: Ps5Colors.textMuted, size: 48),
          SizedBox(height: 14),
          Text(
            '没有匹配的游戏',
            style: TextStyle(
              color: Ps5Colors.text,
              fontSize: 22,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _Ps5MediaPage extends StatelessWidget {
  const _Ps5MediaPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.play_circle_outline_rounded,
            color: Ps5Colors.textMuted,
            size: 58,
          ),
          SizedBox(height: 16),
          Text(
            'Media',
            style: TextStyle(
              color: Ps5Colors.text,
              fontSize: 34,
              fontWeight: FontWeight.w700,
            ),
          ),
          SizedBox(height: 8),
          Text(
            '当前没有可用的媒体项目',
            style: TextStyle(color: Ps5Colors.textMuted, fontSize: 14),
          ),
        ],
      ),
    );
  }
}

class _Ps5SearchOverlay extends StatefulWidget {
  const _Ps5SearchOverlay({
    required this.games,
    required this.onDismiss,
    required this.onSelected,
  });

  final List<GameEntry> games;
  final VoidCallback onDismiss;
  final ValueChanged<GameEntry> onSelected;

  @override
  State<_Ps5SearchOverlay> createState() => _Ps5SearchOverlayState();
}

class _Ps5SearchOverlayState extends State<_Ps5SearchOverlay> {
  final TextEditingController _controller = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final results = widget.games
        .where(
          (entry) =>
              _query.isEmpty ||
              entry.displayNameOrName.toLowerCase().contains(_query) ||
              entry.name.toLowerCase().contains(_query),
        )
        .take(8)
        .toList();
    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            ps5InputAction(event.logicalKey) == Ps5InputAction.back) {
          widget.onDismiss();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              onTap: widget.onDismiss,
              child: const ColoredBox(color: Color(0xB8000000)),
            ),
          ),
          Align(
            alignment: Alignment.topCenter,
            child: Padding(
              padding: const EdgeInsets.only(top: 76),
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: 760,
                  maxHeight: 560,
                ),
                child: Ps5Panel(
                  opaque: true,
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: _controller,
                        autofocus: true,
                        onChanged: (value) =>
                            setState(() => _query = value.toLowerCase()),
                        style: const TextStyle(
                          color: Ps5Colors.text,
                          fontSize: 20,
                        ),
                        cursorColor: Ps5Colors.accent,
                        decoration: InputDecoration(
                          hintText: 'Search games',
                          hintStyle: const TextStyle(
                            color: Ps5Colors.textMuted,
                          ),
                          prefixIcon: const Icon(
                            Icons.search_rounded,
                            color: Ps5Colors.textMuted,
                          ),
                          filled: true,
                          fillColor: Ps5Colors.backgroundRaised,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Flexible(
                        child: results.isEmpty
                            ? const Center(
                                child: Text(
                                  '没有匹配的游戏',
                                  style: TextStyle(
                                    color: Ps5Colors.textMuted,
                                    fontSize: 14,
                                  ),
                                ),
                              )
                            : ListView.builder(
                                shrinkWrap: true,
                                itemCount: results.length,
                                itemBuilder: (context, index) {
                                  final entry = results[index];
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 7),
                                    child: Material(
                                      color: Ps5Colors.backgroundRaised,
                                      borderRadius: BorderRadius.circular(7),
                                      child: InkWell(
                                        onTap: () => widget.onSelected(entry),
                                        borderRadius: BorderRadius.circular(7),
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 13,
                                            vertical: 10,
                                          ),
                                          child: Row(
                                            children: [
                                              SizedBox.square(
                                                dimension: 48,
                                                child: ClipRRect(
                                                  borderRadius:
                                                      BorderRadius.circular(6),
                                                  child: _CoverArt(
                                                    entry: entry,
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 13),
                                              Expanded(
                                                child: Text(
                                                  entry.displayNameOrName,
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: const TextStyle(
                                                    color: Ps5Colors.text,
                                                    fontSize: 15,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              ),
                                              const Icon(
                                                Icons.chevron_right_rounded,
                                                color: Ps5Colors.textMuted,
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AddGameTile extends StatefulWidget {
  const _AddGameTile({
    required this.selected,
    required this.autofocus,
    required this.onFocus,
    required this.onPressed,
  });

  final bool selected;
  final bool autofocus;
  final VoidCallback onFocus;
  final VoidCallback onPressed;

  @override
  State<_AddGameTile> createState() => _AddGameTileState();
}

class _AddGameTileState extends State<_AddGameTile> {
  Timer? _hoverTimer;

  @override
  void dispose() {
    _hoverTimer?.cancel();
    super.dispose();
  }

  void _scheduleHoverSelection() {
    _hoverTimer?.cancel();
    _hoverTimer = Timer(const Duration(milliseconds: 260), () {
      if (mounted) widget.onFocus();
    });
  }

  void _cancelHoverSelection() {
    _hoverTimer?.cancel();
    _hoverTimer = null;
  }

  @override
  Widget build(BuildContext context) {
    final active = widget.selected;
    return FocusableActionDetector(
      autofocus: widget.autofocus,
      onFocusChange: (value) {
        if (value) widget.onFocus();
      },
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.numpadEnter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.gameButtonA): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.gameButton8): ActivateIntent(),
      },
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            widget.onPressed();
            return null;
          },
        ),
      },
      child: AnimatedScale(
        scale: active ? _Ps5LibraryPageState._selectedTileScale : 1,
        alignment: Alignment.topCenter,
        duration: const Duration(milliseconds: 190),
        curve: Curves.easeOutCubic,
        child: MouseRegion(
          onEnter: (_) => _scheduleHoverSelection(),
          onExit: (_) => _cancelHoverSelection(),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 190),
            curve: Curves.easeOutCubic,
            width: _Ps5LibraryPageState._carouselTileSize,
            height: _Ps5LibraryPageState._carouselTileSize,
            padding: EdgeInsets.all(active ? 3 : 4),
            decoration: BoxDecoration(
              color: active
                  ? Colors.white.withValues(alpha: 0.09)
                  : Ps5Colors.backgroundRaised.withValues(alpha: 0.66),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: active
                    ? Colors.white.withValues(alpha: 0.96)
                    : Colors.transparent,
                width: active ? 2.2 : 0,
              ),
              boxShadow: active
                  ? const [
                      BoxShadow(
                        color: Color(0x8A000000),
                        blurRadius: 26,
                        spreadRadius: 1,
                        offset: Offset(0, 10),
                      ),
                    ]
                  : null,
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: widget.onPressed,
                borderRadius: BorderRadius.circular(11),
                child: Center(
                  child: Icon(
                    Icons.add_rounded,
                    size: 42,
                    color: active ? Ps5Colors.accent : Ps5Colors.textMuted,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GameTile extends StatefulWidget {
  const _GameTile({
    super.key,
    required this.entry,
    required this.selected,
    required this.autofocus,
    required this.onFocus,
    required this.onOpen,
  });

  final GameEntry entry;
  final bool selected;
  final bool autofocus;
  final VoidCallback onFocus;
  final VoidCallback onOpen;

  @override
  State<_GameTile> createState() => _GameTileState();
}

class _GameTileState extends State<_GameTile> {
  Timer? _hoverTimer;

  @override
  void dispose() {
    _hoverTimer?.cancel();
    super.dispose();
  }

  void _scheduleHoverSelection() {
    _hoverTimer?.cancel();
    _hoverTimer = Timer(const Duration(milliseconds: 260), () {
      if (mounted) widget.onFocus();
    });
  }

  void _cancelHoverSelection() {
    _hoverTimer?.cancel();
    _hoverTimer = null;
  }

  @override
  Widget build(BuildContext context) {
    final active = widget.selected;
    return FocusableActionDetector(
      autofocus: widget.autofocus,
      onFocusChange: (value) {
        if (value) widget.onFocus();
      },
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.numpadEnter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.gameButtonA): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.gameButton8): ActivateIntent(),
      },
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            widget.onOpen();
            return null;
          },
        ),
      },
      child: AnimatedScale(
        key: ValueKey('ps5-game-tile-${widget.entry.path}'),
        scale: active ? _Ps5LibraryPageState._selectedTileScale : 1,
        alignment: Alignment.topCenter,
        duration: const Duration(milliseconds: 190),
        curve: Curves.easeOutCubic,
        child: MouseRegion(
          onEnter: (_) => _scheduleHoverSelection(),
          onExit: (_) => _cancelHoverSelection(),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 190),
            curve: Curves.easeOutCubic,
            width: _Ps5LibraryPageState._carouselTileSize,
            height: _Ps5LibraryPageState._carouselTileSize,
            padding: EdgeInsets.all(active ? 3 : 4),
            decoration: BoxDecoration(
              color: active
                  ? Colors.white.withValues(alpha: 0.09)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: active
                    ? Colors.white.withValues(alpha: 0.96)
                    : Colors.transparent,
                width: active ? 2.2 : 0,
              ),
              boxShadow: active
                  ? const [
                      BoxShadow(
                        color: Color(0x8A000000),
                        blurRadius: 26,
                        spreadRadius: 1,
                        offset: Offset(0, 10),
                      ),
                    ]
                  : null,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(11),
              child: _CoverArt(entry: widget.entry),
            ),
          ),
        ),
      ),
    );
  }
}

class _CoverArt extends StatelessWidget {
  const _CoverArt({required this.entry});

  final GameEntry entry;

  @override
  Widget build(BuildContext context) {
    final coverPath = entry.coverPath;
    if (coverPath != null && File(coverPath).existsSync()) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(5),
        child: Image.file(
          File(coverPath),
          width: double.infinity,
          height: double.infinity,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) =>
              _CoverFallback(title: entry.displayNameOrName),
        ),
      );
    }
    return _CoverFallback(title: entry.displayNameOrName);
  }
}

class _CoverFallback extends StatelessWidget {
  const _CoverFallback({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final initial = title.trim().isEmpty ? 'A' : title.trim()[0].toUpperCase();
    return ClipRRect(
      borderRadius: BorderRadius.circular(5),
      child: DecoratedBox(
        decoration: const BoxDecoration(color: Color(0xFF0C1723)),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Center(
              child: Text(
                initial,
                style: TextStyle(
                  color: Ps5Colors.accent.withValues(alpha: 0.22),
                  fontSize: 70,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            Positioned(
              left: 12,
              right: 12,
              bottom: 12,
              child: Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Ps5Colors.text.withValues(alpha: 0.78),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Ps5Colors.backgroundRaised,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Ps5Colors.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: Ps5Colors.accent),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: Ps5Colors.textMuted,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _Ps5SettingsPage extends ConsumerWidget {
  const _Ps5SettingsPage({this.showBack = false});

  final bool showBack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final backends = availableBackends();
    final selectedBackend = backends.firstWhere(
      (backend) => backend.value == settings.backend,
      orElse: () => backends.first,
    );

    return _Ps5SubpageFrame(
      showBack: showBack,
      title: '设置',
      child: Scrollbar(
        thumbVisibility: true,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(28, 12, 42, 42),
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 980),
              child: Column(
                children: [
                  const _PageHeading(
                    title: '系统设置',
                    caption: '按游戏保存的选项会在项目编辑器中单独配置。',
                  ),
                  const SizedBox(height: 28),
                  Ps5Section(
                    title: '渲染',
                    children: [
                      Ps5SettingRow(
                        label: '图形后端',
                        caption: selectedBackend.label,
                        control: Ps5Button(
                          icon: Icons.memory_rounded,
                          onPressed: () async {
                            final value = await showPs5OptionPicker<int>(
                              context,
                              title: '图形后端',
                              selected: selectedBackend.value,
                              options: [
                                for (final backend in backends)
                                  (
                                    value: backend.value,
                                    label: backend.label,
                                    caption: backendName(backend.value),
                                  ),
                              ],
                            );
                            if (value != null) notifier.setBackend(value);
                          },
                          child: Text(selectedBackend.label),
                        ),
                      ),
                      if (supportsSpatialUpscalingSettings(settings.backend))
                        Ps5SettingRow(
                          label: '超分输出',
                          caption: renderOutputDescription(
                            settings.renderOutputMode,
                            customWidth: settings.customRenderWidth,
                            customHeight: settings.customRenderHeight,
                          ),
                          control: Ps5Button(
                            icon: Icons.aspect_ratio_rounded,
                            onPressed: () async {
                              final value =
                                  await showPs5OptionPicker<RenderOutputMode>(
                                    context,
                                    title: '超分输出',
                                    selected: settings.renderOutputMode,
                                    options: [
                                      for (final mode
                                          in RenderOutputMode.values)
                                        (
                                          value: mode,
                                          label: mode.label,
                                          caption: renderOutputDescription(
                                            mode,
                                            customWidth:
                                                settings.customRenderWidth,
                                            customHeight:
                                                settings.customRenderHeight,
                                          ),
                                        ),
                                    ],
                                  );
                              if (value != null) {
                                notifier.setRenderOutputMode(value);
                              }
                            },
                            child: Text(settings.renderOutputMode.label),
                          ),
                        ),
                      if (supportsSpatialUpscalingSettings(settings.backend) &&
                          settings.renderOutputMode == RenderOutputMode.custom)
                        Ps5SettingRow(
                          label: '自定义分辨率',
                          caption: '输出保持游戏原始宽高比',
                          control: Ps5Button(
                            icon: Icons.photo_size_select_large_rounded,
                            onPressed: () async {
                              final size =
                                  await showDialog<({int width, int height})>(
                                    context: context,
                                    builder: (_) => _ResolutionDialog(
                                      width: settings.customRenderWidth,
                                      height: settings.customRenderHeight,
                                    ),
                                  );
                              if (size != null) {
                                notifier.setCustomRenderSize(
                                  size.width,
                                  size.height,
                                );
                              }
                            },
                            child: Text(
                              '${settings.customRenderWidth} × ${settings.customRenderHeight}',
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 26),
                  Ps5Section(
                    title: '运行时',
                    children: [
                      Ps5SettingRow(
                        label: '文本翻译',
                        caption: settings.translation.mode.label,
                        control: Ps5Button(
                          icon: Icons.translate_rounded,
                          onPressed: () {
                            Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) =>
                                    const Ps5TranslationSettingsScreen(),
                              ),
                            );
                          },
                          child: const Text('配置'),
                        ),
                      ),
                      Ps5SettingRow(
                        label: '显示帧率',
                        caption: '在游戏画面上显示实时 FPS',
                        control: Ps5Switch(
                          value: settings.showFps,
                          onChanged: notifier.setShowFps,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 26),
                  Ps5Section(
                    title: '调试',
                    children: [
                      Ps5SettingRow(
                        label: '调试模式',
                        caption: '记录详细日志',
                        control: Ps5Switch(
                          value: settings.debugMode,
                          onChanged: notifier.setDebugMode,
                        ),
                      ),
                      Ps5SettingRow(
                        label: '脏区着色',
                        caption: '标记实际重绘区域',
                        control: Ps5Switch(
                          value: settings.damageVisualization,
                          onChanged: settings.debugMode
                              ? notifier.setDamageVisualization
                              : null,
                        ),
                      ),
                      Ps5SettingRow(
                        label: 'Profiler 浮层',
                        caption: '显示分阶段耗时与内存统计',
                        control: Ps5Switch(
                          value: settings.profilerOverlay,
                          onChanged: settings.debugMode
                              ? notifier.setProfilerOverlay
                              : null,
                        ),
                      ),
                      Ps5SettingRow(
                        label: '调试面板',
                        caption: '显示浮动监控面板',
                        control: Ps5Switch(
                          value: settings.debugOverlay,
                          onChanged: notifier.setDebugOverlay,
                        ),
                      ),
                      Ps5SettingRow(
                        label: '崩溃与错误上报',
                        caption: '上传不含游戏内容的诊断信息，重启后完全生效',
                        control: Ps5Switch(
                          value: settings.crashReportingEnabled,
                          onChanged: notifier.setCrashReportingEnabled,
                        ),
                      ),
                      Ps5SettingRow(
                        label: '导出日志',
                        caption: '把当前会话日志写入文件',
                        control: Ps5Button(
                          icon: Icons.ios_share_rounded,
                          onPressed: () async {
                            final file = await Log.exportToFile();
                            if (context.mounted) {
                              notify(context, '已导出: ${file.path}');
                            }
                          },
                          child: const Text('导出'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ResolutionDialog extends StatefulWidget {
  const _ResolutionDialog({required this.width, required this.height});

  final int width;
  final int height;

  @override
  State<_ResolutionDialog> createState() => _ResolutionDialogState();
}

class _ResolutionDialogState extends State<_ResolutionDialog> {
  late final TextEditingController _width = TextEditingController(
    text: '${widget.width}',
  );
  late final TextEditingController _height = TextEditingController(
    text: '${widget.height}',
  );
  String? _error;

  @override
  void dispose() {
    _width.dispose();
    _height.dispose();
    super.dispose();
  }

  void _submit() {
    final width = int.tryParse(_width.text);
    final height = int.tryParse(_height.text);
    if (width == null ||
        height == null ||
        width < 1 ||
        height < 1 ||
        width > 16384 ||
        height > 16384) {
      setState(() => _error = '分辨率必须在 1 到 16384 之间');
      return;
    }
    Navigator.of(context).pop((width: width, height: height));
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Ps5Panel(
          opaque: true,
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                '自定义输出分辨率',
                style: TextStyle(
                  color: Ps5Colors.text,
                  fontSize: 21,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: Ps5Field(
                      controller: _width,
                      label: '宽度',
                      hintText: '2560',
                      autofocus: true,
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Ps5Field(
                      controller: _height,
                      label: '高度',
                      hintText: '1440',
                      keyboardType: TextInputType.number,
                    ),
                  ),
                ],
              ),
              if (_error != null) ...[
                const SizedBox(height: 11),
                Text(
                  _error!,
                  style: const TextStyle(color: Ps5Colors.danger, fontSize: 12),
                ),
              ],
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Ps5Button(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('取消'),
                  ),
                  const SizedBox(width: 10),
                  Ps5Button(
                    primary: true,
                    onPressed: _submit,
                    child: const Text('应用'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Ps5AboutPage extends StatelessWidget {
  const _Ps5AboutPage({this.showBack = false});

  final bool showBack;

  static const _appRepository = 'https://github.com/Alphaly2K/art3m1s';
  static const _coreRepository = 'https://github.com/Alphaly2K/art3m1s-core';

  @override
  Widget build(BuildContext context) {
    return _Ps5SubpageFrame(
      showBack: showBack,
      title: '关于',
      child: Scrollbar(
        thumbVisibility: true,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(28, 12, 42, 42),
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 980),
              child: Column(
                children: [
                  const _PageHeading(
                    title: '关于 Art3m1s',
                    caption: 'Artemis 视觉小说引擎前端',
                  ),
                  const SizedBox(height: 30),
                  Ps5Panel(
                    opaque: true,
                    padding: const EdgeInsets.all(26),
                    child: Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Image.asset(
                            AppInfo.logoAsset,
                            width: 104,
                            height: 104,
                            fit: BoxFit.cover,
                          ),
                        ),
                        const SizedBox(width: 24),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Art3m1s',
                                style: TextStyle(
                                  color: Ps5Colors.text,
                                  fontSize: 32,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 7),
                              Text(
                                '版本 ${AppInfo.displayVersion} · MPL-2.0',
                                style: const TextStyle(
                                  color: Ps5Colors.textMuted,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 14),
                              const Text(
                                '桌面大屏界面 · 本地资料库 · Artemis / FVP / Kirikiri 多引擎运行',
                                style: TextStyle(
                                  color: Ps5Colors.textMuted,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 26),
                  Ps5Section(
                    title: '仓库',
                    children: [
                      _RepoRow(label: 'Flutter App', url: _appRepository),
                      _RepoRow(label: 'Rust Core', url: _coreRepository),
                    ],
                  ),
                  const SizedBox(height: 26),
                  Ps5Section(
                    title: '开源与依赖',
                    children: [
                      Ps5SettingRow(
                        label: '第三方许可证',
                        caption: 'Flutter、Dart 与 Rust 依赖的完整许可文本',
                        control: Ps5Button(
                          icon: Icons.article_outlined,
                          onPressed: () {
                            Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => const _Ps5LicensesPage(),
                              ),
                            );
                          },
                          child: const Text('查看'),
                        ),
                      ),
                      const Ps5SettingRow(
                        label: 'Flutter / Dart',
                        caption:
                            'flutter_riverpod · path_provider · shared_preferences · ffi',
                        control: SizedBox.shrink(),
                      ),
                      const Ps5SettingRow(
                        label: 'Rust / Native',
                        caption:
                            'art3m1s-core · asb-interpreter · pfs-upk-rust · mlua · ANGLE',
                        control: SizedBox.shrink(),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Ps5SubpageFrame extends StatelessWidget {
  const _Ps5SubpageFrame({
    required this.showBack,
    required this.title,
    required this.child,
  });

  final bool showBack;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!showBack) return child;
    return Scaffold(
      backgroundColor: Ps5Colors.background,
      body: SafeArea(
        child: Column(
          children: [
            SizedBox(
              height: 76,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 22),
                child: Row(
                  children: [
                    Ps5IconButton(
                      icon: Icons.arrow_back_rounded,
                      tooltip: '返回',
                      autofocus: true,
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    const SizedBox(width: 14),
                    Text(
                      title,
                      style: const TextStyle(
                        color: Ps5Colors.text,
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const Divider(height: 1, color: Ps5Colors.line),
            Expanded(child: child),
          ],
        ),
      ),
    );
  }
}

class _PageHeading extends StatelessWidget {
  const _PageHeading({required this.title, required this.caption});

  final String title;
  final String caption;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Ps5Colors.text,
              fontSize: 34,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            caption,
            style: const TextStyle(color: Ps5Colors.textMuted, fontSize: 14),
          ),
        ],
      ),
    );
  }
}

class _RepoRow extends StatelessWidget {
  const _RepoRow({required this.label, required this.url});

  final String label;
  final String url;

  @override
  Widget build(BuildContext context) {
    return Ps5SettingRow(
      label: label,
      caption: url,
      control: Ps5Button(
        icon: Icons.copy_rounded,
        onPressed: () async {
          await Clipboard.setData(ClipboardData(text: url));
          if (context.mounted) notify(context, '已复制');
        },
        child: const Text('复制'),
      ),
    );
  }
}

class _Ps5LicensesPage extends StatefulWidget {
  const _Ps5LicensesPage();

  @override
  State<_Ps5LicensesPage> createState() => _Ps5LicensesPageState();
}

class _Ps5LicensesPageState extends State<_Ps5LicensesPage> {
  late final Future<List<PackageLicenses>> _licenses = collectLicenses();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Ps5Colors.background,
      body: SafeArea(
        child: Column(
          children: [
            SizedBox(
              height: 76,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 22),
                child: Row(
                  children: [
                    Ps5IconButton(
                      icon: Icons.arrow_back_rounded,
                      tooltip: '返回',
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    const SizedBox(width: 14),
                    const Text(
                      '第三方许可证',
                      style: TextStyle(
                        color: Ps5Colors.text,
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const Divider(height: 1, color: Ps5Colors.line),
            Expanded(
              child: FutureBuilder<List<PackageLicenses>>(
                future: _licenses,
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const Center(
                      child: CircularProgressIndicator(
                        color: Ps5Colors.accent,
                        strokeWidth: 2.4,
                      ),
                    );
                  }
                  final packages = snapshot.data!;
                  return ListView.builder(
                    padding: const EdgeInsets.fromLTRB(24, 18, 24, 28),
                    itemCount: packages.length,
                    itemBuilder: (context, index) {
                      final package = packages[index];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Ps5Panel(
                          child: ListTile(
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) =>
                                      _LicenseDetailPage(package: package),
                                ),
                              );
                            },
                            leading: const Icon(
                              Icons.inventory_2_outlined,
                              color: Ps5Colors.accent,
                            ),
                            title: Text(
                              package.package,
                              style: const TextStyle(
                                color: Ps5Colors.text,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            subtitle: Text(
                              '${package.licenses.length} 项授权',
                              style: const TextStyle(
                                color: Ps5Colors.textMuted,
                                fontSize: 12,
                              ),
                            ),
                            trailing: const Icon(
                              Icons.chevron_right_rounded,
                              color: Ps5Colors.textMuted,
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LicenseDetailPage extends StatelessWidget {
  const _LicenseDetailPage({required this.package});

  final PackageLicenses package;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Ps5Colors.background,
      body: SafeArea(
        child: Column(
          children: [
            SizedBox(
              height: 76,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 22),
                child: Row(
                  children: [
                    Ps5IconButton(
                      icon: Icons.arrow_back_rounded,
                      tooltip: '返回',
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        package.package,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Ps5Colors.text,
                          fontSize: 21,
                          fontWeight: FontWeight.w700,
                        ),
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
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(26, 22, 26, 40),
                  children: [
                    for (final paragraphs in package.licenses) ...[
                      SelectableText(
                        licenseText(paragraphs),
                        style: const TextStyle(
                          color: Ps5Colors.textMuted,
                          fontSize: 12,
                          height: 1.55,
                        ),
                      ),
                      const SizedBox(height: 28),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
