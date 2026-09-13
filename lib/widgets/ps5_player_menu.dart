import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../adaptive/ps5_chrome.dart';
import '../adaptive/ps5_sounds.dart';
import '../controllers/ps5_input.dart';
import '../services/app_info.dart';

/// 大屏播放器路由守卫：消费菜单键并禁止系统返回意外退出游戏。
class Ps5PlayerRouteGuard extends StatelessWidget {
  const Ps5PlayerRouteGuard({
    super.key,
    required this.onToggleMenu,
    required this.child,
  });

  final VoidCallback onToggleMenu;
  final Widget child;

  static bool opensMenu(KeyEvent event) {
    final hardware = HardwareKeyboard.instance;
    return (event.logicalKey == LogicalKeyboardKey.tab &&
            hardware.isControlPressed &&
            hardware.isShiftPressed) ||
        ps5InputAction(event.logicalKey) == Ps5InputAction.menu;
  }

  KeyEventResult _handleKeyEvent(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    // PlayerScene 内 Esc 只允许交给已经打开的菜单处理；路由守卫永远吞掉，
    // 防止系统返回或 Material 路由把 Esc 当成退出大屏。
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      return KeyEventResult.handled;
    }
    if (!opensMenu(event)) return KeyEventResult.ignored;
    if (event is KeyDownEvent) onToggleMenu();
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      canRequestFocus: false,
      onKeyEvent: _handleKeyEvent,
      child: PopScope(canPop: false, child: child),
    );
  }
}

/// PS5 大屏游戏内菜单。
///
/// 主层只保留悬浮游戏信息与底部六项操作；设置/关于使用侧栏，
/// 音量/电源使用居中小面板。主体不使用整条卡片或分隔线，保持 PS5
/// 控制中心式的画面上下文与轻量焦点反馈。
class Ps5PlayerMenu extends StatefulWidget {
  const Ps5PlayerMenu({
    super.key,
    required this.title,
    required this.showFps,
    required this.addedAt,
    required this.engineLabel,
    required this.sourceLabel,
    required this.masterVolume,
    required this.onShowFpsChanged,
    required this.onResume,
    required this.onExit,
    this.lastPlayedAt,
    this.sessionStartedAt,
    this.screenshotPath,
    this.screenshotBusy = false,
    this.screenshotMessage,
    this.onScreenshot,
    this.onVolumeChanged,
    this.onExitBigScreen,
    this.onCloseApp,
  });

  final String title;
  final bool showFps;
  final DateTime addedAt;
  final DateTime? lastPlayedAt;
  final DateTime? sessionStartedAt;
  final String engineLabel;
  final String sourceLabel;
  final String? screenshotPath;
  final bool screenshotBusy;
  final String? screenshotMessage;
  final double masterVolume;
  final ValueChanged<bool> onShowFpsChanged;
  final VoidCallback onResume;
  final VoidCallback onExit;
  final FutureOr<void> Function()? onScreenshot;
  final ValueChanged<double>? onVolumeChanged;
  final FutureOr<void> Function()? onExitBigScreen;
  final FutureOr<void> Function()? onCloseApp;

  @override
  State<Ps5PlayerMenu> createState() => _Ps5PlayerMenuState();
}

enum _Ps5PlayerPanel { settings, volume, about, power }

class _Ps5PlayerMenuState extends State<Ps5PlayerMenu> {
  final FocusNode _mainActionFocus = FocusNode(
    debugLabel: 'ps5-player-main-action',
  );
  final FocusNode _panelFocus = FocusNode(debugLabel: 'ps5-player-panel');
  _Ps5PlayerPanel? _panel;

  static bool _isToggle(KeyEvent event) {
    final hardware = HardwareKeyboard.instance;
    return event.logicalKey == LogicalKeyboardKey.tab &&
        hardware.isControlPressed &&
        hardware.isShiftPressed;
  }

  static bool _isGamepadMenu(KeyEvent event) {
    return ps5InputAction(event.logicalKey) == Ps5InputAction.menu;
  }

  static bool _isBack(KeyEvent event) {
    return event.logicalKey == LogicalKeyboardKey.escape ||
        ps5InputAction(event.logicalKey) == Ps5InputAction.back;
  }

