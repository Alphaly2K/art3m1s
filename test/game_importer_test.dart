import 'dart:io';

import 'package:art3m1s/models/game_engine.dart';
import 'package:art3m1s/services/game_importer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('discoverBasePfsFiles returns every game but not split volumes', () {
    final root = Directory.systemTemp.createTempSync('art3m1s_multi_pfs_');
    addTearDown(() => root.deleteSync(recursive: true));

    File('${root.path}${Platform.pathSeparator}zeta.pfs').writeAsBytesSync([1]);
    File(
      '${root.path}${Platform.pathSeparator}zeta.pfs.000',
    ).writeAsBytesSync([2]);
    final nested = Directory('${root.path}${Platform.pathSeparator}nested')
      ..createSync();
    File(
      '${nested.path}${Platform.pathSeparator}Alpha.PFS',
    ).writeAsBytesSync([3]);
    File(
      '${nested.path}${Platform.pathSeparator}readme.txt',
    ).writeAsBytesSync([4]);

    final discovered = GameImporter.discoverBasePfsFiles(root.path);

    expect(discovered, [
      '${nested.path}${Platform.pathSeparator}Alpha.PFS',
      '${root.path}${Platform.pathSeparator}zeta.pfs',
    ]);
  });

  test('discoverBasePfsFiles safely handles a missing directory', () {
    expect(
      GameImporter.discoverBasePfsFiles(
        '${Directory.systemTemp.path}${Platform.pathSeparator}missing-art3m1s',
      ),
      isEmpty,
    );
  });

  test(
    'discoverUnpackedProjects finds system.ini roots and ignores nested copies',
    () {
      final root = Directory.systemTemp.createTempSync('art3m1s_unpacked_');
      addTearDown(() => root.deleteSync(recursive: true));

      File(
        '${root.path}${Platform.pathSeparator}system.ini',
      ).writeAsStringSync('[boot]');
      Directory('${root.path}${Platform.pathSeparator}image').createSync();
      File(
        '${root.path}${Platform.pathSeparator}image${Platform.pathSeparator}system.ini',
      ).writeAsStringSync('not a game');

      expect(GameImporter.discoverUnpackedProjects(root.path), [root.path]);
    },
  );

  test('discoverUnpackedProjects finds RFVP roots by HCB marker', () {
    final root = Directory.systemTemp.createTempSync('art3m1s_rfvp_');
    addTearDown(() => root.deleteSync(recursive: true));

    File(
      '${root.path}${Platform.pathSeparator}World.hcb',
    ).writeAsBytesSync([1, 2, 3]);
    Directory('${root.path}${Platform.pathSeparator}save').createSync();
    File(
      '${root.path}${Platform.pathSeparator}save${Platform.pathSeparator}Other.hcb',
    ).writeAsBytesSync([4]);

    expect(GameImporter.discoverUnpackedProjects(root.path), [root.path]);
    expect(GameImporter.detectDirectoryEngine(root.path), GameEngineKind.rfvp);
  });

  test('directory detection prefers Artemis when system.ini is present', () {
    final root = Directory.systemTemp.createTempSync('art3m1s_mixed_');
    addTearDown(() => root.deleteSync(recursive: true));

    File(
      '${root.path}${Platform.pathSeparator}system.ini',
    ).writeAsStringSync('[boot]');
    File(
      '${root.path}${Platform.pathSeparator}World.hcb',
    ).writeAsBytesSync([1]);

    expect(
      GameImporter.detectDirectoryEngine(root.path),
      GameEngineKind.art3m1s,
    );
  });

  test('discovers KRKR roots by data.xp3 case-insensitively', () {
    final root = Directory.systemTemp.createTempSync('art3m1s_krkr_');
    addTearDown(() => root.deleteSync(recursive: true));
    final game = Directory('${root.path}${Platform.pathSeparator}game')
      ..createSync();
    File('${game.path}${Platform.pathSeparator}DATA.XP3').writeAsBytesSync([1]);
    Directory('${game.path}${Platform.pathSeparator}savedata').createSync();
    File(
      '${game.path}${Platform.pathSeparator}savedata${Platform.pathSeparator}patch.xp3',
    ).writeAsBytesSync([2]);

    expect(GameImporter.discoverUnpackedProjects(root.path), [game.path]);
    expect(GameImporter.detectDirectoryEngine(game.path), GameEngineKind.krkr);
  });

  test('detects KRKR root with startup.tjs or exactly one XP3', () {
    final root = Directory.systemTemp.createTempSync('art3m1s_krkr_markers_');
    addTearDown(() => root.deleteSync(recursive: true));
    final startup = Directory('${root.path}${Platform.pathSeparator}startup')
      ..createSync();
    File(
      '${startup.path}${Platform.pathSeparator}Startup.TJS',
    ).writeAsBytesSync([1]);
    final soleXp3 = Directory('${root.path}${Platform.pathSeparator}sole')
      ..createSync();
    File(
      '${soleXp3.path}${Platform.pathSeparator}game.XP3',
    ).writeAsBytesSync([2]);

    expect(
      GameImporter.detectDirectoryEngine(startup.path),
      GameEngineKind.krkr,
    );
    expect(
      GameImporter.detectDirectoryEngine(soleXp3.path),
      GameEngineKind.krkr,
    );
  });

  test(
    'discoverUnpackedProjects searches nested folders case-insensitively',
    () {
      final root = Directory.systemTemp.createTempSync(
        'art3m1s_unpacked_nested_',
      );
      addTearDown(() => root.deleteSync(recursive: true));

      final first = Directory('${root.path}${Platform.pathSeparator}NekoMiko')
        ..createSync();
      File(
        '${first.path}${Platform.pathSeparator}System.INI',
      ).writeAsStringSync('[boot]');
      final second = Directory('${root.path}${Platform.pathSeparator}other')
        ..createSync();
      File(
        '${second.path}${Platform.pathSeparator}system.ini',
      ).writeAsStringSync('[boot]');

      expect(GameImporter.discoverUnpackedProjects(root.path), [
        first.path,
        second.path,
      ]);
    },
  );

  test('discoverUnpackedProjects safely handles a missing directory', () {
    expect(
      GameImporter.discoverUnpackedProjects(
        '${Directory.systemTemp.path}${Platform.pathSeparator}missing-art3m1s-unpacked',
      ),
      isEmpty,
    );
  });
  test('library paths ignore trailing slashes and iOS /private prefix', () {
    expect(
      GameImporter.normalizeLibraryPath('/var/mobile/Containers/Data/game/'),
      '/var/mobile/Containers/Data/game',
    );
    expect(
      GameImporter.isSameLibraryPath(
        '/private/var/mobile/Containers/Data/game/',
        '/var/mobile/Containers/Data/game',
      ),
      isTrue,
    );
    expect(
      GameImporter.libraryContainsPath([
        '/var/mobile/Games/NekoMiko',
      ], '/private/var/mobile/Games/NekoMiko/'),
      isTrue,
    );
  });

  test('managed import delete removes the whole incoming batch', () {
    final root = Directory.systemTemp.createTempSync('art3m1s_managed_games_');
    addTearDown(() => root.deleteSync(recursive: true));

    final incoming = Directory(
      '${root.path}${Platform.pathSeparator}incoming${Platform.pathSeparator}123',
    )..createSync(recursive: true);
    final gameDir = Directory(
      '${incoming.path}${Platform.pathSeparator}MagicalCharming',
    )..createSync();
    File(
      '${gameDir.path}${Platform.pathSeparator}system.ini',
    ).writeAsStringSync('[boot]');
    File(
      '${incoming.path}${Platform.pathSeparator}keep.txt',
    ).writeAsStringSync('stay');

    GameImporter.deleteManagedImport(gameDir.path, [root.path]);

    expect(gameDir.existsSync(), isFalse);
    expect(incoming.existsSync(), isFalse);
    expect(
      Directory('${root.path}${Platform.pathSeparator}incoming').existsSync(),
      isFalse,
    );
    expect(root.existsSync(), isTrue);
  });

  test('managed import delete prunes empty timestamp folders only', () {
    final root = Directory.systemTemp.createTempSync('art3m1s_managed_prune_');
    addTearDown(() => root.deleteSync(recursive: true));

    final incoming = Directory(
      '${root.path}${Platform.pathSeparator}incoming${Platform.pathSeparator}456',
    )..createSync(recursive: true);
    final gameDir = Directory(
      '${incoming.path}${Platform.pathSeparator}OnlyGame',
    )..createSync();
    File(
      '${gameDir.path}${Platform.pathSeparator}system.ini',
    ).writeAsStringSync('[boot]');

    GameImporter.deleteManagedImport(gameDir.path, [root.path]);

    expect(gameDir.existsSync(), isFalse);
    expect(incoming.existsSync(), isFalse);
    expect(
      Directory('${root.path}${Platform.pathSeparator}incoming').existsSync(),
      isFalse,
    );
    expect(root.existsSync(), isTrue);
  });

  test('managed import delete does not touch unmanaged directories', () {
    final root = Directory.systemTemp.createTempSync('art3m1s_unmanaged_');
    addTearDown(() => root.deleteSync(recursive: true));
    final outside = Directory('${root.path}${Platform.pathSeparator}original')
      ..createSync();
    File(
      '${outside.path}${Platform.pathSeparator}system.ini',
    ).writeAsStringSync('[boot]');

    GameImporter.deleteManagedImport(outside.path, [
      '${root.path}${Platform.pathSeparator}games',
    ]);

    expect(outside.existsSync(), isTrue);
  });

  test('managed pfs delete removes the whole imported directory', () {
    final root = Directory.systemTemp.createTempSync('art3m1s_pfs_import_');
    addTearDown(() => root.deleteSync(recursive: true));
    final batch = Directory(
      '${root.path}${Platform.pathSeparator}incoming${Platform.pathSeparator}789',
    )..createSync(recursive: true);
    final dir = Directory('${batch.path}${Platform.pathSeparator}Game')
      ..createSync();
    final base = File('${dir.path}${Platform.pathSeparator}game.pfs')
      ..writeAsBytesSync([1]);
    File(
      '${dir.path}${Platform.pathSeparator}game.pfs.000',
    ).writeAsBytesSync([2]);
    File(
      '${dir.path}${Platform.pathSeparator}readme.txt',
    ).writeAsStringSync('extra');

    GameImporter.deleteManagedImport(base.path, [root.path]);

    expect(base.existsSync(), isFalse);
    expect(dir.existsSync(), isFalse);
    expect(batch.existsSync(), isFalse);
    expect(
      Directory('${root.path}${Platform.pathSeparator}incoming').existsSync(),
      isFalse,
    );
  });

  test('shared incoming batch keeps other library games', () {
    final root = Directory.systemTemp.createTempSync('art3m1s_pfs_shared_');
    addTearDown(() => root.deleteSync(recursive: true));
    final batch = Directory(
      '${root.path}${Platform.pathSeparator}incoming${Platform.pathSeparator}321',
    )..createSync(recursive: true);
    final dir = Directory('${batch.path}${Platform.pathSeparator}Pack')
      ..createSync();
    final first = File('${dir.path}${Platform.pathSeparator}gameA.pfs')
      ..writeAsBytesSync([1]);
    File(
      '${dir.path}${Platform.pathSeparator}gameA.pfs.000',
    ).writeAsBytesSync([2]);
    final second = File('${dir.path}${Platform.pathSeparator}gameB.pfs')
      ..writeAsBytesSync([3]);
    File(
      '${dir.path}${Platform.pathSeparator}readme.txt',
    ).writeAsStringSync('shared');

    GameImporter.deleteManagedImport(
      first.path,
      [root.path],
      retainedPaths: [second.path],
    );

    expect(first.existsSync(), isFalse);
    expect(
      File('${dir.path}${Platform.pathSeparator}gameA.pfs.000').existsSync(),
      isFalse,
    );
    expect(second.existsSync(), isTrue);
    expect(
      File('${dir.path}${Platform.pathSeparator}readme.txt').existsSync(),
      isTrue,
    );
    expect(batch.existsSync(), isTrue);
  });

  test('probeGameFolder finds packed Artemis games via base .pfs', () {
    final root = Directory.systemTemp.createTempSync('art3m1s_probe_');
    addTearDown(() => root.deleteSync(recursive: true));

    // 打包游戏:没有外露 system.ini,只有 PFS 归档。
    final packed = Directory('${root.path}${Platform.pathSeparator}PackedGame')
      ..createSync();
    File(
      '${packed.path}${Platform.pathSeparator}data.pfs',
    ).writeAsBytesSync([1]);
    File(
      '${packed.path}${Platform.pathSeparator}data.pfs.000',
    ).writeAsBytesSync([2]);

    // 解包工程:自带资源 PFS,不应重复登记为独立游戏。
    final unpacked = Directory('${root.path}${Platform.pathSeparator}Unpacked')
      ..createSync();
    File(
      '${unpacked.path}${Platform.pathSeparator}system.ini',
    ).writeAsStringSync('[boot]');
    File(
      '${unpacked.path}${Platform.pathSeparator}res.pfs',
    ).writeAsBytesSync([3]);

    final probe = GameImporter.probeGameFolder(root.path);

    expect(probe.projects, [unpacked.path]);
    expect(probe.pfsArchives, [
      '${packed.path}${Platform.pathSeparator}data.pfs',
    ]);
  });
}
