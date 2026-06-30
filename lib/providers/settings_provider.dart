import 'dart:io' show Platform;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/logger.dart';

final settingsProvider = StateNotifierProvider<SettingsNotifier, SettingsState>(
  (ref) {
    return SettingsNotifier();
  },
);

class SettingsState {
  final bool debugMode;
  final bool debugOverlay;
  final bool showFps;
  final int backend; // 0 = CGL, 1 = ANGLE
  final String runtimePlatform;

  const SettingsState({
    this.debugMode = false,
    this.debugOverlay = false,
    this.showFps = false,
    this.backend = 0,
    this.runtimePlatform = 'WINDOWS',
  });

  SettingsState copyWith({
    bool? debugMode,
    bool? debugOverlay,
    bool? showFps,
    int? backend,
    String? runtimePlatform,
  }) {
    return SettingsState(
      debugMode: debugMode ?? this.debugMode,
      debugOverlay: debugOverlay ?? this.debugOverlay,
      showFps: showFps ?? this.showFps,
      backend: backend ?? this.backend,
      runtimePlatform: runtimePlatform ?? this.runtimePlatform,
    );
  }
}

class SettingsNotifier extends StateNotifier<SettingsState> {
  SettingsNotifier() : super(const SettingsState()) {
    _load();
  }

  int getDefaultBackend() {
    if (Platform.isIOS || Platform.isMacOS) {
      return 3; // Metal
    } else {
      if (Platform.isAndroid) {
        return 1; // OpenGLES
      } else {
        return 2; // Vulkan
      }
    }
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final debugMode = prefs.getBool('debug_mode') ?? false;
    Log.setDebugEnabled(debugMode);
    state = SettingsState(
      debugMode: prefs.getBool('debug_mode') ?? false,
      debugOverlay: prefs.getBool('debugOverlay') ?? false,
      showFps: prefs.getBool('show_fps') ?? false,
      backend:
          prefs.getInt('gfx_backend') ??
          getDefaultBackend(), // default: ANGLE Vulkan
      runtimePlatform: _normalizeRuntimePlatform(
        prefs.getString('runtime_platform'),
      ),
    );
  }

  Future<void> setDebugMode(bool v) async {
    Log.setDebugEnabled(v);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('debug_mode', v);
    state = state.copyWith(debugMode: v);
  }

  Future<void> setDebugOverlay(bool v) async {
    Log.setOverlay(v);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('debug_overlay', v);
    state = state.copyWith(debugOverlay: v);
  }

  Future<void> setShowFps(bool v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('show_fps', v);
    state = state.copyWith(showFps: v);
  }

  Future<void> setBackend(int v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('gfx_backend', v);
    state = state.copyWith(backend: v);
  }

  Future<void> setRuntimePlatform(String v) async {
    final platform = _normalizeRuntimePlatform(v);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('runtime_platform', platform);
    state = state.copyWith(runtimePlatform: platform);
  }

  static String _normalizeRuntimePlatform(String? value) {
    final platform = value?.trim().toUpperCase();
    return switch (platform) {
      'WINDOWS' || 'ANDROID' || 'IOS' || 'WASM' => platform!,
      _ => 'WINDOWS',
    };
  }
}
