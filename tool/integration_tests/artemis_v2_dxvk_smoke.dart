import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:art3m1s/engine/backends/artemis_v2_engine_runtime.dart';
import 'package:art3m1s/engine/engine_runtime_factory.dart';
import 'package:art3m1s/models/game_engine.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SizedBox());
  final root = await Directory.systemTemp.createTemp('artemis-dxvk-');
  try {
    final artifact = Platform.environment['ARTEMIS_DXVK_TEST_ADE2'];
    if (artifact == null) throw StateError('Set ARTEMIS_DXVK_TEST_ADE2.');
    await _run(root, await File(artifact).readAsBytes());
    stdout.writeln(
      'Artemis v2 DXVK Flutter presentation, screenshot and reload passed',
    );
  } catch (error, stack) {
    stderr.writeln('$error\n$stack');
    exitCode = 1;
  } finally {
    await root.delete(recursive: true);
  }
  exit(exitCode);
}

Future<void> _run(Directory root, List<int> artifact) async {
  final game = Directory('${root.path}/game')..createSync();
  final saves = Directory('${root.path}/saves')..createSync();
  File(
    '${game.path}/system.ini',
  ).writeAsStringSync('[WINDOWS]\nWIDTH=4\nHEIGHT=4\nBOOT=boot.iet\n');
  final shader = File('${game.path}/paint.hlsl');
  final source = utf8.encode(
    'float4 main() : SV_Target { return float4(0, 0, 1, 1); }',
  );
  shader.writeAsBytesSync(source);
  final cache = Directory('${game.path}/artemis-shaders/ade2')
    ..createSync(recursive: true);
  File(
    '${cache.path}/paint.hlsl.${sha256.convert(source)}.ade2',
  ).writeAsBytesSync(artifact);

  final runtime = EngineRuntimeFactory.create(engine: GameEngineKind.art3m1s);
  if (runtime is! ArtemisV2EngineRuntime) {
    throw StateError('Build with --dart-define=ARTEMIS_V2=true.');
  }
  try {
    await runtime.initialize();
    runtime.setSaveDir(saves.path);
    Future<void> checkProject(String tag, List<int> expected) async {
      File('${game.path}/boot.iet').writeAsStringSync('''
*top
[lyshader id=paint file=paint.hlsl]
[lyc id=1 width=4 height=4 color=ffff0000]
[lyprop id=1 shader=paint]
[flip]
[takess]
[savess file=$tag]
[caption data=$tag]
[stop]
''');
      final ini = await runtime.prepareProject(
        projectPath: game.path,
        isArchive: false,
        environmentPatchEnabled: false,
        platform: 'WINDOWS',
      );
      runtime.createRuntime(4, 4);
      if (ini == null || !await runtime.loadProjectBytes(ini)) {
        throw StateError('Project failed to open.');
      }
      final texture = await runtime.enableSharedTexture();
      if (texture == null) throw StateError('No Flutter texture.');
      final key = GlobalKey();
      runApp(
        Center(
          child: RepaintBoundary(
            key: key,
            child: SizedBox(
              width: 64,
              height: 64,
              child: Texture(textureId: texture),
            ),
          ),
        ),
      );
      final clock = Stopwatch()..start();
      while (runtime.windowTitle.value != tag &&
          clock.elapsed < const Duration(seconds: 5)) {
        await runtime.advanceTexture(16);
        await Future<void>.delayed(const Duration(milliseconds: 8));
      }
      if (runtime.windowTitle.value != tag) {
        throw StateError('Scene $tag did not settle.');
      }
      await WidgetsBinding.instance.endOfFrame;
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      await _expect(await boundary.toImage(), expected);
      final codec = await ui.instantiateImageCodec(
        await File('${saves.path}/save/$tag.png').readAsBytes(),
      );
      try {
        await _expect((await codec.getNextFrame()).image, expected);
      } finally {
        codec.dispose();
      }
    }

    await checkProject('cached', [0, 0, 255, 255]);
    shader.writeAsStringSync('// invalid shader after project reload');
    await checkProject('changed', [255, 0, 0, 255]);
    shader.writeAsBytesSync(source);
    await checkProject('restored', [0, 0, 255, 255]);
  } finally {
    await runtime.close();
  }
}

Future<void> _expect(ui.Image image, List<int> expected) async {
  try {
    final rgba = (await image.toByteData())!.buffer.asUint8List();
    final index = (image.width * (image.height ~/ 2) + image.width ~/ 2) * 4;
    final actual = rgba.sublist(index, index + 4);
    if (!listEquals(actual, expected)) {
      throw StateError('Expected $expected; got $actual.');
    }
  } finally {
    image.dispose();
  }
}
