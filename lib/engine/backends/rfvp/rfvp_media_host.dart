import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:audio_decode/audio_decode.dart';
import 'package:audioplayers/audioplayers.dart' as audio;
import 'package:flutter/widgets.dart';

import '../../../services/logger.dart';
import '../../engine_runtime.dart';

/// RFVP host-side playback.
///
/// Encoded audio commands are decoded on the Host. Ogg Vorbis and MP3 are
/// converted to PCM WAV in an isolate; formats already supported by the
/// platform player continue through the encoded file path.
class RfvpMediaHost implements EngineMediaHost {
  final Map<int, Uint8List> _encoded = {};
  final Map<int, File> _encodedFiles = {};
  final Map<int, _PcmStream> _pcm = {};
  final Map<int, _RfvpAudioHandle> _handles = {};
  final Map<String, double> _channelVolumes = {
    'master': 1,
    'bgm': 1,
    'se': 1,
    'voice': 1,
  };
  final Directory _cacheDir = Directory.systemTemp.createTempSync(
    'art3m1s_rfvp_media_',
  );
  Future<void> _commandTail = Future<void>.value();
  int _pcmSequence = 0;
  bool _disposed = false;

  @override
  final ValueNotifier<EngineVideoPlayback?> videoPlayback =
      ValueNotifier<EngineVideoPlayback?>(null);

  @override
  final ValueNotifier<bool> fullscreenVideoBlocking = ValueNotifier<bool>(
    false,
  );

  @override
  bool get isFullscreenVideoBlocking => false;

  @override
  void handleEngineAudioCommand(EngineAudioCommand command) {
    if (_disposed) return;
    _commandTail = _commandTail.then((_) => _handleSafely(command));
  }

  Future<void> _handleSafely(EngineAudioCommand command) async {
    if (_disposed) return;
    try {
      await _handle(command);
    } catch (error, stackTrace) {
      Log.error(
        '[RfvpMediaHost] command ${command.kind.name} failed for '
        'stream ${command.streamId}: $error\n$stackTrace',
      );
    }
  }

  Future<void> _handle(EngineAudioCommand command) async {
    final streamId = command.streamId;
    final channel = _channelFor(streamId);
    switch (command.kind) {
      case EngineAudioCommandKind.loadEncoded:
        _discardPcm(streamId);
        _deleteEncodedFile(streamId);
        _encoded[streamId] = command.payload;
        final old = _handles.remove(streamId);
        if (old != null) await old.dispose();
      case EngineAudioCommandKind.createStream:
        if (command.sampleRate <= 0 || command.channels <= 0) {
          Log.warn('[RfvpMediaHost] PCM stream $streamId has invalid format');
          return;
        }
        _encoded.remove(streamId);
        _deleteEncodedFile(streamId);
        final old = _handles.remove(streamId);
        if (old != null) unawaited(old.dispose());
        _discardPcm(streamId);
        _pcm[streamId] = _PcmStream(
          file: File(
            '${_cacheDir.path}${Platform.pathSeparator}'
            'rfvp_pcm_${streamId}_${_pcmSequence++}.wav',
          ),
          sampleRate: command.sampleRate,
          channels: command.channels,
        );
      case EngineAudioCommandKind.submitI16:
        _pcm[streamId]?.append(command.payload);
      case EngineAudioCommandKind.submitF32:
        Log.warn('[RfvpMediaHost] F32 PCM stream $streamId is unsupported');
      case EngineAudioCommandKind.play:
        final pcm = _pcm[streamId];
        final encoded = _encoded[streamId];
        final file = pcm != null
            ? await pcm.finalize()
            : encoded == null
            ? null
            : await _materializePlayable(streamId, encoded);
        if (file == null) {
          Log.warn('[RfvpMediaHost] stream $streamId has no playable data');
          return;
        }
        final old = _handles.remove(streamId);
        if (old != null) await old.dispose();
        final handle = await _RfvpAudioHandle.create(
          file: file,
          channel: channel,
          loop: command.repeat,
          gain: command.volume,
          pan: command.pan,
        );
        _handles[streamId] = handle;
        await handle.setEffectiveVolume(
          command.fadeMs > 0 ? 0 : _effectiveVolume(channel, handle.gain),
        );
        await handle.play();
        if (command.fadeMs > 0) {
          await handle.fadeTo(
            _effectiveVolume(channel, handle.gain),
            command.fadeMs,
          );
        }
      case EngineAudioCommandKind.stop:
        final handle = _handles.remove(streamId);
        if (handle == null) return;
        if (command.fadeMs > 0) await handle.fadeTo(0, command.fadeMs);
        await handle.dispose();
      case EngineAudioCommandKind.pause:
        await _handles[streamId]?.player.pause();
      case EngineAudioCommandKind.resume:
        await _handles[streamId]?.player.resume();
      case EngineAudioCommandKind.setParams:
        final handle = _handles[streamId];
        if (handle == null) return;
        handle.gain = command.volume.clamp(0, 1);
        await handle.setEffectiveVolume(_effectiveVolume(channel, handle.gain));
        await handle.setPan(command.pan);
      case EngineAudioCommandKind.destroyStream:
        _encoded.remove(streamId);
        _deleteEncodedFile(streamId);
        _discardPcm(streamId);
        final handle = _handles.remove(streamId);
        if (handle != null) await handle.dispose();
      case EngineAudioCommandKind.masterVolume:
        _channelVolumes['master'] = command.volume.clamp(0, 1);
        for (final handle in _handles.values.toList()) {
          await handle.setEffectiveVolume(
            _effectiveVolume(handle.channel, handle.gain),
          );
        }
    }
  }

