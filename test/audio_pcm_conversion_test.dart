import 'dart:typed_data';

import 'package:art3m1s/engine/backends/audio_decode_utils.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'F32 audio clips peaks and silences non-finite samples in a byte view',
    () {
      final values = [-2.0, -0.5, 0.0, 0.5, 2.0, double.nan, double.infinity];
      final data = ByteData(4 + values.length * 4);
      for (var i = 0; i < values.length; i++) {
        data.setFloat32(4 + i * 4, values[i], Endian.little);
      }
      final pcm = float32PcmToInt16(data.buffer.asUint8List(4));
      final decoded = ByteData.sublistView(pcm);
      expect(
        [
          for (var i = 0; i < pcm.length; i += 2)
            decoded.getInt16(i, Endian.little),
        ],
        [-32767, -16383, 0, 16383, 32767, 0, 0],
      );
      expect(() => float32PcmToInt16(Uint8List(3)), throwsFormatException);
    },
  );
}
