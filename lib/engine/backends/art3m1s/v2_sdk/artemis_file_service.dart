import 'dart:io';
import 'dart:typed_data';

typedef ArtemisFileReply = ({Map<String, Object?> metadata, Uint8List? blob});

final class ArtemisFileEvent {
  const ArtemisFileEvent(
    this.domain,
    this.kind,
    this.epoch,
    this.requiresReply,
    this.metadata,
    this.blob,
  );

  final int domain;
  final int kind;
  final int epoch;
  final bool requiresReply;
  final Map<String, Object?> metadata;
  final Uint8List blob;

  ArtemisFileReply reply(Map<String, Object?> metadata, {Uint8List? blob}) =>
      (metadata: metadata, blob: blob);
}

// v2 file service domains and operations.
const _runtime = 1, _io = 3;
const _sessionChanged = 1, _runtimeClosed = 4;
const _statKind = 1,
    _readKind = 2,
    _writeKind = 4,
    _deleteKind = 5,
    _abortKind = 6;

/// Resolve a normalized asset key and its optional modification time in the
/// Host's existing resource layers. A callback may also accept a named
/// `int? maxBytes` parameter and return null if the asset exceeds that limit.
typedef ArtemisReadAsset =
    ({Uint8List bytes, DateTime? modified})? Function(String key);

typedef _BoundedAssetReader =
    ({Uint8List bytes, DateTime? modified})? Function(
      String key, {
      int? maxBytes,
    });

/// File service for one Artemis session. Pass in its events in poll order,
/// including session changes. The caller submits replies and retries them
/// unchanged under backpressure. Disk calls here are synchronous; use a
/// managed save root whose directories are controlled by the Host.
final class ArtemisFileService {
  ArtemisFileService({required Directory saveRoot, required this.readAsset}) {
    saveRoot.createSync(recursive: true);
    _root = saveRoot.resolveSymbolicLinksSync();
  }

  ArtemisFileService.assetsOnly({required this.readAsset}) : _root = null;

  static const capabilities = 1 | 32;
  static const _maxFileSize = 64 * 1024 * 1024;
  static final _maxWireSize = (BigInt.one << 64) - BigInt.one;
  static const _maxChunkSize = 1024 * 1024;
  static const _stagingPrefix = '.artemis-write-';

  final ArtemisReadAsset readAsset;
  late final String? _root;
  int _epoch = 0;
  int _revision = 0;
  bool _accepting = false;
  bool _closed = false;
  ({String namespace, String key, String revision, Uint8List bytes})? _read;
  _PendingWrite? _write;

  ArtemisFileReply? handle(ArtemisFileEvent event) {
    if (_closed) throw StateError('Artemis file service is closed');
    if (event.domain == _runtime) {
      if (event.kind == _sessionChanged && event.epoch > _epoch) {
        _clear();
        _epoch = event.epoch;
        _accepting = true;
      } else if (event.kind == _runtimeClosed && event.epoch == _epoch) {
        _clear();
        _accepting = false;
      }
      return null;
    }
    if (event.domain != _io || event.epoch != _epoch || !_accepting) {
      return null;
    }
    final metadata = event.metadata;
    if (event.kind == _abortKind && !event.requiresReply) {
      if (metadata['transaction_id'] == _write?.id) _discardWrite();
      return null;
    }
    if (!event.requiresReply) return null;
    try {
      final namespace = metadata['namespace'];
      final key = metadata['key'];
      if (key is! String || (namespace != 'asset' && namespace != 'save')) {
        throw const _IoFailure('denied');
      }
      if (namespace == 'save' && _root == null) {
        return event.reply(
          event.kind == _statKind
              ? {'status': 'ok', 'found': false}
              : {'status': 'denied'},
        );
      }
      switch (event.kind) {
        case _statKind:
          return _stat(event, namespace as String, key);
        case _readKind:
          return _readRange(event, namespace as String, key);
        case _writeKind:
          if (namespace != 'save') throw const _IoFailure('denied');
          return _writeAtomic(event, key);
        case _deleteKind:
          if (namespace != 'save') throw const _IoFailure('denied');
          final target = _saveFile(key);
          if (target == null || !target.existsSync()) {
            throw const _IoFailure('not_found');
          }
          target.deleteSync();
          _read = null;
          return event.reply({'status': 'ok'});
        default:
          return event.reply({'status': 'unsupported'});
      }
    } on _IoFailure catch (error) {
      if (event.kind == _writeKind) _discardWrite();
      return event.reply({'status': error.status});
    } on Exception {
      if (event.kind == _writeKind) _discardWrite();
      return event.reply({'status': 'io_error'});
    }
  }

