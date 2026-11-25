import 'dart:io';

import 'package:art3m1s/engine/backends/katze_engine_runtime.dart';
import 'package:art3m1s/services/logger.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Katze logs script messages before and during a frame error', () async {
    final fixtures = Platform.environment['KATZE_FIXTURES'];
    if (fixtures == null ||
        Platform.environment['KATZE_OFFSCREEN_AUDIO'] != '1') {
      throw StateError('Set KATZE_FIXTURES and KATZE_OFFSCREEN_AUDIO=1');
    }
    final root = Directory.systemTemp.createTempSync('katze-script-log-');
    addTearDown(() => root.deleteSync(recursive: true));
    final documents = Directory('${root.path}/logs')..createSync();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
    messenger.setMockMethodCallHandler(pathProvider, (call) async {
      expect(call.method, 'getApplicationDocumentsDirectory');
      return documents.path;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(pathProvider, null));

    final config = Directory('${root.path}/config')..createSync();
    File(
      '$fixtures/script-messages.kcs',
    ).copySync('${root.path}/script-messages.kcs');
    File('${config.path}/startup.xml').writeAsStringSync('''
<?xml version="1.0" encoding="UTF-8"?>
<document><SCREEN><width>64</width><height>48</height></SCREEN>
<SCRIPT><start>script-messages</start></SCRIPT>
<INT><int00><name>kcs</name><dir>.</dir><ext>kcs</ext></int00>
<int01><name>config</name><dir>config</dir><ext>xml</ext></int01></INT></document>
''');
    Log.clear();
    Log.setDebugEnabled(true);
    Log.startRuntimeSession();
    addTearDown(() {
      Log.endRuntimeSession();
      Log.setDebugEnabled(false);
      Log.clear();
    });

    final runtime = KatzeEngineRuntime()..scriptEncoding = 'cp932';
    addTearDown(runtime.shutdown);
    await runtime.initialize();
    final project = await runtime.prepareProject(
      projectPath: root.path,
      isArchive: false,
      environmentPatchEnabled: false,
      platform: 'WINDOWS',
    );
    expect(runtime.loadProjectBytes(project!), isTrue);
    expect(runtime.advanceWithoutRender(17), isTrue);
    await expectLater(runtime.advancePixelBatch([17]), throwsStateError);

    const expected = [
      '[Katze] [Script] 猫のログ',
      '[Katze] [Script] 中文日志\n',
      '[Katze] [Script] 失敗前',
      '[Katze] [Script] 错误前\n',
    ];
    expect(
      Log.entries
          .where((entry) => entry.level == 'D')
          .map((entry) => entry.message),
      expected,
    );
    final exported = await (await Log.exportToFile()).readAsString();
    for (final message in expected) {
      expect(exported, contains('[D] $message'));
    }
  });
}
