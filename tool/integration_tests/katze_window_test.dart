import 'dart:io';

import 'package:art3m1s/engine/engine_runtime.dart';
import 'package:art3m1s/engine/engine_runtime_factory.dart';
import 'package:art3m1s/models/game_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Window commands reach the player callback in script order', () async {
    final fixtures = Platform.environment['KATZE_FIXTURES'];
    if (fixtures == null ||
        Platform.environment['KATZE_OFFSCREEN_AUDIO'] != '1') {
      throw StateError('Set KATZE_FIXTURES and KATZE_OFFSCREEN_AUDIO=1');
    }
    final root = Directory.systemTemp.createTempSync('katze-window-');
    addTearDown(() => root.deleteSync(recursive: true));
    final config = Directory('${root.path}/config')..createSync();
    File('$fixtures/window.kcs').copySync('${root.path}/window.kcs');
    File('${config.path}/startup.xml').writeAsStringSync('''
<?xml version="1.0" encoding="UTF-8"?>
<document><SCREEN><width>64</width><height>48</height></SCREEN>
<SCRIPT><start>window</start></SCRIPT>
<INT><int00><name>kcs</name><dir>.</dir><ext>kcs</ext></int00>
<int01><name>config</name><dir>config</dir><ext>xml</ext></int01></INT></document>
''');
    final actions = <EngineWindowAction>[];
    final runtime = EngineRuntimeFactory.create(
      engine: GameEngineKind.katze,
      onWindowAction: actions.add,
    );
    addTearDown(runtime.shutdown);
    await runtime.initialize();
    final project = await runtime.prepareProject(
      projectPath: root.path,
      isArchive: false,
      environmentPatchEnabled: false,
      platform: 'WINDOWS',
    );
    runtime.setWindowStateBits(fullscreen: false);
    expect(await runtime.loadProjectBytes(project!), isTrue);
    expect(runtime.advanceWithoutRender(17), isTrue);
    expect(actions.take(2), [
      EngineWindowAction.toggleFullscreen,
      EngineWindowAction.minimize,
    ]);
    runtime.setWindowStateBits(fullscreen: true);
    expect(runtime.advanceWithoutRender(17), isTrue);
  });
}
