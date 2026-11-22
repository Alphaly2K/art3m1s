import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:art3m1s/engine/backends/katze/core_katze_api.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';

typedef _NewFixture =
    Pointer<KatzeCreateInfo> Function(
      Pointer<Uint8>,
      Size,
      Pointer<Uint8>,
      Size,
    );
typedef _NewFixtureDart =
    Pointer<KatzeCreateInfo> Function(Pointer<Uint8>, int, Pointer<Uint8>, int);
typedef _FixtureVertices =
    Size Function(Pointer<KatzeCreateInfo>, Pointer<Float>, Pointer<Uint32>);
typedef _FixtureVerticesDart =
    int Function(Pointer<KatzeCreateInfo>, Pointer<Float>, Pointer<Uint32>);
typedef _FreeFixture = Size Function(Pointer<KatzeCreateInfo>);

String _requiredEnv(String name) {
  final value = Platform.environment[name];
  if (value == null || value.isEmpty) throw StateError('Set $name');
  return value;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Katze ABI supplies Flutter pixels and detached stereo PCM', () async {
    final api = KatzeApi.load(
      DynamicLibrary.open(_requiredEnv('KATZE_LIBRARY')),
    );
    final native = DynamicLibrary.open(_requiredEnv('KATZE_FIXTURE_HOST'));
    final root = _requiredEnv('KATZE_FIXTURES');
    final createFixture = native.lookupFunction<_NewFixture, _NewFixtureDart>(
      'katze_fixture_new',
    );
    final readVertices = native
        .lookupFunction<_FixtureVertices, _FixtureVerticesDart>(
          'katze_fixture_vertices',
        );
    final freeFixture = native
        .lookupFunction<_FreeFixture, int Function(Pointer<KatzeCreateInfo>)>(
          'katze_fixture_free',
        );

    final (width, height, xy, argb) = using((arena) {
      Pointer<Uint8> contents(Uint8List bytes) =>
          arena<Uint8>(bytes.length)
            ..asTypedList(bytes.length).setAll(0, bytes);
      final script = File('$root/host.kcs').readAsBytesSync();
      final ogg = File('$root/tone.ogg').readAsBytesSync();
      final fixture = createFixture(
        contents(script),
        script.length,
        contents(ogg),
        ogg.length,
      );
      expect(fixture, isNot(nullptr));
      final int session;
      try {
        session = api.create(fixture);
      } catch (_) {
        freeFixture(fixture);
        rethrow;
      }
      try {
        final (width, height) = api.stage(session);
        expect((width, height), (64, 48));
        final time = arena<KatzeFrameTime>();
        time.ref.increment = 1;
        final flags = arena<Uint32>();
        final pcm = arena<Float>(1600);
        var audibleSamples = 0;
        for (var tick = 1; tick <= 8; tick++) {
          time.ref.tick = tick;
          time.ref.milliseconds = tick * 1000 ~/ 60;
          expect(api.step(session, time, flags) & 1, 0);
          api.mixStereo(session, 48000, pcm, 800);
          for (final sample in pcm.asTypedList(1600)) {
            expect(sample.isFinite, isTrue);
            if (sample.abs() > 0.00001) audibleSamples++;
          }
        }
        expect(audibleSamples, greaterThan(0));
        api.present(session);
        final positions = arena<Float>(12);
        final colors = arena<Uint32>(6);
        final count = readVertices(fixture, positions, colors);
        expect(count, 6);
        return (
          width,
          height,
          Float32List.fromList(positions.asTypedList(count * 2)),
          Int32List.fromList(colors.asTypedList(count)),
        );
      } finally {
        api.destroy(session);
        expect(freeFixture(fixture), 0);
      }
    });

    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    final vertices = ui.Vertices.raw(ui.VertexMode.triangles, xy, colors: argb);
    canvas.drawVertices(vertices, ui.BlendMode.dst, ui.Paint());
    final picture = recorder.endRecording();
    final image = await picture.toImage(width, height);
    try {
      final pixels = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
      var colored = 0;
      var clear = 0;
      for (var offset = 0; offset < pixels.lengthInBytes; offset += 4) {
        final rgba = pixels.getUint32(offset);
        if (rgba == 0x2070c0ff) colored++;
        if (rgba == 0) clear++;
      }
      expect(colored, 16 * 12);
      expect(clear, width * height - colored);
    } finally {
      image.dispose();
      picture.dispose();
      vertices.dispose();
    }
  });
}
