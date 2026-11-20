import 'dart:io';
import 'dart:ui' as ui;

import 'package:art3m1s/engine/backends/artemis_v2_engine_runtime.dart';
import 'package:art3m1s/engine/engine_runtime_factory.dart';
import 'package:art3m1s/models/game_engine.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SizedBox());
  final root = await Directory.systemTemp.createTemp('artemis-shader-archive-');
  try {
    final env = Platform.environment;
    final archive = env['ARTEMIS_SHADER_TEST_ARCHIVE'];
    if (archive == null) throw StateError('Set ARTEMIS_SHADER_TEST_ARCHIVE.');
    String key(String name, Set<String> extensions) {
      final value = env[name];
      if (value == null ||
          !RegExp(r'^[a-zA-Z0-9_./-]+$').hasMatch(value) ||
          value.startsWith('/') ||
          value.split('/').contains('..') ||
          !extensions.any(value.toLowerCase().endsWith)) {
        throw StateError(
          'Set $name to a project-relative ${extensions.join('/')} asset key.',
        );
      }
      return value;
    }

    await _check(
      root,
      File(archive),
      key('ARTEMIS_SHADER_TEST_HLSL', {'.hlsl', '.fx'}),
      key('ARTEMIS_SHADER_TEST_GLSL', {'.glsl', '.frag', '.fsh', '.fs'}),
    );
    stdout.writeln('Archived HLSL and GLSL presentation and capture passed');
  } catch (error, trace) {
    stderr.writeln('$error\n$trace');
    exitCode = 1;
  } finally {
    await root.delete(recursive: true);
  }
  exit(exitCode);
}

Future<void> _check(
  Directory root,
  File archive,
  String hlsl,
  String glsl,
) async {
  final project = await Directory('${root.path}/game').create();
  final saves = await Directory('${root.path}/saves').create();
  final copy = await archive.copy('${project.path}/root.pfs');
  await File(
    '${project.path}/system.ini',
  ).writeAsString('[WINDOWS]\nWIDTH=1280\nHEIGHT=720\nBOOT=probe.iet\n');
  await File('${project.path}/probe.iet').writeAsString('''
*top
[lyshader id=dx file=$hlsl]
[lyshader id=gl file=$glsl]
[lyc id=1 width=400 height=720 color=ffff0000]
[lyprop id=1 shader=dx]
[lyc id=2 width=400 height=720 color=ffff0000]
[lyprop id=2 left=400 shader=gl]
[lyc id=3 width=480 height=720 color=ffff0000]
[lyprop id=3 left=800]
[flip]
[takess]
[savess file=effects]
[caption data=effects-ready]
[stop]
''');
  final runtime = EngineRuntimeFactory.create(engine: GameEngineKind.art3m1s);
  if (runtime is! ArtemisV2EngineRuntime) {
    throw StateError('Build with --dart-define=ARTEMIS_V2=true.');
  }
  try {
    await runtime.initialize();
    runtime.setSaveDir(saves.path);
    final ini = await runtime.prepareProject(
      projectPath: copy.path,
      isArchive: true,
      environmentPatchEnabled: false,
      platform: 'WINDOWS',
    );
    runtime.createRuntime(1280, 720);
    if (ini == null || !await runtime.loadProjectBytes(ini)) {
      throw StateError('Archive project failed to open.');
    }
    final texture = await runtime.enableSharedTexture();
    if (texture == null) throw StateError('No Flutter texture.');
    final key = GlobalKey();
    runApp(
      Center(
        child: RepaintBoundary(
          key: key,
          child: SizedBox(
            width: 320,
            height: 180,
            child: Texture(textureId: texture),
          ),
        ),
      ),
    );
    final clock = Stopwatch()..start();
    while (runtime.windowTitle.value != 'effects-ready' &&
        clock.elapsed < const Duration(seconds: 5)) {
      await runtime.advanceTexture(16);
      await Future<void>.delayed(const Duration(milliseconds: 8));
    }
    if (runtime.windowTitle.value != 'effects-ready') {
      throw StateError('The effect scene did not finish.');
    }
    await WidgetsBinding.instance.endOfFrame;
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    await _expect(await boundary.toImage(), 320, 180);
    final codec = await ui.instantiateImageCodec(
      await File('${saves.path}/save/effects.png').readAsBytes(),
    );
    try {
      await _expect((await codec.getNextFrame()).image, 1280, 720);
    } finally {
      codec.dispose();
    }
  } finally {
    await runtime.close();
  }
}

Future<void> _expect(ui.Image image, int width, int height) async {
  try {
    if (image.width != width || image.height != height) {
      throw StateError('Unexpected image size ${image.width}x${image.height}.');
    }
    final data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    final pixels = data.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );
    for (var index = 0; index < pixels.length; index += 4) {
      final x = (index ~/ 4) % width;
      final red = x >= width * 5 ~/ 8;
      if (pixels[index] != (red ? 255 : 0) ||
          pixels[index + 1] != (red ? 0 : 255) ||
          pixels[index + 2] != (red ? 0 : 255) ||
          pixels[index + 3] != 255) {
        throw StateError('Unexpected pixel at ($x, ${index ~/ 4 ~/ width}).');
      }
    }
  } finally {
    image.dispose();
  }
}