  void _resume() {
    Ps5UiSounds.back();
    widget.onResume();
  }

  void _closePanel({bool playSound = true}) {
    if (_panel == null) return;
    if (playSound) Ps5UiSounds.back();
    setState(() => _panel = null);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _mainActionFocus.requestFocus();
    });
  }

  void _openPanel(_Ps5PlayerPanel panel) {
    Ps5UiSounds.confirm();
    setState(() => _panel = panel);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _panelFocus.requestFocus();
    });
  }

  KeyEventResult _handleMenuKey(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (_isToggle(event) || _isGamepadMenu(event)) {
      _resume();
      return KeyEventResult.handled;
    }
    if (!_isBack(event)) return KeyEventResult.ignored;
    if (_panel != null) {
      _closePanel();
    } else {
      _resume();
    }
    return KeyEventResult.handled;
  }

  void _activateScreenshot() {
    if (widget.screenshotBusy || widget.onScreenshot == null) return;
    final result = widget.onScreenshot!();
    if (result is Future<void>) unawaited(result);
  }

  void _activateExitBigScreen() {
    final callback = widget.onExitBigScreen;
    if (callback == null) return;
    _closePanel(playSound: false);
    final result = callback();
    if (result is Future<void>) unawaited(result);
  }

  void _activateCloseApp() {
    final callback = widget.onCloseApp;
    if (callback == null) return;
    _closePanel(playSound: false);
    final result = callback();
    if (result is Future<void>) unawaited(result);
  }

  @override
  void dispose() {
    _mainActionFocus.dispose();
    _panelFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      key: const ValueKey('ps5-player-menu'),
      child: Focus(
        canRequestFocus: false,
        onKeyEvent: _handleMenuKey,
        child: FocusTraversalGroup(
          policy: OrderedTraversalPolicy(),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Positioned.fill(
                child: GestureDetector(
                  key: const ValueKey('ps5-player-menu-backdrop'),
                  behavior: HitTestBehavior.opaque,
                  onTap: _panel == null ? _resume : () => _closePanel(),
                  child: _Ps5PlayerMenuBackdrop(),
                ),
              ),
              const Positioned(
                right: 34,
                top: 24,
                child: SafeArea(bottom: false, child: _Ps5MenuClock()),
              ),
              Positioned(
                left: 28,
                right: 28,
                bottom: 22,
                child: SafeArea(
                  top: false,
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1380),
                      child: ExcludeFocus(
                        excluding: _panel != null,
                        child: AnimatedOpacity(
                          opacity: _panel == null ? 1 : 0.35,
                          duration: const Duration(milliseconds: 150),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _Ps5PlayerInfoRail(
                                title: widget.title,
                                screenshotPath: widget.screenshotPath,
                                addedAt: widget.addedAt,
                                lastPlayedAt: widget.lastPlayedAt,
                                sessionStartedAt: widget.sessionStartedAt,
                                engineLabel: widget.engineLabel,
                                sourceLabel: widget.sourceLabel,
                              ),
                              if (widget.screenshotMessage != null) ...[
                                const SizedBox(height: 8),
                                Text(
                                  widget.screenshotMessage!,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: Ps5Colors.textMuted,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                              const SizedBox(height: 18),
                              _Ps5PlayerActionRail(
                                focusNode: _mainActionFocus,
                                showFps: widget.showFps,
                                screenshotBusy: widget.screenshotBusy,
                                masterVolume: widget.masterVolume,
                                onHome: widget.onExit,
                                onSettings: () =>
                                    _openPanel(_Ps5PlayerPanel.settings),
                                onScreenshot: _activateScreenshot,
                                onAbout: () =>
                                    _openPanel(_Ps5PlayerPanel.about),
                                onVolume: () =>
                                    _openPanel(_Ps5PlayerPanel.volume),
                                onPower: () =>
                                    _openPanel(_Ps5PlayerPanel.power),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              if (_panel != null) _buildSecondaryPanel(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSecondaryPanel(BuildContext context) {
    return switch (_panel!) {
      _Ps5PlayerPanel.settings => _buildSettingsPanel(),
      _Ps5PlayerPanel.volume => _buildVolumePanel(),
      _Ps5PlayerPanel.about => _buildAboutPanel(),
      _Ps5PlayerPanel.power => _buildPowerPanel(),
    };
  }

  Widget _buildSettingsPanel() {
    return _Ps5PanelOverlay(
      alignment: Alignment.centerRight,
      child: _Ps5SidePanel(
        title: '设置',
        onClose: _closePanel,
        child: Column(
          children: [
            Ps5SettingRow(
              label: '显示帧率',
              caption: widget.showFps ? '已开启' : '已关闭',
              control: Ps5Switch(
                value: widget.showFps,
                onChanged: widget.onShowFpsChanged,
              ),
            ),
            const Divider(height: 1, thickness: 0.6, color: Ps5Colors.line),
            const Ps5SettingRow(
              label: '菜单快捷键',
              caption: '键盘组合键；手柄使用 Menu / Options',
              trailing: 'CTRL+SHIFT+TAB',
              compact: true,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVolumePanel() {
    final volume = widget.masterVolume.clamp(0.0, 1.0);
    return _Ps5PanelOverlay(
      alignment: Alignment.center,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Ps5MenuPanel(
          width: 520,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(26, 22, 26, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        '音量',
                        style: TextStyle(
                          color: Ps5Colors.text,
                          fontSize: 22,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ),
                    Text(
                      '${(volume * 100).round()}%',
                      style: const TextStyle(
                        color: Ps5Colors.textMuted,
                        fontSize: 16,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 22),
                Row(
                  children: [
                    Icon(
                      volume <= 0.001
                          ? Icons.volume_off_rounded
                          : Icons.volume_up_rounded,
                      color: Ps5Colors.textMuted,
                      size: 24,
                    ),
                    const SizedBox(width: 18),
                    Expanded(
                      child: SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          activeTrackColor: Ps5Colors.accent,
                          inactiveTrackColor: Ps5Colors.line,
                          thumbColor: Ps5Colors.text,
                          overlayColor: Ps5Colors.accentSoft,
                          trackHeight: 2,
                          thumbShape: const RoundSliderThumbShape(
                            enabledThumbRadius: 5,
                          ),
                          overlayShape: const RoundSliderOverlayShape(
                            overlayRadius: 14,
                          ),
                        ),
                        child: Slider(
                          value: volume,
                          autofocus: true,
                          onChanged: widget.onVolumeChanged,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Align(
                  alignment: Alignment.centerRight,
                  child: Ps5Button(
                    sound: Ps5UiSound.back,
                    onPressed: _closePanel,
                    child: const Text('关闭'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAboutPanel() {
    return _Ps5PanelOverlay(
      alignment: Alignment.centerRight,
      child: _Ps5SidePanel(
        title: '关于',
        onClose: _closePanel,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(26, 18, 26, 26),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Art3m1s',
                style: TextStyle(
                  color: Ps5Colors.text,
                  fontSize: 28,
                  fontWeight: FontWeight.w400,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                AppInfo.displayVersion.isEmpty
                    ? '大屏游戏模式'
                    : AppInfo.displayVersion,
                style: const TextStyle(
                  color: Ps5Colors.textMuted,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                '大屏游戏模式',
                style: TextStyle(
                  color: Ps5Colors.text,
                  fontSize: 18,
                  fontWeight: FontWeight.w400,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                '在控制器和游戏画面之间保留直接、低干扰的操作方式。',
                style: TextStyle(
                  color: Ps5Colors.textMuted,
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPowerPanel() {
    return _Ps5PanelOverlay(
      alignment: Alignment.center,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Ps5MenuPanel(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(24, 20, 24, 12),
                child: Text(
                  '电源',
                  style: TextStyle(
                    color: Ps5Colors.text,
                    fontSize: 22,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ),
              const Divider(height: 1, thickness: 0.6, color: Ps5Colors.line),
              _Ps5PowerChoice(
                icon: Icons.close_rounded,
                label: '关闭 Art3m1s',
                caption: '结束当前应用',
                sound: Ps5UiSound.back,
                destructive: true,
                enabled: widget.onCloseApp != null,
                autofocus: true,
                onPressed: _activateCloseApp,
              ),
              const Divider(height: 1, thickness: 0.6, color: Ps5Colors.line),
              _Ps5PowerChoice(
                icon: Icons.fullscreen_exit_rounded,
                label: '退出大屏幕模式',
                caption: '返回窗口化界面',
                sound: Ps5UiSound.back,
                enabled: widget.onExitBigScreen != null,
                onPressed: _activateExitBigScreen,
              ),
              const Divider(height: 1, thickness: 0.6, color: Ps5Colors.line),
              const _Ps5PowerChoice(
                icon: Icons.power_settings_new_rounded,
                label: '关闭电源',
                caption: '当前平台暂不支持',
                sound: Ps5UiSound.back,
                enabled: false,
                onPressed: null,
              ),
              const Divider(height: 1, thickness: 0.6, color: Ps5Colors.line),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 12, 18, 16),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Ps5Button(
                    sound: Ps5UiSound.back,
                    onPressed: _closePanel,
                    child: const Text('取消'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Ps5PlayerMenuBackdrop extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const ColoredBox(color: Color(0x1F000000)),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0x00000000), Color(0x2E000000), Color(0xF7000000)],
              stops: [0.20, 0.48, 0.86],
            ),
          ),
        ),
      ],
    );
  }
}

class _Ps5PlayerInfoRail extends StatelessWidget {
  const _Ps5PlayerInfoRail({
    required this.title,
    required this.addedAt,
    required this.engineLabel,
    required this.sourceLabel,
    this.lastPlayedAt,
    this.sessionStartedAt,
    this.screenshotPath,
  });

  final String title;
  final DateTime addedAt;
  final DateTime? lastPlayedAt;
  final DateTime? sessionStartedAt;
  final String engineLabel;
  final String sourceLabel;
  final String? screenshotPath;

  @override
  Widget build(BuildContext context) {
    final compact =
        MediaQuery.sizeOf(context).width < 1280 ||
        MediaQuery.sizeOf(context).height < 760;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: compact ? 12 : 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '正在游玩',
            style: TextStyle(
              color: Ps5Colors.textMuted,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Ps5Colors.text,
              fontSize: compact ? 23 : 29,
              fontWeight: FontWeight.w400,
              shadows: const [Shadow(color: Color(0xB8000000), blurRadius: 16)],
            ),
          ),
          SizedBox(height: compact ? 11 : 15),
          Ps5GamePlayInfo(
            addedAt: addedAt,
            lastPlayedAt: lastPlayedAt,
            sessionStartedAt: sessionStartedAt,
            engineLabel: engineLabel,
            sourceLabel: sourceLabel,
            screenshotPath: screenshotPath,
            compact: compact,
          ),
        ],
      ),
    );
  }
}

class _Ps5PlayerActionRail extends StatelessWidget {
  const _Ps5PlayerActionRail({
    required this.focusNode,
    required this.showFps,
    required this.screenshotBusy,
    required this.masterVolume,
    required this.onHome,
    required this.onSettings,
    required this.onScreenshot,
    required this.onAbout,
    required this.onVolume,
    required this.onPower,
  });

  final FocusNode focusNode;
  final bool showFps;
  final bool screenshotBusy;
  final double masterVolume;
  final VoidCallback onHome;
  final VoidCallback onSettings;
  final VoidCallback onScreenshot;
  final VoidCallback onAbout;
  final VoidCallback onVolume;
  final VoidCallback onPower;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 88,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 112,
            child: _Ps5PlayerAction(
              key: const ValueKey('ps5-player-action-home'),
              icon: Icons.home_rounded,
              label: '主页',
              sound: Ps5UiSound.back,
              focusNode: focusNode,
              autofocus: true,
              onPressed: onHome,
            ),
          ),
          const SizedBox(width: 14),
          SizedBox(
            width: 112,
            child: _Ps5PlayerAction(
              key: const ValueKey('ps5-player-action-settings'),
              icon: Icons.settings_rounded,
              label: '设置',
              caption: showFps ? '帧率已开' : null,
              onPressed: onSettings,
            ),
          ),
          const SizedBox(width: 14),
          SizedBox(
            width: 112,
            child: _Ps5PlayerAction(
              key: const ValueKey('ps5-player-action-screenshot'),
              icon: Icons.photo_camera_rounded,
              label: screenshotBusy ? '保存中' : '截图',
              busy: screenshotBusy,
              onPressed: screenshotBusy ? null : onScreenshot,
            ),
          ),
          const SizedBox(width: 14),
          SizedBox(
            width: 112,
            child: _Ps5PlayerAction(
              key: const ValueKey('ps5-player-action-about'),
              icon: Icons.info_outline_rounded,
              label: '关于',
              onPressed: onAbout,
            ),
          ),
          const SizedBox(width: 14),
          SizedBox(
            width: 112,
            child: _Ps5PlayerAction(
              key: const ValueKey('ps5-player-action-volume'),
              icon: masterVolume <= 0.001
                  ? Icons.volume_off_rounded
                  : Icons.volume_up_rounded,
              label: '音量',
              caption: '${(masterVolume * 100).round()}%',
              onPressed: onVolume,
            ),
          ),
          const SizedBox(width: 14),
          SizedBox(
            width: 112,
            child: _Ps5PlayerAction(
              key: const ValueKey('ps5-player-action-power'),
              icon: Icons.power_settings_new_rounded,
              label: '电源',
              onPressed: onPower,
            ),
          ),
        ],
      ),
    );
  }
}

class _Ps5PlayerAction extends StatefulWidget {
  const _Ps5PlayerAction({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.caption,
    this.focusNode,
    this.busy = false,
    this.autofocus = false,
    this.sound = Ps5UiSound.confirm,
  });

  final IconData icon;
  final String label;
  final String? caption;
  final FutureOr<void> Function()? onPressed;
  final FocusNode? focusNode;
  final bool busy;
  final bool autofocus;
  final Ps5UiSound sound;

  @override
  State<_Ps5PlayerAction> createState() => _Ps5PlayerActionState();
}

class _Ps5PlayerActionState extends State<_Ps5PlayerAction> {
  bool _focused = false;
  bool _hovered = false;
  bool _pressed = false;

  void _activate() {
    final callback = widget.onPressed;
    if (callback == null || widget.busy) return;
    Ps5UiSounds.play(widget.sound);
    final result = callback();
    if (result is Future<void>) unawaited(result);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null && !widget.busy;
    final active = enabled && (_focused || _hovered);
    final foreground = enabled ? Ps5Colors.text : Ps5Colors.textMuted;
    return FocusableActionDetector(
      enabled: enabled,
      autofocus: widget.autofocus,
      focusNode: widget.focusNode,
      mouseCursor: enabled
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      onFocusChange: (value) {
        if (value) Ps5UiSounds.tick();
        setState(() => _focused = value);
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
            _activate();
            return null;
          },
        ),
      },
      child: Semantics(
        button: true,
        enabled: enabled,
        label: widget.label,
        child: MouseRegion(
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: enabled ? _activate : null,
            onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
            onTapUp: enabled ? (_) => setState(() => _pressed = false) : null,
            onTapCancel: enabled
                ? () => setState(() => _pressed = false)
                : null,
            child: AnimatedScale(
              scale: _pressed ? 0.985 : 1,
              duration: const Duration(milliseconds: 90),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  AnimatedScale(
                    scale: active ? 1.08 : 1,
                    duration: const Duration(milliseconds: 170),
                    curve: Curves.easeOutBack,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      curve: Curves.easeOutCubic,
                      width: 54,
                      height: 54,
                      decoration: BoxDecoration(
                        color: active
                            ? const Color(0xE6F2F4F7)
                            : const Color(0x571C222B),
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: active
                            ? const [
                                BoxShadow(
                                  color: Color(0x70000000),
                                  blurRadius: 18,
                                  offset: Offset(0, 8),
                                ),
                              ]
                            : null,
                      ),
                      child: widget.busy
                          ? Padding(
                              padding: const EdgeInsets.all(17),
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: active
                                    ? Ps5Colors.background
                                    : Ps5Colors.textMuted,
                              ),
                            )
                          : Icon(
                              widget.icon,
                              size: 27,
                              color: active ? Ps5Colors.background : foreground,
                            ),
                    ),
                  ),
                  const SizedBox(height: 7),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        widget.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: active ? Ps5Colors.text : foreground,
                          fontSize: 12,
                          fontWeight: active
                              ? FontWeight.w600
                              : FontWeight.w400,
                        ),
                      ),
                      if (widget.caption != null) ...[
                        const SizedBox(width: 5),
                        Text(
                          widget.caption!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Ps5Colors.menuMuted,
                            fontSize: 10,
                          ),
                        ),
                      ],
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

class _Ps5PanelOverlay extends StatelessWidget {
  const _Ps5PanelOverlay({required this.alignment, required this.child});

  final Alignment alignment;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: ColoredBox(
        color: const Color(0x73000000),
        child: SafeArea(
          child: Align(alignment: alignment, child: child),
        ),
      ),
    );
  }
}

class _Ps5SidePanel extends StatelessWidget {
  const _Ps5SidePanel({
    required this.title,
    required this.onClose,
    required this.child,
  });

  final String title;
  final VoidCallback onClose;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Ps5MenuPanel(
      width: 460,
      borderRadius: 0,
      child: SizedBox(
        height: double.infinity,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(26, 20, 14, 14),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        color: Ps5Colors.text,
                        fontSize: 22,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ),
                  Ps5IconButton(
                    icon: Icons.close_rounded,
                    tooltip: '关闭',
                    sound: Ps5UiSound.back,
                    onPressed: onClose,
                  ),
                ],
              ),
            ),
            const Divider(height: 1, thickness: 0.6, color: Ps5Colors.line),
            Flexible(child: SingleChildScrollView(child: child)),
          ],
        ),
      ),
    );
  }
}

class _Ps5PowerChoice extends StatefulWidget {
  const _Ps5PowerChoice({
    required this.icon,
    required this.label,
    required this.caption,
    required this.sound,
    required this.enabled,
    required this.onPressed,
    this.destructive = false,
    this.autofocus = false,
  });

  final IconData icon;
  final String label;
  final String caption;
  final Ps5UiSound sound;
  final bool enabled;
  final VoidCallback? onPressed;
  final bool destructive;
  final bool autofocus;

  @override
  State<_Ps5PowerChoice> createState() => _Ps5PowerChoiceState();
}

class _Ps5PowerChoiceState extends State<_Ps5PowerChoice> {
  bool _focused = false;
  bool _hovered = false;

  void _activate() {
    if (!widget.enabled || widget.onPressed == null) return;
    Ps5UiSounds.play(widget.sound);
    widget.onPressed!();
  }

  @override
  Widget build(BuildContext context) {
    final active = widget.enabled && (_focused || _hovered);
    final foreground = !widget.enabled
        ? Ps5Colors.textMuted
        : widget.destructive
        ? Ps5Colors.danger
        : Ps5Colors.text;
    return FocusableActionDetector(
      enabled: widget.enabled,
      autofocus: widget.autofocus,
      mouseCursor: widget.enabled
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      onFocusChange: (value) {
        if (value) Ps5UiSounds.tick();
        setState(() => _focused = value);
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
            _activate();
            return null;
          },
        ),
      },
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.enabled ? _activate : null,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            curve: Curves.easeOutCubic,
            color: active
                ? Ps5Colors.menuHighlight.withValues(alpha: 0.82)
                : Colors.transparent,
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 15),
            child: Row(
              children: [
                Icon(widget.icon, size: 23, color: foreground),
                const SizedBox(width: 15),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.label,
                        style: TextStyle(
                          color: foreground,
                          fontSize: 17,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        widget.caption,
                        style: const TextStyle(
                          color: Ps5Colors.menuMuted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Ps5MenuClock extends StatefulWidget {
  const _Ps5MenuClock();

  @override
  State<_Ps5MenuClock> createState() => _Ps5MenuClockState();
}

class _Ps5MenuClockState extends State<_Ps5MenuClock> {
  late Timer _timer;
  late DateTime _now;

  @override
  void initState() {
    super.initState();
    _now = DateTime.now();
    _timer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _timer.cancel();
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
    return Text(
      '$hour:$minute $period',
      style: const TextStyle(
        color: Ps5Colors.text,
        fontSize: 28,
        fontWeight: FontWeight.w400,
        letterSpacing: 0,
        fontFeatures: [FontFeature.tabularFigures()],
      ),
    );
  }
}
