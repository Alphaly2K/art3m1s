import 'dart:typed_data';

import '../models/game_engine.dart';
import 'backends/art3m1s_engine_runtime.dart';

/// Engine-neutral access to archive-backed projects.
///
/// Import and metadata code uses this facade instead of an engine-specific
/// archive reader.
class EngineArchive {
  const EngineArchive._();

  static Future<List<String>> listEntries({
    required GameEngineKind engine,
    required String archivePath,
  }) {
    return switch (engine) {
      GameEngineKind.art3m1s => Art3m1sEngineRuntime.listArchiveEntries(
        archivePath,
      ),
      GameEngineKind.rfvp => Future<List<String>>.value(const <String>[]),
    };
  }

  static Future<Uint8List?> readFile({
    required GameEngineKind engine,
    required String archivePath,
    required String relativePath,
  }) {
    return switch (engine) {
      GameEngineKind.art3m1s => Art3m1sEngineRuntime.readArchiveFile(
        archivePath,
        relativePath,
      ),
      GameEngineKind.rfvp => Future<Uint8List?>.value(),
    };
  }
}
