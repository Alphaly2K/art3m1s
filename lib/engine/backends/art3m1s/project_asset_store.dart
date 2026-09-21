import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'file_provider.dart';
import 'pfs_bridge.dart';
import 'project_charset.dart';

/// Per-runtime media/asset reader that outlives [FileProvider.detachCoreMount].
///
/// Resident multi-game sessions drop the process-global FileProvider index on
/// purpose. Media still needs to read the current project's directory or its
/// standalone PFS patch volumes, including UTF-8 names inside a Shift_JIS game.
class ProjectAssetStore {
  ProjectAssetStore();

  final PfsBridge _pfs = PfsBridge();
  final List<Pointer<Void>> _archives = [];
  String? _directory;
  String? _archivePath;

  void close() {
    for (final archive in _archives) {
      _pfs.close(archive);
    }
    _archives.clear();
    _directory = null;
    _archivePath = null;
  }

  void openDirectory(String root) {
    close();
    _directory = root;
  }

  void openArchives(String archivePath, {String charset = 'UTF-8'}) {
    close();
    _archivePath = archivePath;
    _pfs.initialize();
    final requested = ProjectCharset.normalize(charset);
    final encodings = requested == 'UTF-8'
        ? const <String>['UTF-8']
        : <String>[requested, 'UTF-8'];
    for (final path in FileProvider.listArchiveCandidates(archivePath)) {
      for (final encoding in encodings) {
        final handle = _pfs.openWithEncoding(path, encoding);
        if (handle != nullptr) {
          _archives.add(handle);
        }
      }
    }
  }

  Uint8List? read(String path) {
    final normalized = _normalizeRelativePath(path);
    if (normalized == null) return null;
    if (_directory case final root?) {
      final file = File(
        '$root${Platform.pathSeparator}'
        '${normalized.replaceAll('/', Platform.pathSeparator)}',
      );
      return file.existsSync() ? file.readAsBytesSync() : null;
    }
    if (_archivePath == null) return null;
    final sidecar = _readSidecar(normalized);
    if (sidecar != null) return sidecar;
    for (final archive in _archives.reversed) {
      final size = _pfs.fileSize(archive, normalized);
      if (size <= 0) continue;
      final buffer = malloc.allocate<Uint8>(size);
      try {
        final read = _pfs.read(archive, normalized, 0, buffer, size);
        if (read > 0) {
          return Uint8List.fromList(buffer.asTypedList(read));
        }
      } finally {
        malloc.free(buffer);
      }
    }
    return null;
  }

  Uint8List? _readSidecar(String path) {
    final archivePath = _archivePath;
    if (archivePath == null) return null;
    final file = File(
      '${File(archivePath).parent.path}${Platform.pathSeparator}'
      '${path.replaceAll('/', Platform.pathSeparator)}',
    );
    return file.existsSync() ? file.readAsBytesSync() : null;
  }

  static String? _normalizeRelativePath(String path) {
    final parts = <String>[];
    for (final raw in path.trim().replaceAll('\\', '/').split('/')) {
      final part = raw.trim();
      if (part.isEmpty || part == '.') continue;
      if (part == '..' || part.contains(':')) return null;
      parts.add(part);
    }
    return parts.isEmpty ? null : parts.join('/');
  }
}