  /// Call after the last event, even when the runtime did not shut down cleanly.
  void close() {
    _clear();
    _closed = true;
  }

  /// Commit a Host-produced save artifact, such as a screenshot.
  String replaceSave(int epoch, String key, Uint8List bytes) {
    if (_closed || !_accepting || _epoch != epoch) return 'cancelled';
    if (bytes.length > _maxFileSize) return 'denied';
    try {
      _replaceSave(key, bytes);
      return 'ok';
    } on _IoFailure catch (error) {
      return error.status;
    } on Exception {
      return 'io_error';
    }
  }

  ArtemisFileReply _stat(ArtemisFileEvent event, String namespace, String key) {
    _read = null;
    Uint8List? bytes;
    DateTime? modified;
    if (namespace == 'asset') {
      final budget = event.metadata['max_read_bytes'];
      int? maxBytes;
      if (budget != null) {
        if (budget is! String ||
            budget.length > 20 ||
            !_unsignedDecimal.hasMatch(budget)) {
          throw const _IoFailure('io_error');
        }
        final limit = BigInt.parse(budget);
        if (limit > _maxWireSize) throw const _IoFailure('io_error');
        maxBytes = limit > BigInt.from(_maxFileSize)
            ? _maxFileSize
            : limit.toInt();
      }
      final reader = readAsset;
      final asset = reader is _BoundedAssetReader
          ? reader(key, maxBytes: maxBytes)
          : reader(key);
      if (asset != null) {
        if (asset.bytes.length > (maxBytes ?? _maxFileSize)) {
          throw const _IoFailure('denied');
        }
        bytes = Uint8List.fromList(asset.bytes);
        modified = asset.modified;
      }
    } else {
      final file = _saveFile(key);
      final stat = file?.statSync();
      if (stat?.type == FileSystemEntityType.file) {
        final input = file!.openSync();
        try {
          final length = input.lengthSync();
          if (length > _maxFileSize) throw const _IoFailure('denied');
          bytes = input.readSync(length);
          if (bytes.length != length) throw const _IoFailure('io_error');
        } finally {
          input.closeSync();
        }
        modified = stat!.modified;
      }
    }
    if (bytes == null) return event.reply({'status': 'ok', 'found': false});
    final revision = '${++_revision}';
    if (bytes.isNotEmpty) {
      _read = (
        namespace: namespace,
        key: key,
        revision: revision,
        bytes: bytes,
      );
    }
    return event.reply({
      'status': 'ok',
      'found': true,
      'revision': revision,
      'size': '${bytes.length}',
      if (modified != null)
        'modified_utc_ms': '${modified.millisecondsSinceEpoch}',
    });
  }

  ArtemisFileReply _readRange(
    ArtemisFileEvent event,
    String namespace,
    String key,
  ) {
    final snapshot = _read;
    final metadata = event.metadata;
    if (snapshot == null ||
        namespace != snapshot.namespace ||
        key != snapshot.key ||
        metadata['revision'] != snapshot.revision) {
      throw const _IoFailure('io_error');
    }
    final offset = _decimal(metadata['offset'], snapshot.bytes.length - 1);
    final length = _decimal(metadata['length'], _maxChunkSize);
    if (length == 0) throw const _IoFailure('io_error');
    final end = (offset + length).clamp(offset, snapshot.bytes.length);
    final eof = end == snapshot.bytes.length;
    if (eof) _read = null;
    return event.reply({
      'status': 'ok',
      'revision': snapshot.revision,
      'eof': eof,
    }, blob: Uint8List.sublistView(snapshot.bytes, offset, end));
  }

  ArtemisFileReply _writeAtomic(ArtemisFileEvent event, String key) {
    final metadata = event.metadata;
    final id = metadata['transaction_id'];
    if (event.blob.length > _maxChunkSize) throw const _IoFailure('denied');
    if (id == null) {
      _replaceSave(key, event.blob);
      return event.reply({'status': 'ok'});
    }
    if (id is! String || !_unsignedDecimal.hasMatch(id) || id == '0') {
      throw const _IoFailure('io_error');
    }
    final size = _decimal(metadata['size'], _maxFileSize);
    final offset = _decimal(metadata['offset'], size);
    final end = offset + event.blob.length;
    if (event.blob.isEmpty || end > size) throw const _IoFailure('io_error');
    final pending =
        _write ??
        (offset == 0
            ? _startWrite(key, id, size)
            : throw const _IoFailure('io_error'));
    if (pending.id != id ||
        pending.key != key ||
        pending.size != size ||
        pending.offset != offset) {
      throw const _IoFailure('io_error');
    }
    final last = end == size;
    final output = pending.file.openSync(mode: FileMode.append);
    try {
      if (output.lengthSync() != offset) throw const _IoFailure('io_error');
      output.writeFromSync(event.blob);
      if (last) output.flushSync();
    } finally {
      output.closeSync();
    }
    pending.offset = end;
    if (last) _commitWrite(pending);
    return event.reply({
      'status': last ? 'ok' : 'staged',
      'transaction_id': id,
      'next_offset': '$end',
    });
  }

