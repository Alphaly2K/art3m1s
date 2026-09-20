import 'dart:io';

import 'package:art3m1s/engine/backends/art3m1s/file_provider.dart';
import 'package:art3m1s/engine/backends/art3m1s/project_asset_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory project;

  setUp(() {
    project = Directory.systemTemp.createTempSync('art3m1s_file_index_');
    Directory('${project.path}/system').createSync(recursive: true);
  });

  tearDown(() {
    FileProvider.close();
    project.deleteSync(recursive: true);
  });

  test(
    'indexed hits read bytes and misses return null without touching disk',
    () {
      File('${project.path}/system/first.iet').writeAsStringSync('boot');
      FileProvider.openDirectory(project.path);

      final bytes = FileProvider.readFile('system/first.iet');
      expect(bytes, isNotNull);
      expect(String.fromCharCodes(bytes!), 'boot');
      expect(FileProvider.readFile('system/missing.iet'), isNull);
      // 索引建立后新落的文件不出现在索引里（资源目录在会话内视为只读）。
      File('${project.path}/system/late.iet').writeAsStringSync('late');
      expect(FileProvider.readFile('system/late.iet'), isNull);
    },
  );

  test('directory index resolves case and separator variants', () {
    File('${project.path}/system/Title.PNG').writeAsBytesSync([1, 2, 3]);
    FileProvider.openDirectory(project.path);

    // 脚本候选路径的大小写/分隔符变体应命中同一文件（与 macOS/Windows
    // 文件系统的大小写不敏感行为一致）。
    expect(FileProvider.readFile('system/title.png'), isNotNull);
    expect(FileProvider.readFile(r'system\TITLE.PNG'), isNotNull);
  });

  test('listFiles is served from the index with extension filter', () {
    File('${project.path}/system/first.iet').writeAsStringSync('boot');
    File('${project.path}/system/title.png').writeAsBytesSync([1]);
    FileProvider.openDirectory(project.path);

    final tblOnly = FileProvider.listFiles(extension: '.iet');
    expect(tblOnly, ['system/first.iet']);
    expect(FileProvider.listFiles(), hasLength(2));
  });

  test('environment patch overlay wins over the index', () {
    FileProvider.openDirectory(project.path, environmentPatchEnabled: true);

    final patched = FileProvider.readFile('system/dmm.lua');
    expect(patched, isNotNull);
    expect(
      String.fromCharCodes(patched!),
      contains('environment compatibility patch'),
    );
  });

  test('listArchiveCandidates keeps split volumes and skips AppleDouble', () {
    File('${project.path}/game.pfs').writeAsBytesSync([1]);
    File('${project.path}/game.pfs.000').writeAsBytesSync([2]);
    File('${project.path}/._game.pfs.001').writeAsBytesSync([3]);

    final names = FileProvider.listArchiveCandidates(
      '${project.path}/game.pfs',
    ).map((path) => path.split(RegExp(r'[/\\]')).last).toList();

    expect(names, ['game.pfs', 'game.pfs.000']);
  });

  test(
    'project asset store reads directory files and rejects unsafe paths',
    () {
      File('${project.path}/sound/se/beep.ogg')
        ..createSync(recursive: true)
        ..writeAsBytesSync([9, 8, 7]);
      final store = ProjectAssetStore()..openDirectory(project.path);
      addTearDown(store.close);

      expect(store.read('sound/se/beep.ogg'), [9, 8, 7]);
      expect(store.read(r'sound\se\beep.ogg'), [9, 8, 7]);
      expect(store.read('sound/se/../se/beep.ogg'), isNull);
      expect(store.read('sound/se/beep:ogg'), isNull);
      FileProvider.detachCoreMount();
      expect(store.read('sound/se/beep.ogg'), [9, 8, 7]);
    },
  );
}
