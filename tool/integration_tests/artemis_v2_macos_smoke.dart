import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:art3m1s/engine/backends/art3m1s/project_vfs.dart';
import 'package:art3m1s/engine/backends/artemis_v2_engine_runtime.dart';
import 'package:art3m1s/engine/engine_runtime.dart';
import 'package:art3m1s/engine/engine_runtime_factory.dart';
import 'package:art3m1s/models/game_engine.dart';
import 'package:art3m1s/models/translation_settings.dart';
import 'package:art3m1s/services/text_translation_service.dart';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
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
  HttpResponse? delayedTranslation;
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
      case '/translate':
        final body = jsonDecode(await utf8.decoder.bind(request).join()) as Map;
        if ((body['text'] as List).single == 'late original') {
          delayedTranslation = request.response;
          return;
        }
        request.response.statusCode = 400;
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
  final gameSaves = Directory('${root.path}/saves');
  final saves = Directory('${gameSaves.path}/Profiles/Game')
    ..createSync(recursive: true);
  Directory('${saves.path}/protected').createSync();
  Directory('${saves.path}/protected.png').createSync();
  final thumbnail = File('${saves.path}/thumb.png')..writeAsStringSync('old');
  File('${game.path}/system.ini').writeAsStringSync(
    '[WINDOWS]\nWIDTH=4\nHEIGHT=4\nBOOT=boot.iet\nSAVEPATH=C:\\Profiles\\Game\n',
  );
  File('${game.path}/data1').writeAsStringSync('confirmed');
  File('${game.path}/tone.wav').writeAsBytesSync(_tone());
  final video = await Process.run('ffmpeg', [
    '-nostdin',
    '-v',
    'error',
    '-f',
    'lavfi',
    '-i',
    'color=blue:s=16x16:r=24:d=2',
    '-f',
    'lavfi',
    '-i',
    'sine=frequency=440:duration=2',
    '-c:v',
    'libx264',
    '-pix_fmt',
    'yuv420p',
    '-c:a',
    'aac',
    '${game.path}/video.mp4',
  ]);
  if (video.exitCode != 0) {
    throw StateError('Cannot generate video fixture: ${video.stderr}');
  }
  final legacyVideo = await Process.run('ffmpeg', [
    '-nostdin',
    '-v',
    'error',
    '-f',
    'lavfi',
    '-i',
    'color=blue:s=32x32:r=24:d=1',
    '-f',
    'lavfi',
    '-i',
    'sine=frequency=440:duration=1',
    '-c:v',
    'wmv2',
    '-c:a',
    'wmav2',
    '${game.path}/legacy.wmv',
  ]);
  if (legacyVideo.exitCode != 0) {
    throw StateError(
      'Cannot generate legacy video fixture: ${legacyVideo.stderr}',
    );
  }
  final theoraFixture = Platform.environment['ARTEMIS_V2_THEORA_FIXTURE'];
  final layerClip = theoraFixture == null ? 'legacy.wmv' : 'legacy.ogv';
  if (theoraFixture != null) {
    await File(theoraFixture).copy('${game.path}/$layerClip');
  }
  final looseLayerClip = File('${game.path}/$layerClip');
  final range = Uint8List(2 * 1024 * 1024 + 257);
  for (var i = 0; i < range.length; i++) {
    range[i] = (i * 31 + (i >> 20) * 11) & 0xff;
  }
  final archive = File('${game.path}/root.pfs');
  await _writePf6(archive, {
    layerClip: await looseLayerClip.readAsBytes(),
    'range.bin': range,
    'checks/runtime.lua': Uint8List.fromList(utf8.encode("return 'data'")),
  });
  await looseLayerClip.delete();
  final vfs = ProjectVfs.openArchive(archive.path);
  try {
    final copied = await vfs.copyFile(
      'range.bin',
      File('${root.path}/range.bin'),
      () => true,
    );
    if (copied == null || !listEquals(await copied.readAsBytes(), range)) {
      throw StateError('The archived asset was changed during chunked copy.');
    }
  } finally {
    vfs.close();
  }
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
[setonsoundfinish id=smoke label=sound_ended call=1]
[seplay id=smoke file=tone.wav gain=100]
[wait se=smoke]
[calllua function=check_sound]
[setonvideofinish id=2 label=video_ended call=1]
[video id=2 file=video.mp4]
[wait time=600]
[takess]
[savess file=video_thumb width=2 height=2]
[wait video=2]
[calllua function=check_video]
[setonvideofinish id=3 label=legacy_video_ended call=1]
[video id=3 file=$layerClip delaymargin=50]
[caption data=legacy_capture_ready]
[@]
[takess]
[savess file=legacy_thumb width=2 height=2]
[wait video=3]
[calllua function=check_legacy_video]
[avoid file=cover.png]
[keyconfig role=15 keys=70]
[keyconfig role=16 keys=70]
[video file=video.mp4 loop=1 skip=1]
[video file=legacy.wmv loop=1 skip=2]
[exec command=fullscreen]
[exec command=minimize]
[calllua function=check_focus]
[setonsoundfinish id=restored label=restored_ended call=1]
[seplay id=restored file=tone.wav gain=100]
[save file=numbered]
[wait se=restored]
[calllua function=check_restore]
[chgmsg id=translation layered=1]
late original
[wait time=350 input=0]
[rp]
current original
[caption data=translation_page]
[wait time=750 input=0]
[save file=translations]
[caption data=ready]
[@]
[video file=video.mp4 loop=1 skip=0]
[stop]
*sound_ended
[calllua function=sound_ended]
[return]
*restored_ended
[calllua function=restored_ended]
[return]
*video_ended
[calllua function=video_ended]
[return]
*legacy_video_ended
[calllua function=legacy_video_ended]
[return]
[lua]
function boot(e)
  count = (count or 0) + 1
  local payload = assert(e:file(require('checks.runtime') .. count))
  local save = e:var('s.savepath') .. '/'
  local f, reason = io.open(save .. 'protected', 'w')
  assert(not f and string.find(reason, 'denied'))
  f = assert(io.open(save .. 'slot', 'w'))
  f:write(payload)
  assert(f:close() and count == 1)