  String _channelFor(int streamId) => streamId < 0x1000 ? 'bgm' : 'se';

  double _effectiveVolume(String channel, double gain) {
    final master = _channelVolumes['master'] ?? 1;
    final channelVolume = _channelVolumes[channel] ?? 1;
    return (master * channelVolume * gain).clamp(0, 1);
  }

  void _discardPcm(int streamId) {
    final stream = _pcm.remove(streamId);
    if (stream != null) unawaited(stream.discard());
  }

  void _deleteEncodedFile(int streamId) {
    final file = _encodedFiles.remove(streamId);
    if (file == null) return;
    try {
      if (file.existsSync()) file.deleteSync();
    } catch (_) {}
  }

  File _materializeEncoded(int streamId, Uint8List bytes) {
    return _writeEncodedFile(
      streamId,
      bytes,
      extension: _extension(bytes),
      prefix: 'rfvp_encoded',
    );
  }

  Future<File> _materializePlayable(int streamId, Uint8List bytes) async {
    final existing = _encodedFiles[streamId];
    if (existing != null && existing.existsSync()) return existing;
    final format = detectFormat(bytes);
    if (format == AudioFormat.ogg || format == AudioFormat.mp3) {
      final stopwatch = Stopwatch()..start();
      final output = File(
        '${_cacheDir.path}${Platform.pathSeparator}'
        'rfvp_decoded_${streamId}_${bytes.length}.wav',
      );
      try {
        await decodeRfvpAudioToWavFile(bytes, output.path);
      } catch (_) {
        try {
          if (output.existsSync()) output.deleteSync();
        } catch (_) {}
        rethrow;
      }
      stopwatch.stop();
      Log.debug(
        '[RfvpMediaHost] decoded stream $streamId '
        '(${format.name}, ${bytes.length} bytes) in '
        '${stopwatch.elapsedMilliseconds} ms',
      );
      _deleteEncodedFile(streamId);
      _encodedFiles[streamId] = output;
      _encoded.remove(streamId);
      return output;
    }
    return _materializeEncoded(streamId, bytes);
  }

