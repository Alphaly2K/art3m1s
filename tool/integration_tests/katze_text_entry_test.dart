import 'dart:io';

import 'package:art3m1s/engine/engine_runtime.dart';
import 'package:art3m1s/engine/engine_runtime_factory.dart';
import 'package:art3m1s/models/game_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'Katze player preserves an open text request and reads the reply',
    () async {
      final fixtures = Platform.environment['KATZE_FIXTURES'];
      if (fixtures == null ||
          Platform.environment['KATZE_OFFSCREEN_AUDIO'] != '1') {
        throw StateError('Set KATZE_FIXTURES and KATZE_OFFSCREEN_AUDIO=1');
      }
      final root = Directory.systemTemp.createTempSync('katze-text-');
      addTearDown(() => root.deleteSync(recursive: true));
      final config = Directory('${root.path}/config')..createSync();
      File('$fixtures/text-entry.kcs').copySync('${root.path}/text-entry.kcs');
      File('${config.path}/startup.xml').writeAsStringSync('''
<?xml version="1.0" encoding="UTF-8"?>
<document><SCREEN><width>64</width><height>48</height></SCREEN>
<SCRIPT><start>text-entry</start></SCRIPT>
<INT><int00><name>kcs</name><dir>.</dir><ext>kcs</ext></int00>
<int01><name>config</name><dir>config</dir><ext>xml</ext></int01></INT></document>
''');
      final dialogs = <EngineDialogRequest>[];
      final runtime = EngineRuntimeFactory.create(
        engine: GameEngineKind.katze,
        onDialogRequested: dialogs.add,
      );
      addTearDown(runtime.shutdown);
      await runtime.initialize();
      final project = await runtime.prepareProject(
        projectPath: root.path,
        isArchive: false,
        environmentPatchEnabled: false,
        platform: 'WINDOWS',
      );
      expect(await runtime.loadProjectBytes(project!), isTrue);
      expect(runtime.advanceWithoutRender(17), isTrue);
      expect(dialogs.single.initialText, '猫');
      expect(runtime.advanceWithoutRender(17), isTrue);
      expect(dialogs, hasLength(1));
      expect(runtime.submitDialog(true, 'あ'), isTrue);
      expect(runtime.submitDialog(false, ''), isFalse);
      expect(runtime.advanceWithoutRender(17), isTrue);
      expect(dialogs, hasLength(2));
      expect(dialogs.last.initialText, '猫');
      expect(runtime.submitDialog(true, ''), isTrue);
      expect(runtime.advanceWithoutRender(17), isTrue);
      expect(dialogs, hasLength(3));
      expect(dialogs.last.initialText, '');
      expect(runtime.submitDialog(false, ''), isTrue);
      expect(runtime.advanceWithoutRender(17), isTrue);
      expect(dialogs, hasLength(3));
    },
  );
}
