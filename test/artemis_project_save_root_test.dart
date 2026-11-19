import 'dart:io';

import 'package:art3m1s/engine/backends/art3m1s/project_save_root.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('selects one layout for the session when preview saves exist', () {
    final root = Directory.systemTemp.createTempSync('artemis-saves-');
    addTearDown(() => root.deleteSync(recursive: true));
    final separator = Platform.pathSeparator;
    final base = root.resolveSymbolicLinksSync();
    final canonical = '$base${separator}Profiles${separator}Game';
    const hint = 'Profiles/Game';

    expect(resolveArtemisProjectSaveRoot(root, hint).directory.path, canonical);

    final oldIndex = File('$base${separator}saveg.dat')
      ..writeAsStringSync('{}');
    final preview = resolveArtemisProjectSaveRoot(root, hint);
    expect(preview.directory.path, base);
    expect(preview.conflict, isFalse);

    Directory(canonical).createSync(recursive: true);
    final both = resolveArtemisProjectSaveRoot(root, hint);
    expect(both.directory.path, canonical);
    expect(both.conflict, isTrue);
    expect(oldIndex.readAsStringSync(), '{}');
    expect(
      () => resolveArtemisProjectSaveRoot(root, 'Profiles/../outside'),
      throwsFormatException,
    );
  });
}
