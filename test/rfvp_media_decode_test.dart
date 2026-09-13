import 'dart:io';

import 'package:art3m1s/engine/backends/rfvp/rfvp_media_host.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final input = Platform.environment['RFVP_AUDIO_PROBE_INPUT'];

  test(
    'decodes RFVP encoded audio into PCM WAV',
    () async {
      final encoded = File(input!).readAsBytesSync();
      final output = File('/tmp/rfvp_host_decoded.wav');
      if (output.existsSync()) output.deleteSync();
      await decodeRfvpAudioToWavFile(encoded, output.path);

      expect(output.lengthSync(), greaterThan(44));
      final header = output.readAsBytesSync().take(12).toList();
      expect(String.fromCharCodes(header, 0, 4), 'RIFF');
      expect(String.fromCharCodes(header, 8, 12), 'WAVE');
    },
    skip: input == null ? 'RFVP_AUDIO_PROBE_INPUT is not set' : false,
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