  void _replaceSave(String key, Uint8List bytes) {
    if (_write != null) throw const _IoFailure('io_error');
    final pending = _startWrite(key, '', bytes.length);
    try {
      pending.file.writeAsBytesSync(bytes, flush: true);
      _commitWrite(pending);
    } finally {
      _discardWrite();
    }
  }

  _PendingWrite _startWrite(String key, String id, int size) {
    final destination = _saveFile(key, createParents: true)!;
    final directory = destination.parent.createTempSync(_stagingPrefix);
    return _write = _PendingWrite(
      id,
      key,
      size,
      directory,
      File(_join(directory.path, 'data')),
    );
  }

  void _commitWrite(_PendingWrite write) {
    final destination = _saveFile(write.key)!;
    write.file.renameSync(destination.path);
    _read = null;
    _discardWrite();
  }

  void _clear() {
    _read = null;
    _discardWrite();
  }

  void _discardWrite() {
    final write = _write;
    _write = null;
    try {
      write?.directory.deleteSync(recursive: true);
    } on FileSystemException {
      // Cleanup failure must not change the result of a completed rename.
    }
  }

  File? _saveFile(String key, {bool createParents = false}) {
    final parts = key.split('/');
    for (final part in parts) {
      if (part.isEmpty ||
          part.endsWith('.') ||
          part.endsWith(' ') ||
          part.startsWith(_stagingPrefix) ||
          _invalidComponent.hasMatch(part) ||
          _device.hasMatch(part)) {
        throw const _IoFailure('denied');
      }
    }
    var path = _root!;
    for (var i = 0; i < parts.length; i++) {
      path = _saveComponent(path, parts[i]);
      final type = FileSystemEntity.typeSync(path, followLinks: false);
      if (i == parts.length - 1) {
        if (type != FileSystemEntityType.file &&
            type != FileSystemEntityType.notFound) {
          throw const _IoFailure('denied');
        }
        return File(path);
      }
      if (type == FileSystemEntityType.notFound) {
        if (!createParents) return null;
        Directory(path).createSync();
      } else if (type != FileSystemEntityType.directory) {
        throw const _IoFailure('denied');
      }
    }
    throw const _IoFailure('denied');
  }

  String _saveComponent(String parent, String name) {
    final exact = _join(parent, name);
    if (FileSystemEntity.typeSync(exact, followLinks: false) !=
        FileSystemEntityType.notFound) {
      return exact;
    }
    String? match;
    for (final entry in Directory(parent).listSync(followLinks: false)) {
      final relative = entry.uri.pathSegments.lastWhere(
        (part) => part.isNotEmpty,
      );
      if (relative.replaceAllMapped(_uppercase, (c) => c[0]!.toLowerCase()) !=
          name) {
        continue;
      }
      if (match != null) throw const _IoFailure('denied');
      match = entry.path;
    }
    return match ?? exact;
  }
}

final class _PendingWrite {
  _PendingWrite(this.id, this.key, this.size, this.directory, this.file);

  final String id;
  final String key;
  final int size;
  final Directory directory;
  final File file;
  int offset = 0;
}

final class _IoFailure implements Exception {
  const _IoFailure(this.status);
  final String status;
}

final _unsignedDecimal = RegExp(r'^(0|[1-9][0-9]*)$');
final _uppercase = RegExp(r'[A-Z]');
final _invalidComponent = RegExp(r'[\x00-\x1f<>:"|?*\\]');
final _device = RegExp(
  r'^(con|prn|aux|nul|com[0-9\u00b9\u00b2\u00b3]|lpt[0-9\u00b9\u00b2\u00b3])(\.|$)',
  caseSensitive: false,
);

int _decimal(Object? value, int max) {
  if (value is String && _unsignedDecimal.hasMatch(value)) {
    final parsed = int.tryParse(value);
    if (parsed != null && parsed >= 0 && parsed <= max && '$parsed' == value) {
      return parsed;
    }
  }
  throw const _IoFailure('io_error');
}

String _join(String dir, String element) {
  final separator = Platform.pathSeparator;
  return dir.endsWith(separator) ? '$dir$element' : '$dir$separator$element';
}
