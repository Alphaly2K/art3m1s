import 'dart:io';

import 'package:art3m1s/engine/native_library.dart';
import 'package:art3m1s/engine/backends/krkr/core_krkr_api.dart';
import 'package:art3m1s/engine/backends/siglus/core_siglus_api.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('host wrappers load both engine contracts from the built core', () {
    expect(Platform.environment['ART3M1S_CORE_LIBRARY'], isNotEmpty);
    final library = openEngineCoreLibrary();
    expect(CoreKrkrApiV1.tryLoad(library), isNotNull);
    final controls = CoreKrkrControlV1.tryLoad(library);
    expect(controls, isNotNull);
    expect(controls!.volume(0, 0.5), isNot(art3m1sKrkrStatusOk));
    expect(CoreSiglusApiV1.tryLoad(library), isNotNull);
    expect(CoreSiglusAudioV1.tryLoad(library), isNotNull);
    expect(CoreSiglusDiagnosticsV1.tryLoad(library), isNotNull);
    final output = CoreSiglusOutputV1.tryLoad(library);
    expect(output, isNotNull);
    expect(output!.start(0), isNot(CoreSiglusApiV1.ok));
    expect(output.stop(0), isNot(CoreSiglusApiV1.ok));
  });
}
