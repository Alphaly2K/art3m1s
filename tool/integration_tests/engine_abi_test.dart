import 'dart:io';

import 'package:art3m1s/engine/native_library.dart';
import 'package:art3m1s/engine/backends/krkr/core_krkr_api.dart';
import 'package:art3m1s/engine/backends/siglus/core_siglus_api.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('host wrappers load both engine contracts from the built core', () {
    expect(Platform.environment['ART3M1S_CORE_LIBRARY'], isNotEmpty);
    final library = openEngineCoreLibrary();
    final krkr = CoreKrkrHostV2.tryLoad(library);
    expect(krkr, isNotNull);
    expect(krkr!.supportsCpuFrames, isTrue);
    expect(krkr.controls.volume(0, 0.5), isNot(art3m1sKrkrStatusOk));
    expect(CoreKrkrApiV1.tryLoad(library), isNotNull);
    final controls = CoreKrkrControlV1.tryLoad(library);
    expect(controls, isNotNull);
    expect(controls!.volume(0, 0.5), isNot(art3m1sKrkrStatusOk));
    final siglus = CoreSiglusHostV1.tryLoad(library);
    expect(siglus, isNotNull);
    expect(siglus!.runtime.supportsSaveDirectory, isTrue);
    expect(siglus.audio.sampleRate, 48000);
    expect(siglus.ui!.submitDialog(0, 1, 0), CoreSiglusApiV1.invalidHandle);
    expect(siglus.frames!.presentLatest(0), CoreSiglusApiV1.invalidHandle);
    expect(siglus.outputClock!.pump(0, 768), CoreSiglusApiV1.invalidHandle);
    expect(siglus.output.start(0), isNot(CoreSiglusApiV1.ok));
    expect(CoreSiglusApiV1.tryLoad(library), isNotNull);
    expect(CoreSiglusAudioV1.tryLoad(library), isNotNull);
    expect(CoreSiglusDiagnosticsV1.tryLoad(library), isNotNull);
    final output = CoreSiglusOutputV1.tryLoad(library);
    expect(output, isNotNull);
    expect(output!.start(0), isNot(CoreSiglusApiV1.ok));
    expect(output.stop(0), isNot(CoreSiglusApiV1.ok));
  });
}
