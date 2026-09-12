import 'dart:ffi';

import 'package:art3m1s/services/rfvp_api.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('RFVP ABI v1 Dart layouts match the C contract on 64-bit hosts', () {
    if (sizeOf<Pointer<Void>>() != 8) {
      return;
    }

    expect(RfvpApiV1.resourcesConfigSize, 64);
    expect(RfvpApiV1.runtimeConfigSize, 56);
    expect(RfvpApiV1.inputEventSize, 40);
    expect(RfvpApiV1.audioCommandSize, 88);
    expect(RfvpApiV1.textureCommandSize, 88);
    expect(RfvpApiV1.drawCommandSize, 264);
    expect(RfvpApiV1.apiTableSize, 272);
  });
}
