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
import 'package:path_provider/path_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SizedBox());
  final root = await Directory.systemTemp.createTemp('artemis-dxvk-');
  try {
    final artifact = Platform.environment['ARTEMIS_DXVK_TEST_ADE2'];
    final token = Platform.environment['ARTEMIS_DXVK_TEST_CACHE_TOKEN'];
    final legacy = Platform.environment['ARTEMIS_DXVK_TEST_LEGACY'] == '1';
    final profile = Platform.environment['ARTEMIS_DXVK_TEST_1080P'] == '1';
    if (artifact == null &&
        (token == null || !RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(token))) {
      throw StateError(
        'Set ARTEMIS_DXVK_TEST_ADE2 or ARTEMIS_DXVK_TEST_CACHE_TOKEN.',
      );
    }
    if ((legacy || profile) && artifact != null) {
      throw StateError('Legacy and 1080p checks require the bundled compiler.');
    }
    await _run(
      root,
      artifact == null ? null : await File(artifact).readAsBytes(),
      token,
      legacy: legacy,
      profile: profile,
    );
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

Future<void> _run(
  Directory root,
  List<int>? artifact,
  String? token, {
  required bool legacy,
  required bool profile,
}) async {
  final game = Directory('${root.path}/game')..createSync();
  final saves = Directory('${root.path}/saves')..createSync();
  final (width, height) = profile ? (1920, 1080) : (4, 4);
  File('${game.path}/system.ini').writeAsStringSync(
    '[WINDOWS]\nWIDTH=$width\nHEIGHT=$height\nBOOT=boot.iet\n',
  );
  final glsl = File('${game.path}/paint.glsl')
    ..writeAsStringSync('''
precision mediump float;
void main() { gl_FragColor = vec4(1.0, 0.0, 0.0, 1.0); }
''');
  final shader = File('${game.path}/paint.hlsl');
  final startupShader = legacy
      ? _legacyShader('float3(fore.b, fore.g, fore.r)')
      : 'float4 main() : SV_Target { return float4(0, 0, 1, 1); }';
  final source = utf8.encode(
    artifact == null ? '$startupShader\n// startup $token' : startupShader,
  );
  shader.writeAsBytesSync(source);
  if (artifact != null) {
    final cache = Directory('${game.path}/artemis-shaders/ade2')
      ..createSync(recursive: true);
    File(
      '${cache.path}/paint.hlsl.${sha256.convert(source)}.ade2',
    ).writeAsBytesSync(artifact);
  }

  final runtime = EngineRuntimeFactory.create(engine: GameEngineKind.art3m1s);
  if (runtime is! ArtemisV2EngineRuntime) {
    throw StateError('Build with --dart-define=ARTEMIS_V2=true.');
  }
  try {
    await runtime.initialize();
    runtime.setSaveDir(saves.path);
    Future<void> checkProject(
      String tag,
      List<int> expected, {
      Future<void> Function()? beforeStep,
      bool effect = true,
      String shaderFile = 'paint.hlsl',
      int glslLayers = 0,
      bool liveSidecars = false,
      bool measure = false,
      int layers = 1,
    }) async {
      final scene = StringBuffer();
      if (layers > 1) {
        scene.writeln('[lyc id=0 width=$width height=$height color=ff000000]');
      }
      for (var layer = 1; layer <= layers; layer++) {
        final color = layers == 1 ? 'ffff0000' : '80ff0000';
        scene.writeln(
          '[lyc id=$layer width=$width height=$height color=$color]',
        );
        if (effect) scene.writeln('[lyprop id=$layer shader=paint]');
      }
      if (glslLayers > 0) {
        scene.writeln('[lyshader id=back file=paint.glsl]');
        for (var layer = 9; layer < 9 + glslLayers; layer++) {
          scene.writeln(
            '[lyc id=$layer width=$width height=$height color=ffffffff]',
          );
          scene.writeln('[lyprop id=$layer shader=back]');
        }
      }
      File('${game.path}/boot.iet').writeAsStringSync('''
*top
${effect ? '[lyshader id=paint file=$shaderFile]' : ''}
$scene
[flip]
${measure ? '' : '[takess]\n[savess file=$tag]'}
[caption data=$tag]
${measure ? _motion : '[stop]'}
''');
      final ini = await runtime.prepareProject(
        projectPath: liveSidecars ? '${game.path}/root.pfs' : game.path,
        isArchive: liveSidecars,
        environmentPatchEnabled: false,
        platform: 'WINDOWS',
      );
      runtime.createRuntime(width, height);
      final opening = Stopwatch()..start();
      if (ini == null || !await runtime.loadProjectBytes(ini)) {
        throw StateError('Project failed to open.');
      }
      if (profile) {
        stdout.writeln(
          '$tag project open: ${_ms(opening.elapsedMicroseconds)} ms',
        );
      }
      await beforeStep?.call();
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
      if (measure) {
        await _measureFrames(runtime, tag);
        return;
      }
      final codec = await ui.instantiateImageCodec(
        await File('${saves.path}/save/$tag.png').readAsBytes(),
      );
      try {
        await _expect((await codec.getNextFrame()).image, expected);
      } finally {
        codec.dispose();
      }
    }

    if (artifact == null) {
      final cacheRoot = await getApplicationCacheDirectory();
      final cache = Directory('${cacheRoot.path}/artemis-ade2-v1');
      Future<File?> cachedEffect(List<int> source) async {
        if (!await cache.exists()) return null;
        final name = '/${sha256.convert(source)}.ade2';
        await for (final entry in cache.list(
          recursive: true,
          followLinks: false,
        )) {
          if (entry is File && entry.path.endsWith(name)) return entry;
        }
        return null;
      }

      final warm = Platform.environment['ARTEMIS_DXVK_TEST_WARM'] == '1';
      final prior = await cachedEffect(source);
      if ((prior != null) != warm) {
        throw StateError('Unexpected starting cache state.');
      }
      final modified = await prior?.lastModified();
      await checkProject(
        'compiled',
        [0, 0, 255, 255],
        beforeStep: () async {
          final entry = await cachedEffect(source);
          if (entry == null) {
            throw StateError('ADE2 missing before the first step.');
          }
          if (modified != null && await entry.lastModified() != modified) {
            throw StateError('The cached program was rewritten.');
          }
        },
      );

      final cacheDirectory = (await cachedEffect(source))!.parent;
      File entryFor(List<int> bytes) =>
          File('${cacheDirectory.path}/${sha256.convert(bytes)}.ade2');
      // The checksum and magic pass the Dart cache checks, but DXVK rejects the body.
      final corrupt = [...ascii.encode('ADE2'), ...List.filled(20, 0)];
      final corruptEntry = [...sha256.convert(corrupt).bytes, ...corrupt];
      final dynamicShader = legacy
          ? _legacyShader('float3(fore.b, fore.r, fore.g)')
          : 'float4 main() : SV_Target { return float4(0, 1, 0, 1); }';
      final dynamicSource = utf8.encode('$dynamicShader\n// dynamic $token');
      final dynamicFile = File('${game.path}/paint.txt')..writeAsBytesSync([]);
      shader.writeAsBytesSync([]);
      await checkProject(
        'dynamic',
        [0, 255, 0, 255],
        shaderFile: 'paint.txt',
        beforeStep: () async {
          if (!warm && await cachedEffect(dynamicSource) != null) {
            throw StateError('Dynamic ADE2 was present before the asset read.');
          }
          stdout.writeln(
            'Project opened before the shader asset was available',
          );
          dynamicFile.writeAsBytesSync(dynamicSource);
        },
      );
      if (await cachedEffect(dynamicSource) == null) {
        throw StateError('No ADE2 was stored for the dynamic shader.');
      }
      final dynamicEntry = entryFor(dynamicSource);
      if (!warm) dynamicEntry.writeAsBytesSync(corruptEntry);
      final dynamicModified = await dynamicEntry.lastModified();
      await checkProject('dynamic-cache', [
        0,
        255,
        0,
        255,
      ], shaderFile: 'paint.txt');
      if (await dynamicEntry.length() <= corruptEntry.length) {
        throw StateError('Runtime did not rebuild the rejected local ADE2.');
      }
      if (warm && await dynamicEntry.lastModified() != dynamicModified) {
        throw StateError('Runtime rewrote an already valid cache entry.');
      }
      dynamicFile.deleteSync();

      final retrySource = utf8.encode('$dynamicShader\n// retry $token');
      shader.writeAsBytesSync(retrySource);
      final packaged = File(
        '${game.path}/artemis-shaders/ade2/paint.hlsl.'
        '${sha256.convert(retrySource)}.ade2',
      );
      packaged.parent.createSync(recursive: true);
      packaged.writeAsStringSync('invalid ADE2');
      final retryEntry = entryFor(retrySource);
      if (!warm) retryEntry.writeAsBytesSync(corruptEntry);
      final retryModified = await retryEntry.lastModified();
      await checkProject(
        'retry',
        [0, 255, 0, 255],
        beforeStep: () async {
          if (await retryEntry.length() <= corruptEntry.length) {
            throw StateError(
              'Rejected packaged and local ADE2 were not replaced at startup.',
            );
          }
          if (warm && await retryEntry.lastModified() != retryModified) {
            throw StateError('Packaged recovery rewrote a valid local cache.');
          }
        },
      );
      packaged.deleteSync();

      final corruptSource = utf8.encode('$dynamicShader\n// corrupt $token');
      shader.writeAsBytesSync(corruptSource);
      final entry = entryFor(corruptSource);
      if (!warm) entry.writeAsBytesSync(corruptEntry);
      final priorModified = await entry.lastModified();
      await checkProject(
        'corrupt-cache',
        [0, 255, 0, 255],
        beforeStep: () async {
          if (await entry.length() <= corruptEntry.length) {
            throw StateError(
              'Rejected local ADE2 was not replaced at startup.',
            );
          }
          if (warm && await entry.lastModified() != priorModified) {
            throw StateError('Repair rewrote an already valid cache entry.');
          }
        },
      );
      shader.writeAsBytesSync(source);
    }
    await checkProject('cached', [0, 0, 255, 255]);
    shader.writeAsStringSync('// invalid shader after project reload');
    await checkProject('changed', [255, 0, 0, 255]);
    shader.writeAsBytesSync(source);
    await checkProject('restored', [0, 0, 255, 255]);
    final mixed = Platform.environment['ARTEMIS_DXVK_TEST_MIXED'] == '1';
    if (mixed && !profile) {
      glsl.writeAsStringSync(_backdrop);
      await checkProject('mixed', [16, 255, 255, 255], glslLayers: 1);
      if (artifact == null) {
        shader.deleteSync();
        glsl.deleteSync();
        File(
          '${game.path}/paint.txt',
        ).writeAsStringSync('$startupShader\n// mixed fallback $token');
        await checkProject(
          'mixed-fallback',
          [16, 255, 255, 255],
          shaderFile: 'paint.txt',
          glslLayers: 1,
          liveSidecars: true,
          beforeStep: () async {
            await glsl.writeAsString('$_backdrop\n// mixed fallback $token');
          },
        );
      }
    }
    if (profile) {
      glsl.deleteSync();
      shader.writeAsBytesSync([]);
      await checkProject(
        'metal',
        [255, 0, 0, 255],
        effect: false,
        measure: true,
      );
      shader.writeAsBytesSync(source);
      await checkProject('dxvk-1', [0, 0, 255, 255], measure: true);
      if (mixed) {
        glsl.writeAsStringSync(_backdrop);
        for (final count in [1, 4]) {
          await checkProject(
            'dxvk-1-glsl-$count',
            [16 * count, 255, 255, 255],
            glslLayers: count,
            measure: true,
          );
        }
        glsl.deleteSync();
      }
      if (legacy) {
        await checkProject(
          'dxvk-2',
          [0, 0, 192, 255],
          layers: 2,
          measure: true,
        );
        await checkProject(
          'dxvk-4',
          [0, 0, 240, 255],
          layers: 4,
          measure: true,
        );
      }
    }
  } finally {
    await runtime.close();
  }
}

const _backdrop = '''
precision mediump float;
varying vec2 resultCoord0;
uniform sampler2D textureBack;
void main() {
  vec4 back = texture2D(textureBack, resultCoord0);
  gl_FragColor = vec4(back.r + 16.0 / 255.0, back.b, back.b, back.a);
}
''';

String _legacyShader(String color) =>
    '''
texture textureFore;
texture textureMask;
sampler samplerFore = sampler_state { Texture = <textureFore>; };
sampler samplerMask = sampler_state { Texture = <textureMask>; };
float alpha;
float weights[2] = {0.25, 0.75};
void ps(float2 uv0 : TEXCOORD0, float2 uv1 : TEXCOORD1, out float4 result : COLOR0) {
    float4 fore = tex2D(samplerFore, uv1);
    float mask = tex2D(samplerMask, uv0).a;
    result = float4($color * (weights[0] + weights[1]), fore.a * mask * alpha);
}
''';

const _motion = '''
*move
[wait time=1 input=0]
[lyprop id=1 left=1]
[flip]
[wait time=1 input=0]
[lyprop id=1 left=0]
[flip]
[jump label=move]
''';

String _ms(int us) => (us / 1000).toStringAsFixed(2);

Future<void> _measureFrames(ArtemisV2EngineRuntime runtime, String tag) async {
  final samples = <int>[];
  for (var frame = 0; frame < 140; frame++) {
    final clock = Stopwatch()..start();
    var presented = false;
    for (var step = 0; step < 8 && !presented; step++) {
      presented = await runtime.advanceTexture(16);
    }
    if (!presented) {
      throw StateError('$tag did not present frame $frame.');
    }
    if (frame >= 20) samples.add(clock.elapsedMicroseconds);
  }
  samples.sort();
  stdout.writeln(
    '$tag ${samples.length} frames: median ${_ms(samples[samples.length ~/ 2])} ms, '
    'p95 ${_ms(samples[(samples.length * 0.95).ceil() - 1])} ms',
  );
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
