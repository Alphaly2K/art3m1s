import 'dart:typed_data';

enum ArtemisPlaybackStatus { started, ended, failed, cancelled }

enum ArtemisAudioChannel { bgm, se, voice }

enum ArtemisAudioAction { stop, gain, pan }

sealed class ArtemisMediaCommand {
  const ArtemisMediaCommand();

  static const capability = 4;
  static const domain = 5;
  static const statusKind = 16;
  static const frameKind = 17;

  static ArtemisMediaCommand? decode(
    int domain,
    int kind,
    Map<String, Object?> data,
  ) {
    if (domain != ArtemisMediaCommand.domain) return null;
    return switch ((kind, data['op'])) {
      (1, 'play') => ArtemisAudioPlay._(data),
      (2, 'play') => ArtemisVideoPlay._(data),
      (1, 'stop' || 'gain' || 'pan') => ArtemisAudioUpdate._(data),
      (1, 'stop_all') => ArtemisMediaStopAll._(audio: true, fadeMs: _ms(data)),
      (2, 'stop_all') => const ArtemisMediaStopAll._(audio: false, fadeMs: 0),
      (1, 'restore') => ArtemisAudioRestore._(data),
      _ => null,
    };
  }

  Map<String, Object?> status(String playbackId, ArtemisPlaybackStatus status) {
    final matches = switch (this) {
      ArtemisAudioPlay(:final id) ||
      ArtemisVideoPlay(:final id) => id == playbackId,
      ArtemisAudioRestore(:final plays) => plays.any(
        (play) => play.id == playbackId,
      ),
      _ => false,
    };
    if (!matches) {
      throw ArgumentError('The command did not start this playback');
    }
    return {'playback_id': playbackId, 'status': status.name};
  }

  Map<String, Object?> videoFrame(
    int frame,
    int width,
    int height,
    Uint8List rgba,
  ) {
    if (this case ArtemisVideoPlay(:final id, layer: final String _)) {
      if (frame <= 0 ||
          width <= 0 ||
          height <= 0 ||
          rgba.length > 64 * 1024 * 1024 ||
          width > rgba.length ~/ 4 ||
          height > rgba.length ~/ 4 ||
          width * height * 4 != rgba.length) {
        throw ArgumentError(
          'Expected a numbered frame of tightly packed RGBA8',
        );
      }
      return {
        'playback_id': id,
        'frame_id': '$frame',
        'width': width,
        'height': height,
      };
    }
    throw ArgumentError('Only a layer video accepts frames');
  }
}

final class ArtemisAudioPlay extends ArtemisMediaCommand {
  ArtemisAudioPlay._(Map<String, Object?> data)
    : id = data['playback_id'] as String,
      replaces = data['replaces'] as String?,
      channel = ArtemisAudioChannel.values.byName(data['channel'] as String),
      scriptId = data['id'] as String?,
      key = data['key'] as String,
      loop = data['loop'] as bool,
      loopKey = data['loop_key'] as String?,
      gain = data['gain'] as int?,
      pan = data['pan'] as int?,
      fadeMs = _ms(data),
      bufferMs = data['buffer_ms'] as int?,
      skippable = data['skippable'] as bool,
      crossfade = data['crossfade'] as bool;

  final String id, key;
  final String? replaces, scriptId, loopKey;
  final ArtemisAudioChannel channel;
  final bool loop, skippable, crossfade;
  final int? gain, pan, bufferMs;
  final int fadeMs;
}

final class ArtemisVideoPlay extends ArtemisMediaCommand {
  ArtemisVideoPlay._(Map<String, Object?> data)
    : id = data['playback_id'] as String,
      replaces = data['replaces'] as String?,
      layer = data['layer'] as String?,
      key = data['key'] as String,
      loop = data['loop'] as bool,
      skip = data['skip'] as int,
      delayMarginMs = data['delay_margin_ms'] as int?;

  final String id, key;
  final String? replaces, layer;
  final bool loop;
  final int skip;
  final int? delayMarginMs;
}

final class ArtemisAudioUpdate extends ArtemisMediaCommand {
  ArtemisAudioUpdate._(Map<String, Object?> data)
    : action = ArtemisAudioAction.values.byName(data['op'] as String),
      ids = List<String>.unmodifiable(
        (data['playback_ids'] as List).cast<String>(),
      ),
      timeMs = _ms(data, 'time_ms'),
      value = data['value'] as int?;

  final ArtemisAudioAction action;
  final List<String> ids;
  final int timeMs;
  final int? value;
}

final class ArtemisMediaStopAll extends ArtemisMediaCommand {
  const ArtemisMediaStopAll._({required this.audio, required this.fadeMs});

  final bool audio;
  final int fadeMs;
}

final class ArtemisAudioRestore extends ArtemisMediaCommand {
  ArtemisAudioRestore._(Map<String, Object?> data)
    : plays = List<ArtemisAudioPlay>.unmodifiable(
        (data['plays'] as List).cast<Map<String, Object?>>().map(
          ArtemisAudioPlay._,
        ),
      ),
      stopVideo = data['stop_video'] as bool;

  final List<ArtemisAudioPlay> plays;
  final bool stopVideo;
}

int _ms(Map<String, Object?> data, [String key = 'fade_ms']) =>
    int.parse(data[key] as String);
