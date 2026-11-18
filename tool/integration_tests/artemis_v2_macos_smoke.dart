import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:art3m1s/engine/backends/artemis_v2_engine_runtime.dart';
import 'package:art3m1s/engine/engine_runtime.dart';
import 'package:art3m1s/engine/engine_runtime_factory.dart';
import 'package:art3m1s/models/game_engine.dart';
import 'package:flutter/widgets.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SizedBox());
  final temp = await Directory.systemTemp.createTemp('artemis-v2-app-');
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  try {
    await _run(temp, server);
    stdout.writeln('Artemis v2 Flutter application smoke passed');
  } catch (error, stack) {
    stderr.writeln('$error\n$stack');
    exitCode = 1;
  } finally {
    await server.close(force: true);
    await temp.delete(recursive: true);
  }
  exit(exitCode);
}

Future<void> _run(Directory root, HttpServer server) async {
  var cancelStarted = false;
  server.listen((request) async {
    switch (request.uri.path) {
      case '/binary':
        request.response.statusCode = 418;
        request.response.add([0, 255, 65]);
      case '/cancel':
        cancelStarted = true;
        return;
      case '/next':
        request.response.write('new');
      default:
        request.response.statusCode = 404;
    }
    await request.response.close();
  });
  final base = 'http://127.0.0.1:${server.port}';
  final executable = File(Platform.resolvedExecutable).parent.path;
  DynamicLibrary.open(
    '$executable/libart3m1s_core.dylib',
  ).lookup<NativeFunction<Void Function()>>('art3m1s_get_api_v1');
  final game = Directory('${root.path}/game')..createSync();
  final saves = Directory('${root.path}/saves')..createSync();
  Directory('${saves.path}/protected').createSync();
  Directory('${saves.path}/protected.png').createSync();
  final thumbnail = File('${saves.path}/thumb.png')..writeAsStringSync('old');
  File(
    '${game.path}/system.ini',
  ).writeAsStringSync('[WINDOWS]\nWIDTH=4\nHEIGHT=4\nBOOT=boot.iet\n');
  File('${game.path}/data1').writeAsStringSync('confirmed');
  File('${game.path}/boot.iet').writeAsStringSync('''
*top
[calllua function=boot]
[lyc id=1 width=4 height=4 color=ff00ff00]
[takess]
[lydel id=1]
[lyc id=2 width=4 height=4 color=ffff0000]
[savess file=protected]
[savess file=thumb width=2 height=3]
[httpget url="$base/binary" filename=download.bin varname_code=t.status]
[httpget url="$base/cancel" varname_code=t.cancelled]
[httpget url="$base/next" varname_code=t.next varname_data=t.response]
[calllua function=check_http]
[caption data=ready]
[stop]
[lua]
function boot(e)
  count = (count or 0) + 1
  local payload = assert(e:file('data' .. count))
  local f, reason = io.open('save/protected', 'w')
  assert(not f and string.find(reason, 'denied'))
  f = assert(io.open('save/slot', 'w'))
  f:write(payload)
  assert(f:close() and count == 1)
end
function tick(e)
  if not cancelled and e:isDown(65) then
    cancelled = true
    e:tag{'var', name='s.http.cancel', data='1'}
  end
end
function check_http(e)
  assert(e:var('t.status') == '418')
  assert(e:var('t.cancelled') == '0')
  assert(e:var('t.next') == '200' and e:var('t.response') == 'new')
end
__engine:setEventHandler{onEnterFrame='tick'}
[/lua]
''');
  final runtime = EngineRuntimeFactory.create(engine: GameEngineKind.art3m1s);
  if (runtime is! ArtemisV2EngineRuntime) {
    throw StateError('Build with ARTEMIS_V2 enabled.');
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
    runtime.createRuntime(4, 4);
    if (!await runtime.loadProjectBytes(ini!)) {
      throw StateError('Cannot open v2 project.');
    }
    final texture = await runtime.enableSharedTexture();
    if (texture == null) throw StateError('No Flutter texture.');
    runApp(
      Center(
        child: SizedBox(
          width: 64,
          height: 64,
          child: Texture(textureId: texture),
        ),
      ),
    );
    var presented = false;
    var cancelled = false;
    final deadline = Stopwatch()..start();
    while (deadline.elapsed < const Duration(seconds: 5)) {
      if (await runtime.advanceTexture(16)) presented = true;
      if (presented && runtime.windowTitle.value == 'ready') break;
      if (cancelStarted && !cancelled) {
        runtime.feedKey(65, true);
        cancelled = true;
      }
      await Future<void>.delayed(const Duration(milliseconds: 4));
    }
    final body = File('${saves.path}/download.bin').readAsBytesSync();
    if (!cancelled ||
        body.length != 3 ||
        body[0] != 0 ||
        body[1] != 255 ||
        body[2] != 65) {
      throw StateError(
        'HTTP response or cancellation did not reach the script.',
      );
    }
    if (!presented ||
        runtime.windowTitle.value != 'ready' ||
        File('${saves.path}/slot').readAsStringSync() != 'confirmed') {
      throw StateError('The v2 project did not persist and present.');
    }
    if (!Directory('${saves.path}/protected.png').existsSync()) {
      throw StateError('The screenshot save replaced a directory.');
    }
    await _checkThumbnail(thumbnail);
    await WidgetsBinding.instance.endOfFrame;
    await runtime.setSessionState(EngineSessionState.suspended);
    if (runtime.hasActiveSharedTexture) {
      throw StateError('Texture did not detach.');
    }
  } finally {
    await runtime.close();
  }
}

Future<void> _checkThumbnail(File file) async {
  final codec = await ui.instantiateImageCodec(await file.readAsBytes());
  try {
    final image = (await codec.getNextFrame()).image;
    try {
      if (image.width != 2 || image.height != 3) {
        throw StateError('The saved screenshot has the wrong size.');
      }
      final rgba = (await image.toByteData())!.buffer.asUint8List();
      for (var i = 0; i < rgba.length; i += 4) {
        if (rgba[i] != 0 ||
            rgba[i + 1] != 255 ||
            rgba[i + 2] != 0 ||
            rgba[i + 3] != 255) {
          throw StateError('The saved screenshot is not the captured scene.');
        }
      }
    } finally {
      image.dispose();
    }
  } finally {
    codec.dispose();
  }
}
