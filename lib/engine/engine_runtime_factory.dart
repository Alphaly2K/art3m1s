import '../models/game_engine.dart';
import '../services/core_bridge.dart'
    hide AvoidOverlay, EngineDialogRequest, EngineVideoPlayback;
import '../services/logger.dart';
import 'backends/art3m1s_engine_runtime.dart';
import 'engine_runtime.dart';

class EngineRuntimeFactory {
  const EngineRuntimeFactory._();

  static EngineRuntime create({
    required GameEngineKind engine,
    void Function(EngineDialogRequest request)? onDialogRequested,
    bool? engineCursorControlEnabled,
  }) {
    return switch (engine) {
      GameEngineKind.art3m1s => Art3m1sEngineRuntime(
        onDialogRequested: onDialogRequested,
        engineCursorControlEnabled: engineCursorControlEnabled,
      ),
      GameEngineKind.rfvp => UnsupportedEngineRuntime(engine),
    };
  }

  /// Engine-specific metadata probe used while importing a project.
  static Future<String?> probeCaption({
    required GameEngineKind engine,
    required String projectPath,
    required bool isPfsArchive,
    String platform = 'WINDOWS',
  }) async {
    switch (engine) {
      case GameEngineKind.art3m1s:
        return CoreBridge().probeCaption(
          projectPath: projectPath,
          isPfsArchive: isPfsArchive,
          platform: platform,
        );
      case GameEngineKind.rfvp:
        Log.info('[Engine] RFVP caption probe 尚未接入');
        return null;
    }
  }
}
