import 'dart:io';

import 'package:art3m1s/engine/backends/art3m1s_engine_runtime.dart';
import 'package:art3m1s/engine/backends/artemis_v2_engine_runtime.dart';
import 'package:art3m1s/engine/engine_runtime.dart';
import 'package:art3m1s/services/logger.dart';
import 'package:flutter/widgets.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final root = await Directory.systemTemp.createTemp('artemis-save-interop-');
  try {
    await _run(root);
    await _verifyProjectSwitch(root);
    stdout.writeln('Artemis save interop and project switch passed');
  } catch (error, stack) {
    stderr.writeln('$error\n$stack');
    for (final log in Log.entries) {
      if (log.level == 'E' || log.level == 'W') stderr.writeln(log.message);
    }
    exitCode = 1;
  } finally {
    await root.delete(recursive: true);
  }
  exit(exitCode);
}

Future<void> _run(Directory root) async {
  final game = Directory('${root.path}/game')..createSync();
  final saves = Directory('${root.path}/saves');
  final canonical = Directory('${saves.path}/Profiles/Game');
  File('${game.path}/system.ini').writeAsStringSync(
    '[WINDOWS]\nWIDTH=64\nHEIGHT=64\nBOOT=boot.iet\nSAVEPATH=C:\\Profiles\\Game\n',
  );
  File('${game.path}/boot.iet').writeAsStringSync(r'''
*top
[if estimate="$g.round == 1"]
[var name=g.round data=2]
[load file=first]
[caption data=first_load_failed]
[stop]
[elseif estimate="$g.round == 2"]
[var name=g.round data=3]
[load file=second]
[caption data=second_load_failed]
[stop]
[/if]
[var name=g.round data=1]
[var name=checkpoint data=11]
[save file=first]
[if estimate="$g.round == 2"]
[if estimate="$checkpoint == 11"]
[jump label=upgrade]
[/if]
[caption data=wrong_first_checkpoint]
[stop]
[/if]
[caption data=seeded]
[stop]
*upgrade
[var name=checkpoint data=22]
[save file=second]
[if estimate="$g.round == 3"]
[caption data="$checkpoint"]
[stop]
[/if]
[caption data=updated]
[stop]
''');

  await _play(Art3m1sEngineRuntime(), game, saves, 'seeded');
  for (final name in ['first', 'saveg.dat', 'system.dat']) {
    if (!File('${canonical.path}/$name').existsSync()) {
      throw StateError('v1 did not write $name to the project folder');
    }
  }
  await _play(ArtemisV2EngineRuntime(), game, saves, 'updated');
  if (!File('${canonical.path}/second').existsSync() ||
      File('${saves.path}/second').existsSync()) {
    throw StateError('v2 did not write to the v1 project folder');
  }
  // Simulate the flat save layout written by the previous v2 preview.
  final preview = Directory('${root.path}/preview')..createSync();
  for (final name in ['second', 'saveg.dat', 'system.dat']) {
    File('${canonical.path}/$name').copySync('${preview.path}/$name');
  }
  await _play(Art3m1sEngineRuntime(), game, saves, '22');
  await _play(ArtemisV2EngineRuntime(), game, preview, '22');
  if (Directory('${preview.path}/Profiles').existsSync()) {
    throw StateError('v2 preview save files were split across layouts');
  }
}

Future<void> _verifyProjectSwitch(Directory root) async {
  Directory project(String key, String boot) {
    final dir = Directory('${root.path}/$key')..createSync();
    File('${dir.path}/system.ini').writeAsStringSync(
      '[WINDOWS]\nWIDTH=64\nHEIGHT=64\nBOOT=boot.iet\nSAVEPATH=$key\n',
    );
    File('${dir.path}/boot.iet').writeAsStringSync(boot);
    return dir;
  }

  final first = project('first-project', r'''
*top
[if estimate="$g.switchvalue == 37"]
[caption data=restored]
[else]
[var name=g.switchvalue data=37]
[caption data=first]
[/if]
[stop]
''');
  final second = project(
    'second-project',
    '*top\n[caption data=second]\n[stop]\n',
  );
  final saves = Directory('${root.path}/switch-saves');
  final runtime = ArtemisV2EngineRuntime();
  try {
    await _openAndWait(runtime, first, saves, 'first');
    await _openAndWait(runtime, second, saves, 'second');
    if (!File('${saves.path}/first-project/saveg.dat').existsSync() ||
        File('${saves.path}/second-project/saveg.dat').existsSync()) {
      throw StateError('Project switch did not persist to the old save folder');
    }
    await _openAndWait(runtime, first, saves, 'restored');
  } finally {
    await runtime.close();
  }
}

Future<void> _play(
  EngineRuntime runtime,
  Directory game,
  Directory saves,
  String expected,
) async {
  try {
    await _openAndWait(runtime, game, saves, expected);
  } finally {
    if (runtime is ArtemisV2EngineRuntime) {
      await runtime.close();
    } else {
      runtime.shutdown();
    }
  }
}

Future<void> _openAndWait(
  EngineRuntime runtime,
  Directory game,
  Directory saves,
  String expected,
) async {
  await runtime.initialize();
  final ini = await runtime.prepareProject(
    projectPath: game.path,
    isArchive: false,
    environmentPatchEnabled: false,
    platform: 'WINDOWS',
  );
  runtime.setSaveDir(saves.path);
  runtime.registerFileReader();
  runtime.createRuntime(64, 64);
  if (ini == null || !await runtime.loadProjectBytes(ini)) {
    throw StateError('${runtime.runtimeType} could not load the fixture');
  }
  for (var frame = 0; frame < 120; frame++) {
    if (runtime is ArtemisV2EngineRuntime) {
      await runtime.advanceTexture(16);
    } else {
      runtime.advanceWithoutRender(16);
    }
    if (runtime.windowTitle.value == expected) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  throw StateError(
    '${runtime.runtimeType} expected $expected, got ${runtime.windowTitle.value}',
  );
}
