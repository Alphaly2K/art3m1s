import 'dart:io';

const artemisProjectSavePathCapability = 64;

({Directory directory, bool conflict}) resolveArtemisProjectSaveRoot(
  Directory gameRoot,
  String savePath,
) {
  final parts = savePath.split('/');
  final invalid = RegExp(r'[\x00-\x1f:\\]');
  if (parts.any(
    (part) =>
        part.isEmpty || part == '.' || part == '..' || invalid.hasMatch(part),
  )) {
    throw const FormatException('Invalid Artemis project save path');
  }
  gameRoot.createSync(recursive: true);
  final root = gameRoot.resolveSymbolicLinksSync();
  var canonical = root;
  var exists = true;
  for (final part in parts) {
    canonical = _join(canonical, part);
    final type = FileSystemEntity.typeSync(canonical, followLinks: false);
    if (type == FileSystemEntityType.notFound) {
      exists = false;
    } else if (type != FileSystemEntityType.directory) {
      throw const FormatException('Artemis save path crosses a non-directory');
    }
  }
  // The slot index and its save files must come from the same layout.
  final preview = ['saveg.dat', 'system.dat', 'aread.dat'].any(
    (name) =>
        FileSystemEntity.typeSync(_join(root, name), followLinks: false) ==
        FileSystemEntityType.file,
  );
  return (
    directory: Directory(preview && !exists ? root : canonical),
    conflict: preview && exists,
  );
}

String _join(String parent, String name) {
  final separator = Platform.pathSeparator;
  return parent.endsWith(separator) ? '$parent$name' : '$parent$separator$name';
}
