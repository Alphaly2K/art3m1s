import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:art3m1s/models/game_entry.dart';
import 'package:art3m1s/screens/player_screen.dart';
import 'package:art3m1s/services/logger.dart';
import 'package:art3m1s/shell/desktop_shell_mode.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:macos_window_utils/window_manipulator.dart';
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

Future<void> main() async {
  final binding = _WindowProbeBinding();
  const v2 = bool.fromEnvironment('ARTEMIS_V2');
  if (!Platform.isMacOS || !v2) {
    throw StateError('Requires a macOS desktop build with ARTEMIS_V2 enabled.');
  }
  final root = await Directory.systemTemp.createTemp('artemis-v2-window-');
  try {
    await _run(root, binding);
    stdout.writeln('Artemis v2 macOS window smoke passed');
  } catch (error, stack) {
    stderr.writeln('$error\n$stack');
    for (final log in Log.entries.where((entry) => entry.level == 'E')) {
      stderr.writeln(log.message);
    }
    exitCode = 1;
  } finally {
    try {
      await root.delete(recursive: true);
    } on FileSystemException catch (error) {
      stderr.writeln('Window probe cleanup failed: ${error.osError?.message}');
      exitCode = 1;
    }
  }
  exit(exitCode);
}

Future<void> _run(Directory root, _WindowProbeBinding binding) async {
  final probe = binding.probe;
  final data = await Directory('${root.path}/data').create();
  await File('${data.path}/.storage-layout-v2').writeAsString('2\n');
  PathProviderPlatform.instance = _ProbePaths(data.path);
  // ignore: invalid_use_of_visible_for_testing_member
  SharedPreferences.setMockInitialValues({});
  final game = await Directory('${root.path}/game').create();
  await File(
    '${game.path}/system.ini',
  ).writeAsString('[WINDOWS]\nWIDTH=128\nHEIGHT=72\nBOOT=boot.iet\n');
  await File('${game.path}/boot.iet').writeAsString('''
*top
[lyc id=1 width=128 height=72 color=ff112233]
[flip]
[exec command=fullscreen]
[wait time=3000 input=0]
[var system=fullscreen name=g.observed_fullscreen]
[autosave allow=1]
[exec command=minimize]
[wait time=1500 input=0]
[var system=minimize name=g.restored_minimized]
[var system=fullscreen name=g.restored_fullscreen]
[save file=restored]
[var name=g.quit_marker data=confirmed]
[stop]
[lua]
function capture_window(e)
  e:tag{'var', system='minimize', name='g.saved_minimized'}
end
__engine:setEventHandler{onSave='capture_window'}
[/lua]
''');

  await windowManager.ensureInitialized();
  await WindowManipulator.initialize(enableWindowDelegate: true);
  final desktop = DesktopShellController();
  try {
    runApp(const SizedBox.shrink());
    if (await windowManager.isMinimized()) await windowManager.restore();
    await windowManager.show();
    await windowManager.focus();
    await _until('Flutter can draw the window', _isVisible);
    await WidgetsBinding.instance.waitUntilFirstFrameRasterized.timeout(
      const Duration(seconds: 9),
    );
    runApp(
      ProviderScope(
        child: DesktopShellScope(
          controller: desktop,
          child: MaterialApp(
            home: PlayerScreen(
              gameId: 'fixture',
              projectPath: game.path,
              source: GameSource.directory,
              translationEnabled: false,
              translationPatchPath: '',
              environmentPatchEnabled: false,
              addedAt: DateTime.fromMillisecondsSinceEpoch(0),
            ),
          ),
        ),
      ),
    );
    await _until('AppKit enters fullscreen', windowManager.isFullScreen);
    if (desktop.mode != DesktopShellMode.standard) {
      throw StateError('Script fullscreen changed the player shell.');
    }
    await _until('AppKit minimizes the window', windowManager.isMinimized);
    final autosave = File('${data.path}/saves/fixture/save/__autosave.dat');
    await _until('the minimized session writes its autosave', autosave.exists);
    final globals = File('${data.path}/saves/fixture/save/saveg.dat');
    Map readGlobals() => jsonDecode(globals.readAsStringSync()) as Map;
    await _until('the script saves its minimized window state', () async {
      if (!await globals.exists()) return false;
      final background = readGlobals();
      return background['observed_fullscreen'] == 1 &&
          background['saved_minimized'] == 1;
    });
    final checkpoint = File('${data.path}/saves/fixture/save/restored');
    await Future<void>.delayed(const Duration(milliseconds: 1800));
    if (await checkpoint.exists()) {
      throw StateError('The scene clock advanced while the window was hidden.');
    }
    await windowManager.restore();
    await _until('AppKit restores the window', () async {
      return !await windowManager.isMinimized();
    });
    await windowManager.setAlwaysOnTop(true);
    await windowManager.show();
    await _until('Flutter can draw the restored window', _isVisible);
    await _until('the original scene resumes and saves', checkpoint.exists);
    await _until('the restored window state is saved', () async {
      final restored = readGlobals();
      return restored['restored_minimized'] == 0 &&
          restored['restored_fullscreen'] == 0;
    });
    bool hasQuitMarker() => readGlobals()['quit_marker'] == 'confirmed';
    if (hasQuitMarker()) throw StateError('Quit marker was written too early.');
    binding.verifyExit = (response) {
      if (response != ui.AppExitResponse.exit ||
          !probe.closed.isCompleted ||
          !hasQuitMarker()) {
        throw StateError('Quit returned before the session finished saving.');
      }
    };
    await windowManager.close();
    await binding.exitChecked.future.timeout(const Duration(seconds: 9));
  } finally {
    if (!binding.exitChecked.isCompleted) {
      if (await windowManager.isMinimized()) await windowManager.restore();
      runApp(const SizedBox.shrink());
      await WidgetsBinding.instance.endOfFrame;
      if (probe.opened) {
        await probe.closed.future.timeout(const Duration(seconds: 9));
      }
    }
    desktop.dispose();
  }
}