  File _writeEncodedFile(
    int streamId,
    Uint8List bytes, {
    required String extension,
    required String prefix,
  }) {
    _deleteEncodedFile(streamId);
    final file = File(
      '${_cacheDir.path}${Platform.pathSeparator}'
      '${prefix}_${streamId}_${bytes.length}.$extension',
    );
    file.writeAsBytesSync(bytes, flush: true);
    _encodedFiles[streamId] = file;
    return file;
  }

  String _extension(Uint8List bytes) {
    if (_startsWith(bytes, const [82, 73, 70, 70])) return 'wav';
    if (_startsWith(bytes, const [79, 103, 103, 83])) return 'ogg';
    if (_startsWith(bytes, const [102, 76, 97, 67])) return 'flac';
    if (_startsWith(bytes, const [73, 68, 51])) return 'mp3';
    if (bytes.length >= 2 && bytes[0] == 0xff && (bytes[1] & 0xe0) == 0xe0) {
      return 'mp3';
    }
    return 'bin';
  }

  bool _startsWith(Uint8List bytes, List<int> prefix) {
    if (bytes.length < prefix.length) return false;
    for (var index = 0; index < prefix.length; index++) {
      if (bytes[index] != prefix[index]) return false;
    }
    return true;
  }

  @override
  Future<void> skipVideo() async {
    videoPlayback.value = null;
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _commandTail;
    final handles = _handles.values.toList();
    _handles.clear();
    for (final handle in handles) {
      await handle.dispose();
    }
    final streams = _pcm.values.toList();
    _pcm.clear();
    for (final stream in streams) {
      await stream.discard();
    }
    for (final file in _encodedFiles.values) {
      try {
        if (file.existsSync()) file.deleteSync();
      } catch (_) {}
    }
    _encodedFiles.clear();
    _encoded.clear();
    videoPlayback.dispose();
    fullscreenVideoBlocking.dispose();
    try {
      if (_cacheDir.existsSync()) _cacheDir.deleteSync(recursive: true);
    } catch (_) {}
  }
}

/// Decodes an encoded RFVP audio payload into a canonical 16-bit PCM WAV file.
///
/// Decoding and writing run in a background isolate. The PCM samples are
/// streamed to disk in chunks instead of building a second full-size WAV
/// buffer in memory.
@visibleForTesting
Future<void> decodeRfvpAudioToWavFile(Uint8List bytes, String outputPath) {
  return Isolate.run(() {
    final decoded = decodeAudio(bytes);
    final samples = decoded.samples;
    final sampleBytes = samples.buffer.asUint8List(
      samples.offsetInBytes,
      samples.lengthInBytes,
    );
    final output = File(outputPath).openSync(mode: FileMode.write);
    try {
      output.writeFromSync(
        _pcmWavHeader(
          dataBytes: sampleBytes.length,
          sampleRate: decoded.sampleRate,
          channels: decoded.channels,
        ),
      );
      const chunkBytes = 1024 * 1024;
      for (var offset = 0; offset < sampleBytes.length; offset += chunkBytes) {
        final end = math.min(offset + chunkBytes, sampleBytes.length);
        output.writeFromSync(Uint8List.sublistView(sampleBytes, offset, end));
      }
    } finally {
      output.closeSync();
    }
  });
}

class _PcmStream {
  _PcmStream({
    required this.file,
    required this.sampleRate,
    required this.channels,
  }) : _sink = file.openWrite();

  final File file;
  final int sampleRate;
  final int channels;
  final IOSink _sink;
  int _dataBytes = 0;
  bool _closed = false;

  void append(Uint8List bytes) {
    if (_closed || bytes.isEmpty) return;
    _sink.add(bytes);
    _dataBytes += bytes.length;
  }

  Future<File?> finalize() async {
    if (_closed) return file.existsSync() ? file : null;
    _closed = true;
    await _sink.flush();
    await _sink.close();
    if (_dataBytes == 0) {
      try {
        if (file.existsSync()) file.deleteSync();
      } catch (_) {}
      return null;
    }
    final header = _pcmWavHeader(
      dataBytes: _dataBytes,
      sampleRate: sampleRate,
      channels: channels,
    );
    final output = file.openSync(mode: FileMode.writeOnly);
    try {
      output.writeFromSync(header);
    } finally {
      output.closeSync();
    }
    return file;
  }