end
function tick(e)
  if e:isDown(74) then saw_held = true end
  if not cancelled and e:isDown(65) then
    cancelled = true
    e:tag{'var', name='s.http.cancel', data='1'}
  end
end
function check_focus(e)
  assert(saw_held and not e:isDown(74), 'Suspension did not release held input')
end
function check_http(e)
  assert(e:var('t.status') == '418')
  assert(e:var('t.cancelled') == '0')
  assert(e:var('t.next') == '200' and e:var('t.response') == 'new')
end
function sound_ended(e)
  media_completed = (media_completed or 0) + 1
end
function check_sound(e)
  assert(media_completed == 1, 'Host audio did not complete naturally')
end
function video_ended(e)
  video_completed = (video_completed or 0) + 1
end
function check_video(e)
  assert(video_completed == 1, 'Host video did not complete naturally')
end
function legacy_video_ended(e)
  legacy_completed = (legacy_completed or 0) + 1
end
function check_legacy_video(e)
  assert(legacy_completed == 1, 'Host legacy video did not complete naturally')
end
function restored_ended(e)
  restored_completed = (restored_completed or 0) + 1
end
function on_load(e, p)
  assert(p.file == 'numbered')
  load_count = (load_count or 0) + 1
end
function check_restore(e)
  if not load_count then
    assert(restored_completed == 1, 'Original sound did not finish before load')
    restored_completed = 0
    e:enqueueTag{'seplay', id='restored', file='tone.wav', loop='1'}
    e:enqueueTag{'load', file='numbered'}
  else
    assert(load_count == 1 and restored_completed == 1,
      'The saved sound did not finish after load')
  end
end
__engine:setEventHandler{onEnterFrame='tick', onLoad='on_load'}
[/lua]
''');
  final captionProject = Directory('${root.path}/caption-probe')..createSync();
  File(
    '${captionProject.path}/system.ini',
  ).writeAsStringSync('[WINDOWS]\nWIDTH=4\nHEIGHT=4\nBOOT=boot.iet\n');
  File('${captionProject.path}/title.txt').writeAsStringSync('Probe title');
  File('${captionProject.path}/boot.iet').writeAsStringSync('''
*top
[calllua function=read_caption]
[stop]
[lua]
function read_caption(e)
  local f = io.open(e:var('s.savepath') .. '/should-not-exist', 'w')
  assert(f == nil)
  e:tag{'caption', data = assert(e:file('title.txt'))}