class _WindowProbeBinding extends WidgetsFlutterBinding {
  late final _WindowProbe probe;
  final exitChecked = Completer<void>();
  void Function(ui.AppExitResponse)? verifyExit;

  @override
  Future<ui.AppExitResponse> handleRequestAppExit() async {
    final response = await super.handleRequestAppExit();
    final verify = verifyExit;
    if (verify == null) return response;
    if (!exitChecked.isCompleted) {
      try {
        verify(response);
        exitChecked.complete();
      } catch (error, stack) {
        exitChecked.completeError(error, stack);
      }
    }
    // Keep the harness alive long enough to report and clean up.
    return ui.AppExitResponse.cancel;
  }

  @override
  BinaryMessenger createBinaryMessenger() =>
      probe = _WindowProbe(super.createBinaryMessenger());
}

class _WindowProbe extends BinaryMessenger {
  _WindowProbe(this.delegate);

  final BinaryMessenger delegate;
  final closed = Completer<void>();
  bool opened = false;

  @override
  Future<ByteData?>? send(String channel, ByteData? message) {
    final response = delegate.send(channel, message);
    if (channel != 'moe.alphaly.art3m1s/artemis_v2' ||
        message == null ||
        response == null) {
      return response;
    }
    const codec = StandardMethodCodec();
    final method = codec.decodeMethodCall(message).method;
    if (method != 'open' && method != 'close') return response;
    return response.then((reply) {
      if (reply != null) {
        try {
          codec.decodeEnvelope(reply);
          if (method == 'open') opened = true;
          if (method == 'close' && !closed.isCompleted) closed.complete();
        } on PlatformException {
          // The runtime handles the original reply.
        }
      }
      return reply;
    });
  }

  @override
  void setMessageHandler(String channel, MessageHandler? handler) =>
      delegate.setMessageHandler(channel, handler);

  @override
  Future<void> handlePlatformMessage(
    String channel,
    ByteData? data,
    PlatformMessageResponseCallback? callback,
  ) async {
    ServicesBinding.instance.channelBuffers.push(
      channel,
      data,
      callback ?? (_) {},
    );
  }
}

Future<bool> _isVisible() async {
  if (!await windowManager.isVisible() || await windowManager.isMinimized()) {
    return false;
  }
  return switch (WidgetsBinding.instance.lifecycleState) {
    null || AppLifecycleState.inactive || AppLifecycleState.resumed => true,
    _ => false,
  };
}

Future<void> _until(String action, Future<bool> Function() ready) async {
  final timer = Stopwatch()..start();
  while (timer.elapsed < const Duration(seconds: 9)) {
    if (await ready()) return;
    await Future<void>.delayed(const Duration(milliseconds: 40));
  }
  throw StateError(
    'Timed out waiting for $action (${WidgetsBinding.instance.lifecycleState}, '
    'visible=${await windowManager.isVisible()}, '
    'minimized=${await windowManager.isMinimized()}, '
    'focused=${await windowManager.isFocused()}).',
  );
}

final class _ProbePaths extends PathProviderPlatform {
  _ProbePaths(this.path);

  final String path;

  @override
  Future<String?> getApplicationSupportPath() async => path;

  @override
  Future<String?> getApplicationDocumentsPath() async => path;
}