  Future<void> discard() async {
    if (!_closed) {
      _closed = true;
      try {
        await _sink.close();
      } catch (_) {}
    }
    try {
      if (file.existsSync()) file.deleteSync();
    } catch (_) {}
  }
}

Uint8List _pcmWavHeader({
  required int dataBytes,
  required int sampleRate,
  required int channels,
}) {
  final header = ByteData(44);
  void ascii(int offset, String value) {
    for (var index = 0; index < value.length; index++) {
      header.setUint8(offset + index, value.codeUnitAt(index));
    }
  }

  final byteRate = sampleRate * channels * 2;
  final blockAlign = channels * 2;
  ascii(0, 'RIFF');
  header.setUint32(4, 36 + dataBytes, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  header.setUint32(16, 16, Endian.little);
  header.setUint16(20, 1, Endian.little);
  header.setUint16(22, channels, Endian.little);
  header.setUint32(24, sampleRate, Endian.little);
  header.setUint32(28, byteRate, Endian.little);
  header.setUint16(32, blockAlign, Endian.little);
  header.setUint16(34, 16, Endian.little);
  ascii(36, 'data');
  header.setUint32(40, dataBytes, Endian.little);
  return header.buffer.asUint8List();
}

class _RfvpAudioHandle {
  _RfvpAudioHandle({
    required this.player,
    required this.channel,
    required this.loop,
    required this.gain,
    required this.pan,
  });

  final audio.AudioPlayer player;
  final String channel;
  final bool loop;
  double gain;
  double pan;
  Timer? _fadeTimer;
  Completer<void>? _fadeCompleter;
  bool _disposed = false;

  static Future<_RfvpAudioHandle> create({
    required File file,
    required String channel,
    required bool loop,
    required double gain,
    required double pan,
  }) async {
    final handle = _RfvpAudioHandle(
      player: audio.AudioPlayer(),
      channel: channel,
      loop: loop,
      gain: gain.clamp(0, 1),
      pan: pan,
    );
    try {
      await handle.player.setReleaseMode(
        loop ? audio.ReleaseMode.loop : audio.ReleaseMode.stop,
      );
      await handle.player.setSource(audio.DeviceFileSource(file.path));
      await handle.setPan(pan);
      return handle;
    } catch (_) {
      await handle.dispose();
      rethrow;
    }
  }

  Future<void> play() => player.resume();

  Future<void> setEffectiveVolume(double volume) async {
    await player.setVolume(volume.clamp(0, 1));
  }

  Future<void> setPan(double value) async {
    pan = value.clamp(-1, 1);
    await player.setBalance(pan);
  }

  Future<void> fadeTo(double target, int durationMs) async {
    _fadeTimer?.cancel();
    _fadeCompleter?.complete();
    target = target.clamp(0, 1);
    if (durationMs <= 0) {
      await setEffectiveVolume(target);
      return;
    }
    final start = player.volume;
    final steps = math.max(1, durationMs ~/ 30);
    var step = 0;
    final completer = _fadeCompleter = Completer<void>();
    _fadeTimer = Timer.periodic(const Duration(milliseconds: 30), (timer) {
      if (_disposed) {
        timer.cancel();
        if (!completer.isCompleted) completer.complete();
        return;
      }
      step += 1;
      final progress = (step / steps).clamp(0, 1).toDouble();
      unawaited(setEffectiveVolume(start + (target - start) * progress));
      if (step >= steps) {
        timer.cancel();
        if (!completer.isCompleted) completer.complete();
      }
    });
    await completer.future;
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _fadeTimer?.cancel();
    if (_fadeCompleter case final completer? when !completer.isCompleted) {
      completer.complete();
    }
    await player.dispose();
  }
}
