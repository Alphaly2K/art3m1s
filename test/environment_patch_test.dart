import 'dart:convert';
import 'dart:io';

import 'package:art3m1s/services/file_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory project;
  late File firstScript;

  setUp(() {
    project = Directory.systemTemp.createTempSync('art3m1s_env_patch_');
    final system = Directory('${project.path}/system')
      ..createSync(recursive: true);
    firstScript = File('${system.path}/first.iet')
      ..writeAsStringSync('''
*top
/*
[var name="t.os" system="os"]
[if estimate="\$t.os == 'windows'"]
[exit]
[/if]
*/
[lua]
function later()
  e:tag{"exit"}
end
[/lua]
''');
  });

  tearDown(() {
    FileProvider.close();
    project.deleteSync(recursive: true);
  });

  test('disabled project receives original files and no virtual scripts', () {
    FileProvider.openDirectory(project.path);

    expect(
      utf8.decode(FileProvider.readFile('system/first.iet')!),
      firstScript.readAsStringSync(),
    );
    expect(FileProvider.readFile('system/dmm.lua'), isNull);
  });

  test('enabled project bypasses only known environment bootstrap files', () {
    final texture = File('${project.path}/system/title.png')
      ..writeAsBytesSync([1, 2, 3]);
    FileProvider.openDirectory(project.path, environmentPatchEnabled: true);

    final patched = utf8.decode(FileProvider.readFile('system/first.iet')!);
    expect(patched, contains('// [var name="t.os" system="os"]'));
    expect(patched, contains('// [exit]'));
    expect(patched, contains('e:tag{"exit"}'));
    expect(
      utf8.decode(FileProvider.readFile('system/dmm.lua')!),
      contains('environment compatibility patch'),
    );
    expect(FileProvider.readFile('system/missing.png'), isNull);
    expect(
      FileProvider.readFile('system/title.png'),
      texture.readAsBytesSync(),
    );
  });

  test('directory enumeration returns relative table paths only', () {
    final table = File('${project.path}/system/table/list_windows_ja.tbl')
      ..createSync(recursive: true)
      ..writeAsStringSync('gametitle="title"');
    File(
      '${project.path}/system/table/ignored.lua',
    ).writeAsStringSync('gametitle="wrong"');
    FileProvider.openDirectory(project.path);

    final paths = FileProvider.listFiles(extension: '.tbl');
    expect(paths, contains('system/table/list_windows_ja.tbl'));
    expect(paths, isNot(contains(table.path)));
    expect(paths, hasLength(1));
  });
}
