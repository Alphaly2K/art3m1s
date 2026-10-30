import 'dart:io';

import 'package:art3m1s/engine/backends/audio_decode_utils.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final input = Platform.environment['RFVP_AUDIO_PROBE_INPUT'];

  test(
    'decodes RFVP encoded audio into PCM WAV',
    () async {
      final encoded = File(input!).readAsBytesSync();
      final temporary = Directory.systemTemp.createTempSync(
        'rfvp_audio_probe_',
      );
      addTearDown(() => temporary.deleteSync(recursive: true));
      final output = File('${temporary.path}/decoded.wav');
      await decodeAudioToPcmWavFile(encoded, output.path);

      expect(output.lengthSync(), greaterThan(44));
      final header = output.readAsBytesSync().take(12).toList();
      expect(String.fromCharCodes(header, 0, 4), 'RIFF');
      expect(String.fromCharCodes(header, 8, 12), 'WAVE');
    },
    skip: input == null ? 'RFVP_AUDIO_PROBE_INPUT is not set' : false,
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
