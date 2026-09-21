import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:audio_decode/audio_decode.dart';

/// Whether [bytes] use a compressed format that Darwin's AudioToolbox path
/// should not receive directly.
bool encodedAudioNeedsPcmWav(Uint8List bytes) {
  try {
    final format = detectFormat(bytes);
    return format == AudioFormat.ogg || format == AudioFormat.mp3;
  } catch (_) {
    return false;
  }
}

/// Decodes an encoded audio payload into a canonical 16-bit PCM WAV file.
///
/// Decoding and writing run in a background isolate. PCM samples are streamed
/// to disk in chunks instead of building a second full-size WAV buffer.
Future<void> decodeAudioToPcmWavFile(Uint8List bytes, String outputPath) {
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