end
[/lua]
''');
  final caption = await EngineRuntimeFactory.probeCaption(
    engine: GameEngineKind.art3m1s,
    projectPath: captionProject.path,
    isPfsArchive: false,
  );
  if (caption != 'Probe title') {
    throw StateError(
      'Caption probe did not return the project title: $caption',
    );
  }
  final windowActions = <EngineWindowAction>[];
  final runtime = EngineRuntimeFactory.create(
    engine: GameEngineKind.art3m1s,
    onWindowAction: windowActions.add,
  );
  if (runtime is! ArtemisV2EngineRuntime) {
    throw StateError('Build with ARTEMIS_V2 enabled.');
  }
  try {
    await runtime.initialize();
    final patch = File('${root.path}/translation.json')
      ..writeAsStringSync('{"current original":"host replacement"}');
    final translator = await TextTranslationService.create(
      settings: TranslationSettings(
        mode: TranslationMode.online,
        provider: TranslationProvider.deepL,
        endpoint: '$base/translate',
        apiKey: 'smoke',
      ),
      patchPath: patch.path,
      cacheFile: File('${root.path}/translation.pb'),
    );
    runtime.configureTranslation(translator);
    final ini = await runtime.prepareProject(
      projectPath: game.path,
      isArchive: false,
      environmentPatchEnabled: false,
      platform: 'WINDOWS',
    );
    runtime.setSaveDir(gameSaves.path);
    runtime.createRuntime(4, 4);
    if (!await runtime.loadProjectBytes(ini!)) {
      throw StateError('Cannot open v2 project.');
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
    var presented = false;
    var cancelled = false;
    var skippedVideo = false;
    var skippedMenuVideo = false;
    var sentLateTranslation = false;
    var requestedLegacyCapture = false;
    final deadline = Stopwatch()..start();
    while (deadline.elapsed < const Duration(seconds: 15)) {
      final outputChanged = await runtime.advanceTexture(16);
      if (outputChanged) presented = true;
      if (presented && runtime.windowTitle.value == 'ready') break;
      if (outputChanged &&
          !requestedLegacyCapture &&
          runtime.windowTitle.value == 'legacy_capture_ready' &&
          await _showingBlueVideo(boundaryKey)) {
        runtime.feedClick();
        requestedLegacyCapture = true;
      }
      if (cancelStarted && !cancelled) {
        runtime.feedKey(65, true);
        cancelled = true;
      }
      if (!sentLateTranslation &&
          runtime.windowTitle.value == 'translation_page') {
        final response = delayedTranslation;
        if (response != null) {
          response.headers.contentType = ContentType.json;
          response.write('{"translations":[{"text":"discarded translation"}]}');
          await response.close();
          sentLateTranslation = true;
        }
      }
      final playback = runtime.media.videoPlayback.value;
      if (playback != null && !skippedVideo) {
        if (!playback.isFullscreen ||
            !playback.skippable ||
            playback.view is! Texture) {
          throw StateError(
            'Fullscreen video was not published as a Flutter texture.',
          );
        }
        runApp(
          Center(child: SizedBox(width: 64, height: 64, child: playback.view)),
        );
        await WidgetsBinding.instance.endOfFrame;
        runtime.media.handleEngineAudioCommand(
          EngineAudioCommand(
            kind: EngineAudioCommandKind.masterVolume,
            streamId: 0,
            id: 'master',
            channel: 'master',
            payload: Uint8List(0),
            volume: 0.25,
          ),
        );
        runtime.feedKey(70, true);
        await runtime.advanceTexture(16);
        if (runtime.avoidOverlay.value?.file != 'cover.png' ||
            !identical(runtime.media.videoPlayback.value, playback)) {
          throw StateError('Avoid did not cover the playing video.');
        }
        runtime.feedKey(70, false);
        await runtime.advanceTexture(16);
        runtime.feedKey(70, true);
        await runtime.advanceTexture(16);
        if (runtime.avoidOverlay.value != null) {
          throw StateError('Avoid did not clear after the second press.');
        }
        runtime.feedKey(70, false);
        runtime.feedKey(74, true);
        await runtime.advanceTexture(16);
        await runtime.setSessionState(EngineSessionState.suspended);
        if (await runtime.advanceTexture(16) ||
            runtime.media.videoPlayback.value != playback) {
          throw StateError('Suspension retired an active video.');
        }
        await runtime.setSessionState(EngineSessionState.active);
        await runtime.media.skipVideo();
        skippedVideo = true;
      } else if (playback != null && !skippedMenuVideo) {
        final menu = playback.onMenuSkip;
        if (!playback.isFullscreen || playback.skippable || menu == null) {
          throw StateError('Menu-only video policy is incorrect.');
        }
        await runtime.media.skipVideo();
        if (!identical(runtime.media.videoPlayback.value, playback)) {
          throw StateError('Tap skipped a menu-only video.');
        }
        final loopDeadline = Stopwatch()..start();
        while (loopDeadline.elapsed < const Duration(milliseconds: 1300)) {
          await runtime.advanceTexture(16);
          if (!identical(runtime.media.videoPlayback.value, playback)) {
            throw StateError('The fullscreen WMV retired at its first end.');
          }
          await Future<void>.delayed(const Duration(milliseconds: 16));
        }
        menu();
        skippedMenuVideo = true;
      }
      await Future<void>.delayed(const Duration(milliseconds: 16));
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
        !requestedLegacyCapture ||
        !skippedVideo ||
        !skippedMenuVideo ||
        runtime.media.videoPlayback.value != null ||
        runtime.windowTitle.value != 'ready' ||
        !File('${saves.path}/numbered').existsSync() ||
        File('${saves.path}/slot').readAsStringSync() != 'confirmed') {
      throw StateError('The v2 project did not persist and present.');
    }
    if (!Directory('${saves.path}/protected.png').existsSync()) {
      throw StateError('The screenshot save replaced a directory.');
    }
    if (windowActions.length != 2 ||
        windowActions.first != EngineWindowAction.toggleFullscreen ||
        windowActions.last != EngineWindowAction.minimize) {
      throw StateError(
        'Scripted window actions did not reach the Host in order.',
      );
    }
    final saved =
        jsonDecode(File('${saves.path}/translations').readAsStringSync())
            as Map;
    final messageText = saved['message_text'] as Map;
    final lines = (messageText['layers'] as List)
        .expand((layer) => (layer as Map)['tags'] as List)
        .whereType<Map>()
        .map((tag) => tag['Text'])
        .whereType<String>()
        .toList();
    if (!sentLateTranslation ||
        translator.hostReplacementTable['late original'] !=
            'discarded translation' ||
        !lines.contains('host replacement') ||
        lines.contains('discarded translation') ||
        lines.contains('current original')) {
      throw StateError(
        'Translation replies did not preserve the current message page.',
      );
    }
    await _checkThumbnail(thumbnail);
    await _checkThumbnail(
      File('${saves.path}/video_thumb.png'),
      height: 2,
      blue: true,
    );
    await _checkThumbnail(
      File('${saves.path}/legacy_thumb.png'),
      height: 2,
      blue: true,
    );
    await WidgetsBinding.instance.endOfFrame;
    await runtime.setSessionState(EngineSessionState.suspended);
    if (runtime.hasActiveSharedTexture) {
      throw StateError('Texture did not detach.');
    }
    await runtime.setSessionState(EngineSessionState.active);
    runtime.feedClick();
    deadline.reset();
    while (deadline.elapsed < const Duration(seconds: 4) &&
        runtime.media.videoPlayback.value == null) {
      await runtime.advanceTexture(16);
      await Future<void>.delayed(const Duration(milliseconds: 16));
    }
    final activeVideo = runtime.media.videoPlayback.value;
    if (activeVideo == null || activeVideo.view is! Texture) {
      throw StateError(
        'Could not start the video before replacing the project.',
      );
    }
    runApp(
      Center(
        child: RepaintBoundary(
          key: boundaryKey,
          child: SizedBox(width: 64, height: 64, child: activeVideo.view),
        ),
      ),
    );
    if (!await _showingBlueVideo(boundaryKey)) {
      throw StateError('The active video did not reach the Flutter texture.');
    }
    final invalid = Directory('${root.path}/replacement')..createSync();
    final replacementSaves = Directory('${root.path}/replacement-saves');
    File('${invalid.path}/system.ini').writeAsBytesSync(ini);
    File('${invalid.path}/video.mp4').writeAsStringSync('invalid video');
    File('${invalid.path}/boot.iet').writeAsStringSync('''
