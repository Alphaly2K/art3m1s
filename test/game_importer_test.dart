import 'dart:io';

import 'package:art3m1s/services/game_importer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('import progress formats copied files and bytes', () {
    const progress = GameImportProgress(
      filesCopied: 7,
      bytesCopied: 1536,
      currentName: 'data.pfs',
    );
    expect(progress.message, '已复制 7 个文件 · 1.5 KB\ndata.pfs');
  });

  test('import progress can be decoded from native maps', () {
    final progress = GameImportProgress.fromMap({
      'files': 12,
      'bytes': 1048576,
      'current': 'system.ini',
    });
    expect(progress.filesCopied, 12);
    expect(progress.bytesCopied, 1048576);
    expect(progress.currentName, 'system.ini');
    expect(progress.message, contains('1.0 MB'));
  });

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

  test('incomplete SAF batch is discarded and pruned on next launch', () {
    final root = Directory.systemTemp.createTempSync('art3m1s_incomplete_');
    addTearDown(() => root.deleteSync(recursive: true));
    final batch = Directory(
      '${root.path}${Platform.pathSeparator}incoming${Platform.pathSeparator}123',
    )..createSync(recursive: true);
    File(
      '${batch.path}${Platform.pathSeparator}${GameImporter.incompleteImportMarker}',
    ).writeAsStringSync('1');
    final gameDir = Directory(
      '${batch.path}${Platform.pathSeparator}MagicalCharming',
    )..createSync();
    File(
      '${gameDir.path}${Platform.pathSeparator}system.ini',
    ).writeAsStringSync('[boot]');

    expect(
      GameImporter.findIncompleteBatchRoot(gameDir.path, [root.path])?.path,
      batch.path,
    );

    GameImporter.discardAndroidImportForRoots(gameDir.path, [root.path]);
    expect(batch.existsSync(), isFalse);
    expect(gameDir.existsSync(), isFalse);
  });

  test('completed SAF import keeps files after marker is cleared', () {
    final root = Directory.systemTemp.createTempSync('art3m1s_complete_');
    addTearDown(() => root.deleteSync(recursive: true));
    final batch = Directory(
      '${root.path}${Platform.pathSeparator}incoming${Platform.pathSeparator}456',
    )..createSync(recursive: true);
    File(
      '${batch.path}${Platform.pathSeparator}${GameImporter.incompleteImportMarker}',
    ).writeAsStringSync('1');
    final gameDir = Directory('${batch.path}${Platform.pathSeparator}Kept')
      ..createSync();
    File(
      '${gameDir.path}${Platform.pathSeparator}system.ini',
    ).writeAsStringSync('[boot]');

    GameImporter.markAndroidImportCompleteForRoots(gameDir.path, [root.path]);
    expect(
      File(
        '${batch.path}${Platform.pathSeparator}${GameImporter.incompleteImportMarker}',
      ).existsSync(),
      isFalse,
    );
    GameImporter.pruneIncompleteImports([root.path]);
    expect(gameDir.existsSync(), isTrue);
  });

  test('startup prune only deletes flagged incoming batches', () {
    final root = Directory.systemTemp.createTempSync('art3m1s_prune_flag_');
    addTearDown(() => root.deleteSync(recursive: true));
    final stale = Directory(
      '${root.path}${Platform.pathSeparator}incoming${Platform.pathSeparator}stale',
    )..createSync(recursive: true);
    File(
      '${stale.path}${Platform.pathSeparator}${GameImporter.incompleteImportMarker}',
    ).writeAsStringSync('1');
    File(
      '${stale.path}${Platform.pathSeparator}system.ini',
    ).writeAsStringSync('[boot]');
    final kept = Directory(
      '${root.path}${Platform.pathSeparator}incoming${Platform.pathSeparator}kept',
    )..createSync(recursive: true);
    File(
      '${kept.path}${Platform.pathSeparator}system.ini',
    ).writeAsStringSync('[boot]');

    GameImporter.pruneIncompleteImports([root.path]);
    expect(stale.existsSync(), isFalse);
    expect(kept.existsSync(), isTrue);
  });
}
