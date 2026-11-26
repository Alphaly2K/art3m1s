import 'dart:io';

import '../models/game_engine.dart';
import '../services/logger.dart';
import 'backends/art3m1s_engine_runtime.dart';
import 'backends/art3m1s/v2_caption_probe.dart';
import 'backends/art3m1s/v2_sdk/artemis_flutter_session.dart';
import 'backends/artemis_v2_engine_runtime.dart';
import 'backends/krkr_engine_runtime.dart';
import 'backends/rfvp_engine_runtime.dart';
import 'backends/siglus_engine_runtime.dart';
import 'backends/sena_engine_runtime.dart';
import 'backends/katze_engine_runtime.dart';
import 'engine_runtime.dart';

class EngineRuntimeFactory {
  static const _artemisOverride = bool.hasEnvironment('ARTEMIS_V2');
  static bool _hasProductionArtemis = false;

  static bool get _rfvpV2 => const bool.hasEnvironment('RFVP_V2')
      ? const bool.fromEnvironment('RFVP_V2')
      : Platform.environment['RFVP_V2'] != '0';

  static bool get _artemisV2 =>
      Platform.isMacOS &&
      (_artemisOverride
          ? const bool.fromEnvironment('ARTEMIS_V2')
          : _hasProductionArtemis);

  static Future<void> initialize() async {
    if (Platform.isMacOS && !_artemisOverride) {
      _hasProductionArtemis =
          await ArtemisFlutterSession.hasProductionRuntime();
    }
  }

  const EngineRuntimeFactory._();

  static EngineRuntime create({
    required GameEngineKind engine,
    int renderBackend = 3,
    void Function(EngineDialogRequest request)? onDialogRequested,
    void Function(EngineWindowAction action)? onWindowAction,
    bool? engineCursorControlEnabled,
  }) {
    return switch (engine) {
      GameEngineKind.art3m1s
          when _artemisV2 &&
              (_artemisOverride || renderBackend == 3 || renderBackend == 6) =>
        ArtemisV2EngineRuntime(
          onDialogRequested: onDialogRequested,
          onWindowAction: onWindowAction,
        ),
      GameEngineKind.art3m1s => Art3m1sEngineRuntime(
        onDialogRequested: onDialogRequested,
        engineCursorControlEnabled: engineCursorControlEnabled,
      ),
      GameEngineKind.rfvp => RfvpEngineRuntime(
        engineCursorControlEnabled: engineCursorControlEnabled,
        useReplayFrames: _rfvpV2,
      ),
      GameEngineKind.krkr => KrkrEngineRuntime(
        engineCursorControlEnabled: engineCursorControlEnabled,
      ),
      GameEngineKind.siglus => SiglusEngineRuntime(
        onDialogRequested: onDialogRequested,
      ),
      GameEngineKind.sena => SenaEngineRuntime(),
      GameEngineKind.katze => KatzeEngineRuntime(
        onWindowAction: onWindowAction,
        onDialogRequested: onDialogRequested,
      ),
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
      case GameEngineKind.art3m1s when _artemisV2:
        return probeArtemisV2Caption(
          projectPath: projectPath,
          isArchive: isPfsArchive,
          platform: platform,
        );
      case GameEngineKind.art3m1s:
        return Art3m1sEngineRuntime().probeCaption(
          projectPath: projectPath,
          isPfsArchive: isPfsArchive,
          platform: platform,
        );
      case GameEngineKind.rfvp:
        Log.info('[Engine] RFVP caption probe 尚未接入');
        return null;
      case GameEngineKind.krkr:
        Log.info('[Engine] KRKR caption probe 尚未接入');
        return null;
      case GameEngineKind.siglus:
        Log.info('[Engine] Siglus caption probe 尚未接入');
        return null;
      case GameEngineKind.sena:
      case GameEngineKind.katze:
        return null;
    }
  }
}
