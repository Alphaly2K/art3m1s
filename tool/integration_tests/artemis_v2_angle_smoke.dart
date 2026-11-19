import 'dart:io';
import 'dart:ui' as ui;

import 'package:art3m1s/engine/backends/artemis_v2_engine_runtime.dart';
import 'package:art3m1s/engine/engine_runtime_factory.dart';
import 'package:art3m1s/models/game_engine.dart';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SizedBox());
  final root = await Directory.systemTemp.createTemp('artemis-angle-');
  try {
    await _run(root);
    stdout.writeln('Artemis v2 ANGLE Flutter application smoke passed');
  } catch (error, stack) {
    stderr.writeln('$error\n$stack');
    exitCode = 1;
  } finally {
    await root.delete(recursive: true);
  }
  exit(exitCode);
}

Future<void> _run(Directory root) async {
  final game = Directory('${root.path}/game')..createSync();
  final saves = Directory('${root.path}/saves')..createSync();
  File(
    '${game.path}/system.ini',
  ).writeAsStringSync('[WINDOWS]\nWIDTH=4\nHEIGHT=4\nBOOT=boot.iet\n');
  File('${game.path}/boot.iet').writeAsStringSync('''
*top
[lyshader id=paint file=paint.frag]
[lyc id=1 width=4 height=4 color=ffff0000]
[lyprop id=1 shader=paint]
[takess]
[savess file=before]
[flip]
[lyshader id=paint file=green.frag]
[trans type=1 time=64 input=0]
[takess]
[savess file=after]
[caption data=ready]
[stop]
''');
  File('${game.path}/paint.frag').writeAsStringSync('''
precision mediump float;
varying vec2 resultCoord;
uniform sampler2D textureFore;
void main() {
  vec4 color = texture2D(textureFore, resultCoord).bgra;
  color.r = step(0.5, resultCoord.y);
  gl_FragColor = color;
}
''');
  File('${game.path}/green.frag').writeAsStringSync('''
precision mediump float;
void main() { gl_FragColor = vec4(0.0, 1.0, 0.0, 1.0); }
''');
  final runtime = EngineRuntimeFactory.create(engine: GameEngineKind.art3m1s);
  if (runtime is! ArtemisV2EngineRuntime) {
    throw StateError('Build with --dart-define=ARTEMIS_V2=true.');
  }
  try {
    await runtime.initialize();
    final ini = await runtime.prepareProject(
      projectPath: game.path,
      isArchive: false,
      environmentPatchEnabled: false,
      platform: 'WINDOWS',
    );
    runtime.setSaveDir(saves.path);
    runtime.createRuntime(4, 4, backend: 6);
    if (ini == null || !await runtime.loadProjectBytes(ini)) {
      throw StateError('ANGLE project failed to open.');
    }
    final texture = await runtime.enableSharedTexture();
    if (texture == null) throw StateError('No Flutter texture.');
    final boundaryKey = GlobalKey();
    runApp(
      Center(
        child: RepaintBoundary(
          key: boundaryKey,
          child: SizedBox(
            width: 64,
            height: 64,
            child: Texture(textureId: texture),
          ),
        ),
      ),
    );
    final deadline = Stopwatch()..start();
    var blended = false;
    while (deadline.elapsed < const Duration(seconds: 5)) {
      if (await runtime.advanceTexture(16)) {
        final (top, bottom) = await _colors(await _composition(boundaryKey));
        if (top[1] > 32 && top[1] < 223 && top[2] > 32 && top[2] < 223) {
          if (top[0] != 0 ||
              bottom[0] < 32 ||
              (bottom[0] - top[2]).abs() > 1 ||
              bottom[1] != top[1] ||
              bottom[2] != top[2] ||
              top[3] != 255 ||
              bottom[3] != 255) {
            throw StateError('Incorrect transition pixels: $top, $bottom.');
          }
          blended = true;
        }
      }
      if (runtime.windowTitle.value == 'ready') break;
      await Future<void>.delayed(const Duration(milliseconds: 8));
    }
    if (!blended || runtime.windowTitle.value != 'ready') {
      throw StateError('Expected a displayed transition and the final scene.');
    }
    await _expect(
      await _loadPng(saves, 'before'),
      [0, 0, 255, 255],
      [255, 0, 255, 255],
    );
    const green = [0, 255, 0, 255];
    await _expect(await _loadPng(saves, 'after'), green, green);
    await _expect(await _composition(boundaryKey), green, green);
  } finally {
    await runtime.close();
  }
}

Future<ui.Image> _composition(GlobalKey key) async {
  await WidgetsBinding.instance.endOfFrame;
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  return boundary.toImage();
}

Future<ui.Image> _loadPng(Directory saves, String name) async {
  final codec = await ui.instantiateImageCodec(
    await File('${saves.path}/save/$name.png').readAsBytes(),
  );
  try {
    return (await codec.getNextFrame()).image;
  } finally {
    codec.dispose();
  }
}

Future<(List<int>, List<int>)> _colors(ui.Image image) async {
  try {
    final pixels = (await image.toByteData())!.buffer.asUint8List();
    List<int> sample(int row) {
      final offset = (row * image.width + image.width ~/ 2) * 4;
      return pixels.sublist(offset, offset + 4);
    }

    return (sample(image.height ~/ 4), sample(3 * image.height ~/ 4));
  } finally {
    image.dispose();
  }
}

Future<void> _expect(ui.Image image, List<int> top, List<int> bottom) async {
  final (actualTop, actualBottom) = await _colors(image);
  if (!listEquals(actualTop, top) || !listEquals(actualBottom, bottom)) {
    throw StateError('Expected $top, $bottom; got $actualTop, $actualBottom.');
  }
}
