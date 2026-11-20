import 'dart:convert';

import 'package:flutter/services.dart';

import 'artemis_media.dart';

export 'artemis_media.dart';

typedef ArtemisFlutterState = ({
  String epoch,
  int width,
  int height,
  int phase,
  int waitFlags,
  bool exitRequested,
});

final class ArtemisFlutterMessage {
  ArtemisFlutterMessage({
    required int domain,
    required int kind,
    required String epoch,
    required Map<String, Object?> metadata,
    Uint8List? blob,
  }) : _wire = {
         'domain': domain,
         'kind': kind,
         'epoch': epoch,
         'request': '0',
         'metadata': _encode(metadata),
         'blob': ?blob,
       };

  ArtemisFlutterMessage._(this._wire);

  final Map<String, Object?> _wire;
}

final class ArtemisFlutterEvent {
  ArtemisFlutterEvent._(Map<Object?, Object?> wire)
    : _owner = wire['owner'] as String,
      domain = wire['domain'] as int,
      kind = wire['kind'] as int,
      epoch = wire['epoch'] as String,
      sequence = wire['sequence'] as String,
      request = wire['request'] as String,
      metadata =
          jsonDecode(utf8.decode(wire['metadata'] as Uint8List))
              as Map<String, Object?>,
      blob = wire['blob'] as Uint8List;

  final String _owner;
  final int domain;
  final int kind;
  final String epoch;
  final String sequence;
  final String request;
  final Map<String, Object?> metadata;
  final Uint8List blob;

  bool get requiresReply => request != '0';

  late final mediaCommand = ArtemisMediaCommand.decode(domain, kind, metadata);

  ArtemisFlutterMessage playbackStatus(
    String playbackId,
    ArtemisPlaybackStatus status,
  ) => _mediaMessage(
    ArtemisMediaCommand.statusKind,
    _media.status(playbackId, status),
  );

  ArtemisFlutterMessage videoFrame(
    int frame,
    int width,
    int height,
    Uint8List rgba,
  ) => _mediaMessage(
    ArtemisMediaCommand.frameKind,
    _media.videoFrame(frame, width, height, rgba),
    rgba,
  );

  ArtemisMediaCommand get _media =>
      mediaCommand ?? (throw StateError('This event is not a media command'));

  ArtemisFlutterMessage _mediaMessage(
    int kind,
    Map<String, Object?> metadata, [
    Uint8List? blob,
  ]) => ArtemisFlutterMessage._({
    'owner': _owner,
    'domain': ArtemisMediaCommand.domain,
    'kind': kind,
    'epoch': epoch,
    'request': '0',
    'metadata': _encode(metadata),
    'blob': ?blob,
  });

  ArtemisFlutterMessage reply(
    Map<String, Object?> metadata, {
    Uint8List? blob,
  }) {
    if (!requiresReply) throw StateError('This event does not accept a reply');
    return ArtemisFlutterMessage._({
      'owner': _owner,
      'domain': domain,
      'kind': kind,
      'epoch': epoch,
      'request': request,
      'metadata': _encode(metadata),
      'blob': ?blob,
    });
  }
}

/// Dart receives owned events. The macOS Runner owns the Core and GPU threads.
/// The player schedules steps and services requests through its own resource,
/// save, media, and UI services.
final class ArtemisFlutterSession {
  static const _channel = MethodChannel('moe.alphaly.art3m1s/artemis_v2');
  ArtemisFlutterSession._(this._id, this.usesDxvk);

  final String _id;
  final bool usesDxvk;
  bool _closed = false;

  static Future<
    ({
      ArtemisFlutterSession session,
      ArtemisFlutterState state,
      Set<int> preparedHlsl,
    })
  >
  open({
    required Uint8List ini,
    required String platform,
    required int hostCaps,
    String? reportedOS,
    bool angle = false,
    bool mixedShaders = false,
    bool screenshots = false,
    List<({Uint8List source, Uint8List artifact})> hlslEffects = const [],
    List<Uint8List> glslSources = const [],
    bool compileHlsl = false,
    bool hlslOnDemand = false,
  }) async {
    final result = (await _channel.invokeMapMethod<Object?, Object?>('open', {
      'ini': ini,
      'platform': platform,
      'hostCaps': hostCaps,
      'reportedOS': ?reportedOS,
      if (angle) 'renderer': 'angle',
      if (mixedShaders) 'mixedShaders': true,
      if ((angle || mixedShaders) && glslSources.isNotEmpty)
        'glslSources': glslSources,
      'screenshots': screenshots,
      if ((!angle || mixedShaders) && compileHlsl) 'compileHlsl': true,
      if ((!angle || mixedShaders) && hlslOnDemand) 'hlslOnDemand': true,
      if ((!angle || mixedShaders) && hlslEffects.isNotEmpty)
        'hlslEffects': [
          for (final effect in hlslEffects)
            {'source': effect.source, 'artifact': effect.artifact},
        ],
    }))!;
    final session = ArtemisFlutterSession._(
      result['session'] as String,
      result['dxvk'] == true,
    );
    try {
      return (
        session: session,
        state: _state(result),
        preparedHlsl:
            (result['preparedHlsl'] as List?)?.cast<int>().toSet() ?? const {},
      );
    } catch (_) {
      await session.close();
      rethrow;
    }
  }