*top
[video file=video.mp4 loop=1 skip=0]
[caption data=replaced]
[stop]
''');
    final replacement = await runtime.prepareProject(
      projectPath: invalid.path,
      isArchive: false,
      environmentPatchEnabled: false,
      platform: 'WINDOWS',
    );
    if (runtime.media.videoPlayback.value != null) {
      throw StateError('Project replacement left the old video active.');
    }
    runtime.setSaveDir(replacementSaves.path);
    if (!await runtime.loadProjectBytes(replacement!)) {
      throw StateError('Could not replace the project.');
    }
    deadline.reset();
    while (deadline.elapsed < const Duration(seconds: 4) &&
        runtime.windowTitle.value != 'replaced') {
      await runtime.advanceTexture(16);
      if (runtime.media.videoPlayback.value != null) {
        throw StateError('The replacement project reused old media.');
      }
      await Future<void>.delayed(const Duration(milliseconds: 16));
    }
    if (runtime.windowTitle.value != 'replaced') {
      throw StateError('Video failure did not resume the replacement script.');
    }
    await runtime.close();
    for (final name in ['saveg.dat', 'system.dat']) {
      final saved = File('${replacementSaves.path}/Profiles/Game/$name');
      if (!saved.existsSync() || saved.lengthSync() == 0) {
        throw StateError(
          'The replacement project did not write $name on exit.',
        );
      }
    }
  } finally {
    await runtime.close();
  }
}

Uint8List _tone() {
  const sampleRate = 16000;
  const samples = sampleRate ~/ 4;
  final data = ByteData(44 + samples * 2);
  data.setUint32(0, 0x52494646); // RIFF
  data.setUint32(4, data.lengthInBytes - 8, Endian.little);
  data.setUint32(8, 0x57415645); // WAVE
  data.setUint32(12, 0x666d7420); // fmt
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little);
  data.setUint16(22, 1, Endian.little);
  data.setUint32(24, sampleRate, Endian.little);
  data.setUint32(28, sampleRate * 2, Endian.little);
  data.setUint16(32, 2, Endian.little);
  data.setUint16(34, 16, Endian.little);
  data.setUint32(36, 0x64617461); // data
  data.setUint32(40, samples * 2, Endian.little);
  return data.buffer.asUint8List();
}

Future<void> _writePf6(File archive, Map<String, Uint8List> files) async {
  final names = files.keys.map(ascii.encode).toList();
  final entriesBytes = names.fold<int>(
    0,
    (size, name) => size + 16 + name.length,
  );
  final trailerBytes = 4 + 8 * (files.length + 1) + 4;
  final indexBytes = 4 + entriesBytes + trailerBytes;
  final header = BytesBuilder()..add(ascii.encode('pf6'));
  void addU32(int value) {
    final bytes = ByteData(4)..setUint32(0, value, Endian.little);
    header.add(bytes.buffer.asUint8List());
  }

  addU32(indexBytes);
  addU32(files.length);
  var offset = 7 + indexBytes;
  for (final (index, data) in files.values.indexed) {
    addU32(names[index].length);
    header.add(names[index]);
    addU32(0);
    addU32(offset);
    addU32(data.length);
    offset += data.length;
  }
  addU32(files.length + 1);
  header.add(Uint8List(8 * (files.length + 1)));
  addU32(7 + 4 + entriesBytes);
  final sink = archive.openWrite();
  sink.add(header.takeBytes());
  for (final data in files.values) {
    sink.add(data);
  }
  await sink.close();
}

Future<bool> _showingBlueVideo(GlobalKey key) async {
  await WidgetsBinding.instance.endOfFrame.timeout(const Duration(seconds: 2));
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final image = await boundary.toImage(pixelRatio: 0.125);
  try {
    final pixels = (await image.toByteData())!.buffer.asUint8List();
    final center = (image.height ~/ 2 * image.width + image.width ~/ 2) * 4;
    return _isBlue(pixels, center);
  } finally {
    image.dispose();
  }
}

bool _isBlue(Uint8List rgba, int i) =>
    rgba[i] <= 8 && rgba[i + 1] <= 8 && rgba[i + 2] >= 245;

Future<void> _checkThumbnail(
  File file, {
  int height = 3,
  bool blue = false,
}) async {
  final codec = await ui.instantiateImageCodec(await file.readAsBytes());
  try {
    final image = (await codec.getNextFrame()).image;
    try {
      if (image.width != 2 || image.height != height) {
        throw StateError('The saved screenshot has the wrong size.');
      }
      final rgba = (await image.toByteData())!.buffer.asUint8List();
      for (var i = 0; i < rgba.length; i += 4) {
        final correct = blue
            ? _isBlue(rgba, i)
            : rgba[i] == 0 && rgba[i + 1] == 255 && rgba[i + 2] == 0;
        if (!correct || rgba[i + 3] != 255) {
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
