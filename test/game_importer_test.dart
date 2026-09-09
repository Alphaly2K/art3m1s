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

  test('managed import delete removes sandbox copy and empty parents', () {
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
    expect(incoming.existsSync(), isTrue);
    expect(
      File('${incoming.path}${Platform.pathSeparator}keep.txt').existsSync(),
      isTrue,
    );
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

  test('managed pfs delete also removes sibling volumes', () {
    final root = Directory.systemTemp.createTempSync('art3m1s_pfs_import_');
    addTearDown(() => root.deleteSync(recursive: true));
    final dir = Directory('${root.path}${Platform.pathSeparator}incoming')
      ..createSync();
    final base = File('${dir.path}${Platform.pathSeparator}game.pfs')
      ..writeAsBytesSync([1]);
    File(
      '${dir.path}${Platform.pathSeparator}game.pfs.000',
    ).writeAsBytesSync([2]);
    File(
      '${dir.path}${Platform.pathSeparator}readme.txt',
    ).writeAsStringSync('keep');

    GameImporter.deleteManagedImport(base.path, [root.path]);

    expect(base.existsSync(), isFalse);
    expect(
      File('${dir.path}${Platform.pathSeparator}game.pfs.000').existsSync(),
      isFalse,
    );
    expect(
      File('${dir.path}${Platform.pathSeparator}readme.txt').existsSync(),
      isTrue,
    );
  });
}
