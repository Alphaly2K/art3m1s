import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

/// Runs the compiler shipped with the Host, and owns its disposable disk cache.
final class ArtemisHlslCompiler {
  ArtemisHlslCompiler._(this._executable, this._cache);

  static const _tool = 'artemis-hlsl-compile';
  static const _libraries = [
    'libvkd3d-utils.1.dylib',
    'libvkd3d-shader.1.dylib',
    'libvkd3d.1.dylib',
  ];
  static const maxSourceBytes = 256 * 1024;
  static const maxArtifactBytes = 16 * 1024 * 1024;

  final String _executable;
  final Directory? _cache;

  static Future<ArtemisHlslCompiler?> bundled() async {
    if (!Platform.isMacOS) return null;
    final directory = File(Platform.resolvedExecutable).parent;
    final executable = File('${directory.path}/$_tool');
    if (!await executable.exists()) return null;
    Directory? cache;
    try {
      final identities = await Future.wait([
        for (final name in [_tool, ..._libraries])
          sha256.bind(File('${directory.path}/$name').openRead()).single,
      ]);
      final identity = sha256.convert([
        for (final digest in identities) ...digest.bytes,
      ]);
      final root = await getApplicationCacheDirectory();
      cache = Directory('${root.path}/artemis-ade2-v1/$identity');
    } on Exception {
      // A cache directory is optional; the bundled tool can still compile.
    }
    return ArtemisHlslCompiler._(executable.path, cache);
  }

  Future<Uint8List?> prepare(Uint8List source) async {
    if (source.isEmpty || source.length > maxSourceBytes) return null;
    final cache = _cache;
    final entry = cache == null
        ? null
        : File('${cache.path}/${sha256.convert(source)}.ade2');
    final hit = entry == null ? null : await _load(entry);
    if (hit != null) return hit;
    final artifact = await _compile(source);
    if (artifact != null && entry != null) {
      await _store(cache!, entry, artifact);
    }
    return artifact;
  }

  Future<Uint8List?> _compile(Uint8List source) async {
    Process? process;
    try {
      process = await Process.start(_executable, ['effect-pair']);
      final child = process;
      final stdout = child.stdout.fold(BytesBuilder(copy: false), (out, data) {
        if (out.length + data.length > maxArtifactBytes) {
          child.kill(ProcessSignal.sigkill);
          throw const FormatException(
            'HLSL compiler output exceeded the limit',
          );
        }
        return out..add(data);
      });
      final results = await Future.wait<Object?>([
        stdout,
        child.stderr.drain<void>(),
        child.exitCode,
        (child.stdin..add(source)).close(),
      ]).timeout(const Duration(seconds: 5));
      final artifact = (results[0] as BytesBuilder).takeBytes();
      if (results[2] == 0 && _isAde2(artifact)) return artifact;
    } on Exception {
      if (process != null) {
        process.kill(ProcessSignal.sigkill);
        await process.exitCode;
      }
    }
    return null;
  }

  static Future<Uint8List?> _load(File entry) async {
    try {
      if (await entry.length() > maxArtifactBytes + 32) return null;
      final stored = await entry.readAsBytes();
      if (stored.length <= 32 || stored.length > maxArtifactBytes + 32) {
        return null;
      }
      final artifact = Uint8List.sublistView(stored, 32);
      if (!_isAde2(artifact)) return null;
      final checksum = sha256.convert(artifact).bytes;
      for (var i = 0; i < checksum.length; i++) {
        if (stored[i] != checksum[i]) return null;
      }
      return artifact;
    } on FileSystemException {
      return null;
    }
  }

  static Future<void> _store(
    Directory cache,
    File entry,
    Uint8List artifact,
  ) async {
    Directory? temporary;
    try {
      await cache.create(recursive: true);
      temporary = await cache.createTemp('.write-');
      final staged = File('${temporary.path}/effect');
      final recorded = Uint8List(32 + artifact.length)
        ..setRange(0, 32, sha256.convert(artifact).bytes)
        ..setRange(32, 32 + artifact.length, artifact);
      await staged.writeAsBytes(recorded);
      await staged.rename(entry.path);
    } on FileSystemException {
      // Keep using the freshly compiled effect if the cache cannot be written.
    } finally {
      try {
        await temporary?.delete(recursive: true);
      } on FileSystemException {
        // The OS can reclaim this directory with the rest of the cache.
      }
    }
  }

  static bool _isAde2(Uint8List artifact) =>
      artifact.length > 20 &&
      ByteData.sublistView(artifact).getUint32(0, Endian.little) == 0x32454441;
}
