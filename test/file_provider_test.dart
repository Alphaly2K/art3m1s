import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:art3m1s/engine/backends/art3m1s/file_provider.dart';
import 'package:art3m1s/engine/backends/art3m1s/project_asset_store.dart';
import 'package:flutter_test/flutter_test.dart';

/// 最小 PF6 归档，用于验证解包目录与分卷的叠加优先级。
Uint8List _buildPf6(List<(String, String)> files) {
  final encoded = files
      .map((entry) => (entry.$1, utf8.encode(entry.$2)))
      .toList();
  final entriesLen = encoded.fold<int>(
    0,
    (sum, entry) => sum + 4 + entry.$1.length + 4 + 4 + 4,
  );
  final entryCount = encoded.length;
  final indexSize = 4 + entriesLen + 4 + 8 * (entryCount + 1) + 4;
  final dataStart = 7 + indexSize;

  final out = BytesBuilder();
  out.add(utf8.encode('pf6'));
  out.add(_u32(indexSize));
  out.add(_u32(entryCount));
  var offset = dataStart;
  for (final (name, data) in encoded) {
    out.add(_u32(name.length));
    out.add(utf8.encode(name));
    out.add(_u32(0));
    out.add(_u32(offset));
    out.add(_u32(data.length));
    offset += data.length;
  }
  out.add(_u32(entryCount + 1));
  out.add(Uint8List(8 * (entryCount + 1)));
  out.add(_u32(7 + 4 + entriesLen));
  for (final (_, data) in encoded) {
    out.add(data);
  }
  return out.toBytes();
}

List<int> _u32(int value) => [
  value & 0xff,
  (value >> 8) & 0xff,
  (value >> 16) & 0xff,
  (value >> 24) & 0xff,
];

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

  test('hybrid project layers loose files over patch and base volumes', () {
    File('${project.path}/root.pfs').writeAsBytesSync(
      _buildPf6([
        ('system/first.iet', 'base-boot'),
        ('system/base-only.txt', 'base-only'),
        ('font/base.ttf', 'base-font'),
      ]),
    );
    File('${project.path}/root.pfs.006').writeAsBytesSync(
      _buildPf6([
        ('system/first.iet', 'patch-boot'),
        ('system/patch-only.txt', 'patch-only'),
      ]),
    );
    // 解包目录里的散装文件优先级最高。
    File('${project.path}/system/first.iet').writeAsStringSync('loose-boot');

    FileProvider.openDirectory(project.path);

    expect(FileProvider.hasArchiveLayers, isTrue);
    expect(
      utf8.decode(FileProvider.readFile('system/first.iet')!),
      'loose-boot',
    );
    expect(
      utf8.decode(FileProvider.readFile(r'system\patch-only.txt')!),
      'patch-only',
    );
    expect(
      utf8.decode(FileProvider.readFile('system/base-only.txt')!),
      'base-only',
    );
    expect(utf8.decode(FileProvider.readFile('font/base.ttf')!), 'base-font');
    expect(
      FileProvider.listFiles(extension: '.txt'),
      containsAll(<String>['system/base-only.txt', 'system/patch-only.txt']),
    );
  });

  test('archive project layers sidecar files over patch and base volumes', () {
    File('${project.path}/root.pfs').writeAsBytesSync(
      _buildPf6([
        ('system/first.iet', 'base-boot'),
        ('movie/op.dat', 'base-movie'),
      ]),
    );
    File(
      '${project.path}/root.pfs.003',
    ).writeAsBytesSync(_buildPf6([('system/first.iet', 'patch-boot')]));
    File('${project.path}/movie/op.dat')
      ..createSync(recursive: true)
      ..writeAsStringSync('sidecar-movie');

    FileProvider.openPfs('${project.path}/root.pfs');

    expect(
      utf8.decode(FileProvider.readFile('system/first.iet')!),
      'patch-boot',
    );
    expect(
      utf8.decode(FileProvider.readFile('movie/op.dat')!),
      'sidecar-movie',
    );
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

  test('project asset store reads hybrid project archives', () {
    File(
      '${project.path}/root.pfs',
    ).writeAsBytesSync(_buildPf6([('sound/se/beep.ogg', 'archive-beep')]));
    final store = ProjectAssetStore()
      ..openProject(project.path, isArchive: false);
    addTearDown(store.close);

    expect(store.read('sound/se/beep.ogg'), utf8.encode('archive-beep'));
  });
}
