import 'dart:ffi';

import 'package:art3m1s/engine/backends/rfvp/core_rfvp_api.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('RFVP ABI v1 Dart layouts match the C contract on 64-bit hosts', () {
    if (sizeOf<Pointer<Void>>() != 8) {
      return;
    }

    expect(CoreRfvpApiV1.inputEventSize, 40);
    expect(CoreRfvpApiV1.audioCommandSize, 88);
    // 16 字节头 + 28 个函数指针（含表尾追加的 log/文本事件/字体覆盖/
    // trace mask/profiler/脏区可视化）。
    expect(CoreRfvpApiV1.apiTableSize, 240);
  });
}
