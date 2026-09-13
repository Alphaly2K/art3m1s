import 'dart:ffi';

import 'package:art3m1s/engine/backends/krkr/core_krkr_api.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('KRKR ABI v1 Dart layouts match the C contract on 64-bit hosts', () {
    expect(sizeOf<IntPtr>(), 8);
    expect(CoreKrkrApiV1.probeSize, 64);
    expect(CoreKrkrApiV1.runtimeConfigSize, 56);
    expect(CoreKrkrApiV1.inputEventSize, 40);
    expect(CoreKrkrApiV1.frameSize, 72);
    expect(CoreKrkrApiV1.audioCommandSize, 72);
    expect(CoreKrkrApiV1.audioConsumedSize, 40);
    expect(CoreKrkrApiV1.apiTableSize, 128);
  });
}
