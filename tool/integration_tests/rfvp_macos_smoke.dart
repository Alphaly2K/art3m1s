import 'dart:io';
import 'dart:ui' as ui;

import 'package:art3m1s/engine/backends/rfvp_engine_runtime.dart';
import 'package:art3m1s/engine/engine_runtime.dart';
import 'package:art3m1s/engine/engine_runtime_factory.dart';
import 'package:art3m1s/models/game_engine.dart';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SizedBox());
  final game = Platform.environment['RFVP_SMOKE_GAME'];
  final saves = await Directory.systemTemp.createTemp('rfvp-window-smoke-');
  final runtime =
      EngineRuntimeFactory.create(engine: GameEngineKind.rfvp)
          as RfvpEngineRuntime;
  try {
    if (game == null) {
      throw StateError('Set RFVP_SMOKE_GAME to the tile fixture.');
    }
    final expected = Platform.environment['RFVP_SMOKE_EXPECT_VERSION'];
    final version = runtime.useReplayFrames ? '2' : '1';
    if (expected != null && version != expected) {
      throw StateError('Expected RFVP v$expected, got v$version.');
    }
    await runtime.initialize();
    final project = await runtime.prepareProject(
      projectPath: game,
      isArchive: false,
      environmentPatchEnabled: false,
      platform: 'WINDOWS',
    );
    runtime.setSaveDir(saves.path);
    runtime.registerFileReader();
    runtime.createRuntime(640, 480, backend: 3);
    if (project == null || !runtime.loadProjectBytes(project)) {
      throw StateError('RFVP failed to open: ${runtime.lastError}');
    }
    if (!runtime.advanceWithoutRender(16)) {
      throw StateError('RFVP step failed.');
    }
    await _checkTexture(runtime);
    await runtime.setSessionState(EngineSessionState.suspended);
    if (runtime.hasActiveSharedTexture) {
      throw StateError('Suspending RFVP did not release the surface.');
    }
    await runtime.setSessionState(EngineSessionState.active);
    await _checkTexture(runtime);
    stdout.writeln('RFVP v$version Flutter texture and resume passed');
  } catch (error, stack) {
    stderr.writeln('$error\n$stack');
    exitCode = 1;
  } finally {
    await runtime.setSessionState(EngineSessionState.suspended);
    runtime.shutdown();
    await saves.delete(recursive: true);
  }
  exit(exitCode);
}

Future<void> _checkTexture(RfvpEngineRuntime runtime) async {
  final texture = await runtime.enableSharedTexture();
  if (texture == null) {
    throw StateError('RFVP could not bind a Flutter texture.');
  }
  final key = GlobalKey();
  runApp(
    Center(
      child: RepaintBoundary(
        key: key,
        child: SizedBox(
          width: 320,
          height: 240,
          child: Texture(textureId: texture),
        ),
      ),
    ),
  );
  await WidgetsBinding.instance.endOfFrame;
  if (runtime.advanceAndPresent(16) != 1) {
    throw StateError('RFVP did not present to the new Flutter texture.');
  }
  final deadline = Stopwatch()..start();
  while (deadline.elapsed < const Duration(seconds: 3)) {
    await WidgetsBinding.instance.endOfFrame;
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage();
    try {
      final data = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!.buffer.asUint8List();
      final row = 10 * image.width * 4;
      if (listEquals(data.sublist(row + 6 * 4, row + 7 * 4), [
            255,
            255,
            255,
            255,
          ]) &&
          listEquals(data.sublist(row + 2 * 4, row + 3 * 4), [0, 0, 0, 255])) {
        return;
      }
    } finally {
      image.dispose();
    }
  }
  throw StateError('The Flutter texture did not show the RFVP tile.');
}
