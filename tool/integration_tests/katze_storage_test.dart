import 'dart:ffi';
import 'dart:io';

import 'package:art3m1s/engine/backends/katze/katze_game_host.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Katze saves survive destruction and remount', () {
    final configuredHost = Platform.environment['KATZE_GAME_HOST'];
    final configuredFixtures = Platform.environment['KATZE_FIXTURES'];
    if (configuredHost == null || configuredFixtures == null) {
      throw StateError('Set KATZE_GAME_HOST and KATZE_FIXTURES');
    }
    final library = DynamicLibrary.open(configuredHost);
    final root = Directory.systemTemp.createTempSync('katze-storage-');
    addTearDown(() => root.deleteSync(recursive: true));
    final game = Directory('${root.path}/game')..createSync();
    final config = Directory('${game.path}/config')..createSync();
    final saveDirectory = Directory('${root.path}/saves');
    final startup = File('${config.path}/startup.xml');
    void run(String entry, Directory storage) {
      File(
        '$configuredFixtures/$entry.kcs',
      ).copySync('${game.path}/$entry.kcs');
      startup.writeAsStringSync('''
<?xml version="1.0" encoding="UTF-8"?>
<document><SCREEN><width>64</width><height>48</height></SCREEN>
<SCRIPT><start>$entry</start></SCRIPT>
<INT><int00><name>kcs</name><dir>.</dir><ext>kcs</ext></int00>
<int01><name>config</name><dir>config</dir><ext>xml</ext></int01></INT></document>
''');
      final session = KatzeGameHost.open(
        library,
        game.path,
        saveDirectory: storage.path,
      );
      try {
        expect(session.step(increment: 1, milliseconds: 16), isTrue);
      } finally {
        session.close();
      }
    }

    run('host-write', saveDirectory);
    final slot = File('${saveDirectory.path}/host-slot.css');
    expect(slot.existsSync(), isTrue);
    expect(File('${game.path}/host-slot.css').existsSync(), isFalse);
    expect(slot.readAsBytesSync().take(4), [67, 83, 83, 0]);
    run('host-read', saveDirectory);
    final empty = Directory('${root.path}/empty');
    expect(() => run('host-read', empty), throwsStateError);
  });
}
