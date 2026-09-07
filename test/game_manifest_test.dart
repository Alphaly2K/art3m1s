import 'dart:convert';
import 'dart:io';

import 'package:art3m1s/models/game_entry.dart';
import 'package:art3m1s/models/input_gate.dart';
import 'package:art3m1s/services/game_manifest.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('GameManifest.parse', () {
    test('parses a full manifest', () {
      final manifest = GameManifest.parse(
        utf8.encode(
          jsonEncode({
            'name': 'NekoMiko',
            'vndbId': 'v23658',
            'translationEnabled': true,
            'translationPatchPath': 'patch/zh.json',
            'environmentPatchEnabled': true,
            'experimentalElunaEnabled': false,
            'fontOverride': 'font/cjk.ttf',
            'reportedOs': 'ps4',
            'inputGate': {
              'keyboard': false,
              'blockedKeys': [27],
            },
          }),
        ),
      )!;
      expect(manifest.name, 'NekoMiko');
      expect(manifest.vndbId, 'v23658');
      expect(manifest.translationEnabled, isTrue);
      expect(manifest.translationPatchPath, 'patch/zh.json');
      expect(manifest.environmentPatchEnabled, isTrue);
      expect(manifest.experimentalElunaEnabled, isFalse);
      expect(manifest.fontOverride, 'font/cjk.ttf');
      expect(manifest.reportedOs, 'ps4');
      expect(manifest.inputGate!.keyboard, isFalse);
      expect(manifest.inputGate!.blockedKeys, {27});
      // 清单里的门控 JSON 缺省字段保持全放行默认。
      expect(manifest.inputGate!.touch, isTrue);
    });

    test('missing fields stay null so callers can fall back', () {
      final manifest = GameManifest.parse(utf8.encode('{}'))!;
      expect(manifest.name, isNull);
      expect(manifest.vndbId, isNull);
      expect(manifest.translationEnabled, isNull);
      expect(manifest.fontOverride, isNull);
      expect(manifest.inputGate, isNull);
    });

    test('rejects non-object and malformed json', () {
      expect(GameManifest.parse(utf8.encode('[]')), isNull);
      expect(GameManifest.parse(utf8.encode('not json')), isNull);
      expect(GameManifest.parse(utf8.encode('')), isNull);
    });

    test('wrong-typed fields degrade to null instead of crashing', () {
      final manifest = GameManifest.parse(
        utf8.encode(
          jsonEncode({
            'name': 42,
            'translationEnabled': 'yes',
            'inputGate': 'keyboard:false',
          }),
        ),
      )!;
      expect(manifest.name, '42'); // 数字名转字符串是善意行为
      expect(manifest.translationEnabled, isNull);
      expect(manifest.inputGate, isNull);
    });
  });

  group('GameManifest.selectManifestPath', () {
    test('accepts root and one level deep, case-insensitive', () {
      expect(GameManifest.selectManifestPath(['art3m1s.json']), 'art3m1s.json');
      expect(
        GameManifest.selectManifestPath(['patch/Art3M1S.JSON']),
        'patch/Art3M1S.JSON',
      );
    });

    test('ignores files deeper than two levels', () {
      expect(GameManifest.selectManifestPath(['a/b/art3m1s.json']), isNull);
      expect(
        GameManifest.selectManifestPath(['a/b/c/art3m1s.json', 'x.json']),
        isNull,
      );
    });

    test('picks the first match and tolerates windows separators', () {
      expect(
        GameManifest.selectManifestPath(['sub/art3m1s.json', 'art3m1s.json']),
        'sub/art3m1s.json',
      );
      expect(
        GameManifest.selectManifestPath([r'patch\art3m1s.json']),
        'patch/art3m1s.json',
      );
    });
  });

  group('GameManifest.discover (directory)', () {
    test('finds a manifest one level below the root', () async {
      final dir = await Directory.systemTemp.createTemp('manifest_test');
      try {
        final sub = Directory('${dir.path}/patch')..createSync();
        File('${sub.path}/art3m1s.json').writeAsStringSync(
          jsonEncode({'name': '测试游戏', 'environmentPatchEnabled': true}),
        );
        final manifest = await GameManifest.discover(
          dir.path,
          GameSource.directory,
        );
        expect(manifest, isNotNull);
        expect(manifest!.name, '测试游戏');
        expect(manifest.environmentPatchEnabled, isTrue);
      } finally {
        await dir.delete(recursive: true);
      }
    });

    test('ignores manifests two levels below the root', () async {
      final dir = await Directory.systemTemp.createTemp('manifest_test');
      try {
        final deep = Directory('${dir.path}/a/b')..createSync(recursive: true);
        File(
          '${deep.path}/art3m1s.json',
        ).writeAsStringSync(jsonEncode({'name': '太深'}));
        final manifest = await GameManifest.discover(
          dir.path,
          GameSource.directory,
        );
        expect(manifest, isNull);
      } finally {
        await dir.delete(recursive: true);
      }
    });

    test('returns null for directories without a manifest', () async {
      final dir = await Directory.systemTemp.createTemp('manifest_test');
      try {
        File('${dir.path}/system.ini').writeAsStringSync('[System]\n');
        expect(
          await GameManifest.discover(dir.path, GameSource.directory),
          isNull,
        );
      } finally {
        await dir.delete(recursive: true);
      }
    });
  });

  group('GameManifest.readGameFile', () {
    test('reads a file inside the game directory', () async {
      final dir = await Directory.systemTemp.createTemp('manifest_test');
      try {
        File('${dir.path}/font.ttf').writeAsBytesSync([1, 2, 3]);
        final bytes = await GameManifest.readGameFile(
          dir.path,
          GameSource.directory,
          'font.ttf',
        );
        expect(bytes, [1, 2, 3]);
      } finally {
        await dir.delete(recursive: true);
      }
    });

    test('rejects path traversal outside the game directory', () async {
      final dir = await Directory.systemTemp.createTemp('manifest_test');
      try {
        expect(
          await GameManifest.readGameFile(
            dir.path,
            GameSource.directory,
            '../../etc/passwd',
          ),
          isNull,
        );
      } finally {
        await dir.delete(recursive: true);
      }
    });

    test('returns null for missing files', () async {
      final dir = await Directory.systemTemp.createTemp('manifest_test');
      try {
        expect(
          await GameManifest.readGameFile(
            dir.path,
            GameSource.directory,
            'nope.ttf',
          ),
          isNull,
        );
      } finally {
        await dir.delete(recursive: true);
      }
    });
  });

  group('GameEntry manifest fields', () {
    test('vndbId and fontOverridePath round trip through json', () {
      final entry = GameEntry(
        name: 'n',
        path: '/tmp/g',
        source: GameSource.directory,
        addedAt: DateTime(2026),
        vndbId: 'v23658',
        fontOverridePath: 'font/cjk.ttf',
        reportedOs: 'switch',
        inputGate: InputGatePolicy.touchOnly,
      );
      final restored = GameEntry.fromJson(entry.toJson());
      expect(restored.vndbId, 'v23658');
      expect(restored.fontOverridePath, 'font/cjk.ttf');
      expect(restored.reportedOs, 'switch');
      expect(restored.inputGate.knownProfile, InputGateProfile.touchOnly);
    });

    test('old library json without manifest fields decodes to defaults', () {
      final entry = GameEntry.fromJson({
        'name': 'n',
        'path': '/tmp/g',
        'source': 'directory',
        'addedAt': '2026-01-01T00:00:00.000',
      });
      expect(entry.vndbId, '');
      expect(entry.fontOverridePath, '');
      expect(entry.inputGate.isFull, isTrue);
    });

    test(
      'uses a direct directory manifest as the authoritative settings file',
      () async {
        final dir = await Directory.systemTemp.createTemp('manifest_test');
        try {
          final entry = GameEntry(
            name: 'n',
            path: dir.path,
            source: GameSource.directory,
            addedAt: DateTime(2026),
            displayName: '显示名',
            translationEnabled: true,
            translationPatchPath: 'patch/zh.json',
            reportedOs: 'switch',
            runtimePlatform: 'IOS',
          );
          final path = await GameManifest.writeForProject(
            dir.path,
            GameSource.directory,
            GameManifest.fromGameEntry(entry),
          );

          expect(path, '${dir.path}/art3m1s.json');
          final loaded = await GameManifest.loadEntrySettings(
            entry.copyWith(manifestPath: path, runtimePlatform: 'WINDOWS'),
          );
          expect(loaded.displayName, '显示名');
          expect(loaded.translationEnabled, isTrue);
          expect(loaded.translationPatchPath, 'patch/zh.json');
          expect(loaded.reportedOs, 'switch');
          expect(loaded.runtimePlatform, 'IOS');
          expect(loaded.manifestPath, path);
        } finally {
          await dir.delete(recursive: true);
        }
      },
    );

    test('stores PFS settings in a sidecar manifest', () {
      expect(
        GameManifest.manifestPathFor('/games/root.pfs', GameSource.pfsArchive),
        '/games/root.pfs.art3m1s.json',
      );
    });
  });
}
