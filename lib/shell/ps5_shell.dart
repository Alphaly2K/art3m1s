import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../adaptive/feedback.dart';
import '../adaptive/ps5_chrome.dart';
import '../adaptive/ps5_menu.dart';
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
import '../widgets/ps5_osk.dart';
import 'ps5_game_library.dart';

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
  late final Animation<double> _startupFade;
  late final Animation<double> _startupScale;
  late final Animation<double> _startupMorph;

  @override
  void initState() {
    super.initState();
    _intro = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1900),
    )..forward();
    _introFade = CurvedAnimation(
      parent: _intro,
      curve: const Interval(0.48, 0.92, curve: Curves.easeOutCubic),
    );
    _introSlide = Tween<Offset>(begin: const Offset(0, 0.025), end: Offset.zero)
        .animate(
          CurvedAnimation(
            parent: _intro,
            curve: const Interval(0.48, 1, curve: Curves.easeOutBack),
          ),
        );
    _startupFade = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 0,
          end: 1,
        ).chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 24,
      ),
      TweenSequenceItem(tween: ConstantTween<double>(1), weight: 42),
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 1,
          end: 0,
        ).chain(CurveTween(curve: Curves.easeInCubic)),
        weight: 34,
      ),
    ]).animate(_intro);
    _startupScale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 0.94,
          end: 1,
        ).chain(CurveTween(curve: Curves.easeOutBack)),
        weight: 66,
      ),
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 1,
          end: 1.035,
        ).chain(CurveTween(curve: Curves.easeInCubic)),
        weight: 34,
      ),
    ]).animate(_intro);
    _startupMorph = CurvedAnimation(
      parent: _intro,
      curve: const Interval(0, 0.46, curve: Curves.easeOutCubic),
    );
  }

  @override
  void dispose() {
    _intro.dispose();
    super.dispose();
  }

  void _openSettings() {
    unawaited(
      Navigator.of(
        context,
      ).push<void>(_ps5SettingsRoute(const _Ps5SettingsHome())),
    );
  }

  void _openAbout() {
    unawaited(
      Navigator.of(context).push<void>(
        _ps5SettingsRoute(
          const Ps5SettingsFrame(title: '关于', child: _Ps5AboutPage()),
        ),
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
    // Esc 永远不退出大屏：对话框与子页面各自处理返回键；首页上的 Esc
    // 直接吞掉。只有手柄 B（circle）在首页路由为当前路由时才退出大屏，
    // 避免对话框开着时按键穿透到首页触发退出。
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      return KeyEventResult.handled;
    }
    if (action == Ps5InputAction.back && widget.onExitBigScreen != null) {
      if (ModalRoute.of(context)?.isCurrent == true) {
        unawaited(widget.onExitBigScreen!());
      }
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
              ExcludeFocus(
                excluding: _searchOpen,
                child: FadeTransition(
                  opacity: _introFade,
                  child: SlideTransition(
                    position: _introSlide,
                    child: SafeArea(
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 360),
                              switchInCurve: Curves.linear,
                              switchOutCurve: Curves.linear,
                              layoutBuilder: (currentChild, previousChildren) =>
                                  Stack(
                                    fit: StackFit.expand,
                                    children: [
                                      ...previousChildren,
                                      ?currentChild,
                                    ],
                                  ),
                              transitionBuilder: (child, animation) {
                                final fade = CurvedAnimation(
                                  parent: animation,
                                  curve: const Interval(
                                    0,
                                    0.78,
                                    curve: Curves.easeOut,
                                  ),
                                  reverseCurve: Curves.easeInCubic,
                                );
                                final motion = CurvedAnimation(
                                  parent: animation,
                                  curve: Curves.easeOutBack,
                                  reverseCurve: Curves.easeInCubic,
                                );
                                return FadeTransition(
                                  opacity: fade,
                                  child: SlideTransition(
                                    position: Tween<Offset>(
                                      begin: const Offset(0.018, 0.012),
                                      end: Offset.zero,
                                    ).animate(motion),
                                    child: ScaleTransition(
                                      scale: Tween<double>(
                                        begin: 0.992,
                                        end: 1,
                                      ).animate(motion),
                                      child: child,
                                    ),
                                  ),
                                );
                              },
                              child: _tab == 0
                                  ? ClipRect(
                                      key: const ValueKey('games'),
                                      child: _Ps5LibraryPage(
                                        query: _searchQuery,
                                      ),
                                    )
                                  : Ps5GameLibraryPage(
                                      key: const ValueKey('game-library'),
                                      onClose: () => setState(() => _tab = 0),
                                    ),
                            ),
                          ),
                          Align(
                            alignment: Alignment.topCenter,
                            child: _Ps5TopBar(
                              tab: _tab,
                              onTab: (value) => setState(() => _tab = value),
                              onSearch: () =>
                                  setState(() => _searchOpen = true),
                              onSettings: _openSettings,
                              onProfile: _openAbout,
                              onExitBigScreen: widget.onExitBigScreen,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Positioned.fill(
                child: IgnorePointer(
                  child: FadeTransition(
                    opacity: _startupFade,
                    child: ScaleTransition(
                      scale: _startupScale,
                      child: AnimatedBuilder(
                        animation: _startupMorph,
                        builder: (context, _) =>
                            _Ps5StartupLogo(progress: _startupMorph.value),
                      ),
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

class _Ps5StartupLogo extends StatelessWidget {
  const _Ps5StartupLogo({required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox.square(
            dimension: 148,
            child: CustomPaint(
              painter: _Ps5StartupLogoPainter(progress: progress),
            ),
          ),
          const SizedBox(height: 22),
          Text(
            'ART3M1S',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.86),
              fontSize: 18,
              fontWeight: FontWeight.w400,
              letterSpacing: 7.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _Ps5StartupLogoPainter extends CustomPainter {
  const _Ps5StartupLogoPainter({this.progress = 1});

  final double progress;

  static double _phase(double start, double end, double value) {
    return ((value - start) / (end - start)).clamp(0, 1).toDouble();
  }

  static void _drawPathProgress(
    Canvas canvas,
    Path path,
    Paint paint,
    double progress,
  ) {
    if (progress <= 0) return;
    for (final metric in path.computeMetrics()) {
      canvas.drawPath(metric.extractPath(0, metric.length * progress), paint);
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.shortestSide / 148;
    canvas.scale(scale, scale);
    final crescentProgress = Curves.easeOutCubic.transform(
      _phase(0, 0.68, progress),
    );
    final threeProgress = Curves.easeOutBack.transform(
      _phase(0.18, 0.82, progress),
    );
    final arrowProgress = Curves.easeOutCubic.transform(
      _phase(0.38, 1, progress),
    );
    final line = Paint()
      ..color = Colors.white.withValues(alpha: 0.9)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final crescent = Path()
      ..moveTo(117, 28)
      ..cubicTo(91, 7, 43, 12, 22, 46)
      ..cubicTo(-1, 83, 21, 130, 63, 137)
      ..cubicTo(94, 142, 121, 126, 133, 103)
      ..cubicTo(112, 125, 79, 126, 57, 109)
      ..cubicTo(28, 86, 39, 45, 70, 32)
      ..cubicTo(85, 25, 102, 24, 117, 28);
    canvas.save();
    canvas.translate(74, 74);
    canvas.rotate(-0.13 * (1 - crescentProgress));
    canvas.translate(-74 - 14 * (1 - crescentProgress), -74);
    _drawPathProgress(canvas, crescent, line, crescentProgress);
    canvas.restore();

    final three = Path()
      ..moveTo(68, 57)
      ..cubicTo(101, 45, 114, 70, 91, 80)
      ..cubicTo(119, 82, 116, 112, 80, 113)
      ..cubicTo(70, 113, 62, 111, 56, 108);
    canvas.save();
    canvas.translate(84, 84);
    canvas.scale(0.72 + 0.28 * threeProgress);
    canvas.translate(-84, -84);
    _drawPathProgress(
      canvas,
      three,
      line
        ..strokeWidth = 4.2
        ..color = Colors.white.withValues(alpha: 0.7 * threeProgress),
      _phase(0.1, 0.9, threeProgress),
    );
    canvas.restore();

    final arrow = Path()
      ..moveTo(28, 122)
      ..lineTo(112, 38)
      ..moveTo(96, 40)
      ..lineTo(115, 35)
      ..lineTo(110, 54);
    canvas.save();
    canvas.translate(-18 * (1 - arrowProgress), 16 * (1 - arrowProgress));
    _drawPathProgress(
      canvas,
      arrow,
      line
        ..strokeWidth = 5
        ..color = Colors.white.withValues(alpha: 0.96 * arrowProgress),
      arrowProgress,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_Ps5StartupLogoPainter oldDelegate) {
    return oldDelegate.progress != progress;
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
                  label: 'Game Library',
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
  const _Ps5LibraryPage({required this.query});

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

  /// 指针悬停/键盘焦点进入某张卡片时，只朝该卡方向步进一格；卡片滑动后
  /// 指针下的下一张卡会继续触发，从而形成逐卡步进而非跳变。
  void _stepSelectionToward(int index) {
    if (index == _selectedIndex) return;
    setState(() {
      _selectedIndex += index > _selectedIndex ? 1 : -1;
    });
  }

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
            const SizedBox(height: 96),
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
                          duration: const Duration(milliseconds: 360),
                          curve: Curves.easeOutBack,
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
                                  onFocus: () => _stepSelectionToward(index),
                                  onPressed: actions.pickDirectory,
                                  onTap: () {
                                    if (_selectedIndex != index) {
                                      setState(() => _selectedIndex = index);
                                    } else {
                                      actions.pickDirectory();
                                    }
                                  },
                                )
                              : _GameTile(
                                  key: ValueKey(
                                    'ps5-game-tile-slot-${games[index].path}',
                                  ),
                                  entry: games[index],
                                  selected: index == _selectedIndex,
                                  autofocus: index == _selectedIndex,
                                  onFocus: () => _stepSelectionToward(index),
                                  onOpen: () => actions.launch(games[index]),
                                  onTap: () {
                                    if (_selectedIndex != index) {
                                      setState(() => _selectedIndex = index);
                                    } else {
                                      actions.launch(games[index]);
                                    }
                                  },
                                ),
                        ),
                      AnimatedPositioned(
                        duration: const Duration(milliseconds: 360),
                        curve: Curves.easeOutBack,
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
                child: _HeroCopySwitcher(entry: selected, actions: actions),
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
      duration: const Duration(milliseconds: 300),
      reverseDuration: const Duration(milliseconds: 180),
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

/// 左下角游戏简介（大标题 + meta 行 + 操作按钮）：切换选中游戏时先完整
/// 淡出旧内容，再重建为新内容并播放淡入+上滑动画，避免交叉叠化期间新旧
/// 文本同帧重叠。模式与 [_CarouselTitle] 一致。
class _HeroCopySwitcher extends StatefulWidget {
  const _HeroCopySwitcher({required this.entry, required this.actions});

  final GameEntry entry;
  final LibraryActions actions;

  @override
  State<_HeroCopySwitcher> createState() => _HeroCopySwitcherState();
}

class _HeroCopySwitcherState extends State<_HeroCopySwitcher>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;
  final GlobalKey _gameMenuButtonKey = GlobalKey();
  late GameEntry _shown = widget.entry;
  bool _swapping = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
      reverseDuration: const Duration(milliseconds: 200),
    )..forward();
    final curved = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    _fade = curved;
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.045),
      end: Offset.zero,
    ).animate(curved);
  }

  @override
  void didUpdateWidget(_HeroCopySwitcher oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.entry.path == _shown.path || _swapping) return;
    _swapping = true;
    _controller.reverse().then((_) {
      if (!mounted) return;
      setState(() => _shown = widget.entry);
      _swapping = false;
      _controller.forward(from: 0);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Rect? _gameMenuAnchor() {
    final box = _gameMenuButtonKey.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  Future<void> _showGameActionsMenu(GameEntry selected) async {
    final result = await showPs5ListMenu<int>(
      context,
      anchor: _gameMenuAnchor(),
      sections: [
        Ps5MenuSection(
          items: [
            const Ps5MenuItem(id: 'play', label: '开始游戏', value: 0),
            const Ps5MenuItem(id: 'edit', label: '编辑项目', value: 1),
            const Ps5MenuItem(
              id: 'delete',
              label: '从库中移除',
              value: 2,
              destructive: true,
            ),
          ],
        ),
      ],
    );
    if (!mounted || result == null) return;
    switch (result.itemId) {
      case 'play':
        widget.actions.launch(selected);
      case 'edit':
        widget.actions.editGame(selected);
      case 'delete':
        widget.actions.confirmDelete(selected);
    }
  }

  @override
  Widget build(BuildContext context) {
    final meta = <String>[
      _shown.engine.label,
      _shown.source == GameSource.directory ? '工程目录' : 'PFS',
      if (_shown.translationEnabled) '翻译',
    ].join(' · ');
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(
        position: _slide,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _shown.displayNameOrName,
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
            Text(
              meta,
              style: const TextStyle(color: Ps5Colors.textMuted, fontSize: 14),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                _HeroActionButton(
                  label: 'Play',
                  icon: Icons.play_arrow_rounded,
                  onPressed: () => widget.actions.launch(_shown),
                  wide: true,
                ),
                const SizedBox(width: 12),
                _HeroActionButton(
                  key: _gameMenuButtonKey,
                  icon: Icons.more_horiz_rounded,
                  tooltip: '项目操作',
                  onPressed: () => _showGameActionsMenu(_shown),
                ),
              ],
            ),
          ],
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
    super.key,
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
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final active = _focused || _hovered;
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
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() {
          _hovered = false;
          _pressed = false;
        }),
        child: AnimatedScale(
          scale: _pressed
              ? 0.965
              : active
              ? 1.035
              : 1,
          duration: Duration(milliseconds: _pressed ? 70 : 210),
          curve: _pressed ? Curves.easeOutCubic : Curves.easeOutBack,
          child: Stack(
            children: [
              Material(
                color: active
                    ? const Color(0xFFD7D9DC)
                    : const Color(0xCC20242A),
                borderRadius: BorderRadius.circular(999),
                child: InkWell(
                  onTap: widget.onPressed,
                  onHighlightChanged: (value) =>
                      setState(() => _pressed = value),
                  borderRadius: BorderRadius.circular(999),
                  hoverColor: Colors.transparent,
                  focusColor: Colors.transparent,
                  splashColor: Colors.white.withValues(alpha: 0.08),
                  child: SizedBox(
                    width: widget.wide ? 268 : 68,
                    height: 64,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (widget.icon != null)
                          Icon(
                            widget.icon,
                            color: active
                                ? Ps5Colors.background
                                : Ps5Colors.text,
                            size: 25,
                          ),
                        if (widget.label != null) ...[
                          const SizedBox(width: 10),
                          Text(
                            widget.label!,
                            style: TextStyle(
                              color: active
                                  ? Ps5Colors.background
                                  : Ps5Colors.text,
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
              Positioned.fill(
                child: Ps5AnimatedFocusBorder(
                  active: active,
                  borderRadius: 999,
                  strokeWidth: 1.8,
                ),
              ),
            ],
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
        constraints: const BoxConstraints(maxWidth: 460),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox.square(
              dimension: 96,
              child: CustomPaint(painter: _Ps5StartupLogoPainter()),
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
  final ScrollController _scrollController = ScrollController();
  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
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
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Color(0xF23A373A),
                        Color(0xF21C222D),
                        Color(0xF20C121B),
                      ],
                      stops: [0, 0.48, 1],
                    ),
                    borderRadius: BorderRadius.circular(3),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0xA6000000),
                        blurRadius: 34,
                        offset: Offset(0, 16),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _Ps5SearchField(
                        controller: _controller,
                        onChanged: (value) =>
                            setState(() => _query = value.toLowerCase()),
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
                            : Scrollbar(
                                controller: _scrollController,
                                thumbVisibility: true,
                                thickness: 3,
                                radius: const Radius.circular(2),
                                child: ListView.builder(
                                  controller: _scrollController,
                                  shrinkWrap: true,
                                  clipBehavior: Clip.none,
                                  padding: const EdgeInsets.only(right: 12),
                                  itemCount: results.length,
                                  itemBuilder: (context, index) {
                                    final entry = results[index];
                                    return _Ps5SearchResultRow(
                                      entry: entry,
                                      onPressed: () => widget.onSelected(entry),
                                    );
                                  },
                                ),
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

class _Ps5SearchField extends StatefulWidget {
  const _Ps5SearchField({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  State<_Ps5SearchField> createState() => _Ps5SearchFieldState();
}

class _Ps5SearchFieldState extends State<_Ps5SearchField> {
  late final FocusNode _focusNode = FocusNode(debugLabel: 'PS5 search field')
    ..addListener(_handleFocusChange);

  void _handleFocusChange() {
    if (mounted) setState(() {});
  }

  Future<void> _openKeyboard() async {
    final result = await showPs5OnScreenKeyboard(
      context,
      title: 'Search games',
      initialValue: widget.controller.text,
      hintText: 'Search games',
    );
    if (!mounted || result == null) return;
    widget.controller.text = result;
    widget.onChanged(result);
  }

  @override
  void dispose() {
    _focusNode
      ..removeListener(_handleFocusChange)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final focused = _focusNode.hasFocus;
    return Shortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.numpadEnter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.gameButtonA): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.gameButton8): ActivateIntent(),
      },
      child: Actions(
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              unawaited(_openKeyboard());
              return null;
            },
          ),
        },
        child: Stack(
          children: [
            TextField(
              controller: widget.controller,
              focusNode: _focusNode,
              autofocus: true,
              readOnly: true,
              onTap: () => unawaited(_openKeyboard()),
              style: const TextStyle(color: Ps5Colors.text, fontSize: 20),
              cursorColor: Ps5Colors.accent,
              decoration: InputDecoration(
                hintText: 'Search games',
                hintStyle: const TextStyle(color: Ps5Colors.textMuted),
                prefixIcon: const Icon(
                  Icons.search_rounded,
                  color: Ps5Colors.textMuted,
                ),
                filled: true,
                fillColor: focused
                    ? const Color(0xB51B222D)
                    : const Color(0x99101620),
                border: const OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(1)),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: const OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(1)),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: const OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(1)),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            Positioned.fill(
              child: Ps5AnimatedFocusBorder(
                active: focused,
                borderRadius: 1,
                strokeWidth: 1.7,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Ps5SearchResultRow extends StatefulWidget {
  const _Ps5SearchResultRow({required this.entry, required this.onPressed});

  final GameEntry entry;
  final VoidCallback onPressed;

  @override
  State<_Ps5SearchResultRow> createState() => _Ps5SearchResultRowState();
}

class _Ps5SearchResultRowState extends State<_Ps5SearchResultRow> {
  bool _focused = false;
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final active = _focused || _hovered;
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: FocusableActionDetector(
        onFocusChange: (value) => setState(() => _focused = value),
        mouseCursor: SystemMouseCursors.click,
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
        child: MouseRegion(
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() {
            _hovered = false;
            _pressed = false;
          }),
          child: GestureDetector(
            onTap: widget.onPressed,
            onTapDown: (_) => setState(() => _pressed = true),
            onTapUp: (_) => setState(() => _pressed = false),
            onTapCancel: () => setState(() => _pressed = false),
            child: AnimatedScale(
              scale: _pressed
                  ? 0.985
                  : active
                  ? 1.012
                  : 1,
              duration: Duration(milliseconds: _pressed ? 70 : 180),
              curve: _pressed ? Curves.easeOutCubic : Curves.easeOutBack,
              child: Stack(
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    curve: Curves.easeOutCubic,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 13,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: active
                          ? const Color(0x3D8C929A)
                          : const Color(0x66101620),
                      border: Border.all(
                        color: active
                            ? const Color(0xFF636870)
                            : Colors.transparent,
                      ),
                    ),
                    child: Row(
                      children: [
                        SizedBox.square(
                          dimension: 48,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(3),
                            child: _CoverArt(entry: widget.entry),
                          ),
                        ),
                        const SizedBox(width: 13),
                        Expanded(
                          child: Text(
                            widget.entry.displayNameOrName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Ps5Colors.text,
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
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
                  Positioned.fill(
                    child: Ps5AnimatedFocusBorder(
                      active: active,
                      borderRadius: 1,
                      strokeWidth: 1.6,
                    ),
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

class _AddGameTile extends StatelessWidget {
  const _AddGameTile({
    required this.selected,
    required this.autofocus,
    required this.onFocus,
    required this.onPressed,
    required this.onTap,
  });

  final bool selected;
  final bool autofocus;
  final VoidCallback onFocus;
  final VoidCallback onPressed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final active = selected;
    return FocusableActionDetector(
      autofocus: autofocus,
      onFocusChange: (value) {
        if (value) onFocus();
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
            onPressed();
            return null;
          },
        ),
      },
      child: AnimatedScale(
        scale: active ? _Ps5LibraryPageState._selectedTileScale : 1,
        alignment: Alignment.topCenter,
        duration: const Duration(milliseconds: 340),
        curve: Curves.easeOutBack,
        child: MouseRegion(
          onEnter: (_) => onFocus(),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: SizedBox.square(
              dimension: _Ps5LibraryPageState._carouselTileSize,
              child: Ps5FocusFrame(
                selected: active,
                child: Material(
                  color: Ps5Colors.backgroundRaised.withValues(alpha: 0.66),
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
      ),
    );
  }
}

class _GameTile extends StatelessWidget {
  const _GameTile({
    super.key,
    required this.entry,
    required this.selected,
    required this.autofocus,
    required this.onFocus,
    required this.onOpen,
    required this.onTap,
  });

  final GameEntry entry;
  final bool selected;
  final bool autofocus;
  final VoidCallback onFocus;
  final VoidCallback onOpen;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final active = selected;
    return FocusableActionDetector(
      autofocus: autofocus,
      onFocusChange: (value) {
        if (value) onFocus();
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
            onOpen();
            return null;
          },
        ),
      },
      child: AnimatedScale(
        key: ValueKey('ps5-game-tile-${entry.path}'),
        scale: active ? _Ps5LibraryPageState._selectedTileScale : 1,
        alignment: Alignment.topCenter,
        duration: const Duration(milliseconds: 340),
        curve: Curves.easeOutBack,
        child: MouseRegion(
          onEnter: (_) => onFocus(),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: SizedBox.square(
              dimension: _Ps5LibraryPageState._carouselTileSize,
              child: Ps5FocusFrame(
                selected: active,
                child: _CoverArt(entry: entry),
              ),
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

Route<T> _ps5SettingsRoute<T>(Widget page) {
  return PageRouteBuilder<T>(
    opaque: true,
    transitionDuration: const Duration(milliseconds: 380),
    reverseTransitionDuration: const Duration(milliseconds: 280),
    pageBuilder: (context, animation, secondaryAnimation) => page,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final fade = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      final motion = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: fade,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0.075, 0),
            end: Offset.zero,
          ).animate(motion),
          child: child,
        ),
      );
    },
  );
}

class _Ps5SettingsHome extends StatelessWidget {
  const _Ps5SettingsHome();

  void _open(BuildContext context, String title, Widget child) {
    Navigator.of(context).push<void>(
      _ps5SettingsRoute(Ps5SettingsFrame(title: title, child: child)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Ps5SettingsFrame(
      title: '设置',
      showBack: false,
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1180),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(48, 54, 48, 72),
            children: [
              _Ps5SettingsNavItem(
                icon: Icons.display_settings_outlined,
                label: '图形与显示',
                caption: '图形后端、超分输出与显示选项',
                autofocus: true,
                onPressed: () => _open(
                  context,
                  '图形与显示',
                  const _Ps5SettingsPage(
                    section: _Ps5SettingsSection.rendering,
                  ),
                ),
              ),
              const _Ps5SettingsDivider(),
              _Ps5SettingsNavItem(
                icon: Icons.sports_esports_outlined,
                label: '游戏与辅助',
                caption: '文本翻译与游戏内显示',
                onPressed: () => _open(
                  context,
                  '游戏与辅助',
                  const _Ps5SettingsPage(section: _Ps5SettingsSection.runtime),
                ),
              ),
              const _Ps5SettingsDivider(),
              _Ps5SettingsNavItem(
                icon: Icons.bug_report_outlined,
                label: '开发者与诊断',
                caption: '调试、性能信息与日志导出',
                onPressed: () => _open(
                  context,
                  '开发者与诊断',
                  const _Ps5SettingsPage(section: _Ps5SettingsSection.debug),
                ),
              ),
              const _Ps5SettingsDivider(),
              _Ps5SettingsNavItem(
                icon: Icons.info_outline_rounded,
                label: '关于 Art3m1s',
                caption: '版本、项目仓库与第三方许可证',
                onPressed: () => _open(context, '关于', const _Ps5AboutPage()),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Ps5SettingsDivider extends StatelessWidget {
  const _Ps5SettingsDivider();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(left: 84, right: 24),
      child: Divider(height: 1, thickness: 0.6, color: Color(0x28FFFFFF)),
    );
  }
}

class _Ps5SettingsNavItem extends StatefulWidget {
  const _Ps5SettingsNavItem({
    required this.icon,
    required this.label,
    required this.caption,
    required this.onPressed,
    this.autofocus = false,
  });

  final IconData icon;
  final String label;
  final String caption;
  final VoidCallback onPressed;
  final bool autofocus;

  @override
  State<_Ps5SettingsNavItem> createState() => _Ps5SettingsNavItemState();
}

class _Ps5SettingsNavItemState extends State<_Ps5SettingsNavItem> {
  bool _focused = false;
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final active = _focused || _hovered;
    return FocusableActionDetector(
      autofocus: widget.autofocus,
      onFocusChange: (value) => setState(() => _focused = value),
      mouseCursor: SystemMouseCursors.click,
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
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onPressed,
          child: Stack(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                curve: Curves.easeOutCubic,
                constraints: const BoxConstraints(minHeight: 92),
                padding: const EdgeInsets.symmetric(
                  horizontal: 26,
                  vertical: 18,
                ),
                decoration: BoxDecoration(
                  color: active ? const Color(0x2AFFFFFF) : Colors.transparent,
                  border: Border.all(
                    color: active
                        ? const Color(0xFF60656D)
                        : Colors.transparent,
                  ),
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: 58,
                      child: Icon(
                        widget.icon,
                        color: active ? Ps5Colors.text : Ps5Colors.menuMuted,
                        size: 30,
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            widget.label,
                            style: const TextStyle(
                              color: Ps5Colors.text,
                              fontSize: 21,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            widget.caption,
                            style: const TextStyle(
                              color: Ps5Colors.menuMuted,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(
                      Icons.chevron_right_rounded,
                      color: Ps5Colors.menuMuted,
                      size: 26,
                    ),
                  ],
                ),
              ),
              Positioned.fill(
                child: Ps5AnimatedFocusBorder(
                  active: active,
                  borderRadius: 1,
                  strokeWidth: 2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _Ps5SettingsSection { rendering, runtime, debug }

class _Ps5SettingsPage extends ConsumerWidget {
  const _Ps5SettingsPage({required this.section});

  final _Ps5SettingsSection section;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final backends = availableBackends();
    final selectedBackend = backends.firstWhere(
      (backend) => backend.value == settings.backend,
      orElse: () => backends.first,
    );

    return Scrollbar(
      thumbVisibility: true,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(48, 30, 48, 72),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1200),
            child: Column(
              children: [
                if (section == _Ps5SettingsSection.rendering)
                  Ps5Section(
                    title: '渲染',
                    children: [
                      Ps5SettingRow(
                        label: '图形后端',
                        caption: backendName(selectedBackend.value),
                        trailing: selectedBackend.label,
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
                      ),
                      if (supportsSpatialUpscalingSettings(settings.backend))
                        Ps5SettingRow(
                          label: '超分输出',
                          caption: renderOutputDescription(
                            settings.renderOutputMode,
                            customWidth: settings.customRenderWidth,
                            customHeight: settings.customRenderHeight,
                          ),
                          trailing: settings.renderOutputMode.label,
                          onPressed: () async {
                            final value =
                                await showPs5OptionPicker<RenderOutputMode>(
                                  context,
                                  title: '超分输出',
                                  selected: settings.renderOutputMode,
                                  options: [
                                    for (final mode in RenderOutputMode.values)
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
                        ),
                      if (supportsSpatialUpscalingSettings(settings.backend) &&
                          settings.renderOutputMode == RenderOutputMode.custom)
                        Ps5SettingRow(
                          label: '自定义分辨率',
                          caption: '输出保持游戏原始宽高比',
                          trailing:
                              '${settings.customRenderWidth} × ${settings.customRenderHeight}',
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
                        ),
                    ],
                  ),
                if (section == _Ps5SettingsSection.runtime)
                  Ps5Section(
                    title: '运行时',
                    children: [
                      Ps5SettingRow(
                        label: '文本翻译',
                        caption: '离线补丁与在线翻译服务',
                        trailing: settings.translation.mode.label,
                        onPressed: () {
                          Navigator.of(context).push(
                            _ps5SettingsRoute<void>(
                              const Ps5TranslationSettingsScreen(),
                            ),
                          );
                        },
                      ),
                      Ps5SettingRow(
                        label: '显示帧率',
                        caption: '在游戏画面上显示实时 FPS',
                        control: Ps5Switch(
                          value: settings.showFps,
                          onChanged: notifier.setShowFps,
                        ),
                        onPressed: () => notifier.setShowFps(!settings.showFps),
                      ),
                    ],
                  ),
                if (section == _Ps5SettingsSection.debug)
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
                        onPressed: () =>
                            notifier.setDebugMode(!settings.debugMode),
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
                        onPressed: settings.debugMode
                            ? () => notifier.setDamageVisualization(
                                !settings.damageVisualization,
                              )
                            : null,
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
                        onPressed: settings.debugMode
                            ? () => notifier.setProfilerOverlay(
                                !settings.profilerOverlay,
                              )
                            : null,
                      ),
                      Ps5SettingRow(
                        label: '调试面板',
                        caption: '显示浮动监控面板',
                        control: Ps5Switch(
                          value: settings.debugOverlay,
                          onChanged: notifier.setDebugOverlay,
                        ),
                        onPressed: () =>
                            notifier.setDebugOverlay(!settings.debugOverlay),
                      ),
                      Ps5SettingRow(
                        label: '崩溃与错误上报',
                        caption: '上传不含游戏内容的诊断信息，重启后完全生效',
                        control: Ps5Switch(
                          value: settings.crashReportingEnabled,
                          onChanged: notifier.setCrashReportingEnabled,
                        ),
                        onPressed: () => notifier.setCrashReportingEnabled(
                          !settings.crashReportingEnabled,
                        ),
                      ),
                      Ps5SettingRow(
                        label: '导出日志',
                        caption: '把当前会话日志写入文件',
                        trailing: '导出',
                        onPressed: () async {
                          final file = await Log.exportToFile();
                          if (context.mounted) {
                            notify(context, '已导出: ${file.path}');
                          }
                        },
                      ),
                    ],
                  ),
              ],
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
  const _Ps5AboutPage();

  static const _appRepository = 'https://github.com/Alphaly2K/art3m1s';
  static const _coreRepository = 'https://github.com/Alphaly2K/art3m1s-core';

  @override
  Widget build(BuildContext context) {
    return Scrollbar(
      thumbVisibility: true,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(48, 30, 48, 72),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1200),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const SizedBox.square(
                      dimension: 84,
                      child: CustomPaint(painter: _Ps5StartupLogoPainter()),
                    ),
                    const SizedBox(width: 18),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Art3m1s',
                            style: TextStyle(
                              color: Ps5Colors.text,
                              fontSize: 28,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '版本 ${AppInfo.displayVersion} · MPL-2.0',
                            style: const TextStyle(
                              color: Ps5Colors.textMuted,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 10),
                          const Text(
                            '桌面大屏界面 · 本地资料库 · Artemis / FVP / Kirikiri 多引擎运行',
                            style: TextStyle(
                              color: Ps5Colors.textMuted,
                              fontSize: 12,
                              height: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 30),
                const Ps5Section(
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
                      trailing: '查看',
                      onPressed: () {
                        Navigator.of(context).push(
                          _ps5SettingsRoute<void>(const _Ps5LicensesPage()),
                        );
                      },
                    ),
                    const Ps5SettingRow(
                      label: 'Flutter / Dart',
                      caption:
                          'flutter_riverpod · path_provider · shared_preferences · ffi',
                    ),
                    const Ps5SettingRow(
                      label: 'Rust / Native',
                      caption:
                          'art3m1s-core · asb-interpreter · pfs-upk-rust · mlua · ANGLE',
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
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
      trailing: '复制',
      onPressed: () async {
        await Clipboard.setData(ClipboardData(text: url));
        if (context.mounted) notify(context, '已复制');
      },
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
    return Ps5SettingsFrame(
      title: '第三方许可证',
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
          return Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1200),
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(48, 10, 48, 72),
                itemCount: packages.length,
                separatorBuilder: (context, index) => const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20),
                  child: Divider(
                    height: 1,
                    thickness: 0.6,
                    color: Ps5Colors.line,
                  ),
                ),
                itemBuilder: (context, index) {
                  final package = packages[index];
                  return Ps5SettingRow(
                    label: package.package,
                    caption: '${package.licenses.length} 项授权',
                    trailing: '查看',
                    onPressed: () {
                      Navigator.of(context).push(
                        _ps5SettingsRoute<void>(
                          _LicenseDetailPage(package: package),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          );
        },
      ),
    );
  }
}

class _LicenseDetailPage extends StatelessWidget {
  const _LicenseDetailPage({required this.package});

  final PackageLicenses package;

  @override
  Widget build(BuildContext context) {
    return Ps5SettingsFrame(
      title: package.package,
      child: Scrollbar(
        thumbVisibility: true,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(72, 10, 72, 72),
          children: [
            for (final paragraphs in package.licenses) ...[
              SelectableText(
                licenseText(paragraphs),
                style: const TextStyle(
                  color: Ps5Colors.textMuted,
                  fontSize: 13,
                  height: 1.6,
                ),
              ),
              const SizedBox(height: 28),
            ],
          ],
        ),
      ),
    );
  }
}
