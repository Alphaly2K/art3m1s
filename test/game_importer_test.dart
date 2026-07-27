import 'dart:io';

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
}