  Future<T?> _call<T>(String name, [Map<String, Object?> args = const {}]) {
    if (_closed) throw StateError('Artemis session is closed');
    return _channel.invokeMethod<T>(name, {'session': _id, ...args});
  }

  Future<int> setSurface(int width, int height) async =>
      (await _call<int>('surface', {'width': width, 'height': height}))!;

  Future<void> detachSurface() => _call<void>('detach');

  Future<void> prepareHlsl(Uint8List source, Uint8List artifact) =>
      _call<void>('prepareHlsl', {'source': source, 'artifact': artifact});

  /// Returns the ID of a freshly presented frame, or null if none was presented.
  Future<String?> present() => _call<String>('present');

  Future<({int width, int height, Uint8List rgba})> capture(
    String frame,
  ) async {
    final result = (await _call<Map<Object?, Object?>>('capture', {
      'frame': frame,
    }))!;
    return (
      width: result['width'] as int,
      height: result['height'] as int,
      rgba: result['rgba'] as Uint8List,
    );
  }

  Future<({ArtemisFlutterState state, bool backpressured, int stepFlags})>
  step({
    required int frame,
    required int monotonicNS,
    required DateTime time,
    bool backgroundAutosave = false,
  }) async {
    final result = (await _call<Map<Object?, Object?>>('step', {
      'frame': frame,
      'monotonicNS': monotonicNS,
      'unixMS': time.millisecondsSinceEpoch,
      'utcOffsetMinutes': time.timeZoneOffset.inMinutes,
      if (backgroundAutosave) 'backgroundAutosave': true,
    }))!;
    return (
      state: _state(result),
      backpressured: result['backpressured'] as bool,
      stepFlags: result['stepFlags'] as int,
    );
  }

  Future<List<ArtemisFlutterEvent>> pollEvents() async =>
      (await _call<List<Object?>>('poll'))!
          .cast<Map<Object?, Object?>>()
          .map(ArtemisFlutterEvent._)
          .toList(growable: false);

  Future<void> openVideo({
    required String epoch,
    required ArtemisVideoPlay play,
    required String path,
    double volume = 1,
  }) => _call<void>('videoOpen', {
    'epoch': epoch,
    'playback': play.id,
    'path': path,
    'fullscreen': play.layer == null,
    'loop': play.loop,
    'delayMarginMs': play.delayMarginMs,
    'volume': volume,
  });

  Future<void> closeVideo(String playback) =>
      _call<void>('videoClose', {'playback': playback});

  Future<void> suspendVideos(bool suspended) =>
      _call<void>('videoSuspend', {'suspended': suspended});

  Future<void> setVideoVolume(double volume) =>
      _call<void>('videoVolume', {'volume': volume});

  Future<
    List<
      ({
        String id,
        ArtemisPlaybackStatus status,
        int? texture,
        int? width,
        int? height,
      })
    >
  >
  pollVideos() async => (await _call<List<Object?>>('videoPoll'))!
      .cast<Map<Object?, Object?>>()
      .map(
        (wire) => (
          id: wire['playback'] as String,
          status: ArtemisPlaybackStatus.values.byName(wire['status'] as String),
          texture: wire['texture'] as int?,
          width: wire['width'] as int?,
          height: wire['height'] as int?,
        ),
      )
      .toList(growable: false);

  /// A false result means the batch was not accepted and can be retried.
  Future<bool> submit(List<ArtemisFlutterMessage> batch) async {
    for (final message in batch) {
      final owner = message._wire['owner'];
      if (owner != null && owner != _id) {
        throw ArgumentError('The message belongs to another Artemis session');
      }
    }
    return (await _call<bool>('submit', {
      'batch': batch.map((message) => message._wire).toList(growable: false),
    }))!;
  }

  Future<void> close() async {
    if (_closed) return;
    final pending = _call<void>('close');
    _closed = true;
    await pending;
  }
}

ArtemisFlutterState _state(Map<Object?, Object?> wire) => (
  epoch: wire['epoch'] as String,
  width: wire['width'] as int,
  height: wire['height'] as int,
  phase: wire['phase'] as int,
  waitFlags: wire['waitFlags'] as int,
  exitRequested: wire['exitRequested'] as bool,
);

Uint8List _encode(Map<String, Object?> metadata) =>
    Uint8List.fromList(utf8.encode(jsonEncode(metadata)));
