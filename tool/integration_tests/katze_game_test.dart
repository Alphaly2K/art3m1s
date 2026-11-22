import 'dart:ffi';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:art3m1s/engine/backends/katze/katze_game_host.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';

String _requireEnv(String key) {
  final value = Platform.environment[key];
  if (value == null || value.isEmpty) throw StateError('Set $key');
  return value;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('Katze directory mounts and supplies stage pixels and PCM', () async {
    final library = DynamicLibrary.open(_requireEnv('KATZE_GAME_HOST'));
    final root = _requireEnv('KATZE_GAME');
    final encoding = Platform.environment['KATZE_GAME_ENCODING'] ?? '';
    final game = KatzeGameHost.open(library, root, encoding: encoding);
    final click = Platform.environment['KATZE_GAME_TEST_CLICK']
        ?.split(',')
        .map(int.parse)
        .toList();
    try {
      if (click != null) {
        expect(click, hasLength(4));
        game.pointer(click[0], click[1]);
      }
      final rounds = click == null ? 1200 : click[3];
      var audible = 0;
      using((arena) {
        final output = arena<Float>(1600);
        final pcm = output.asTypedList(1600);
        for (var tick = 1; tick <= rounds; tick++) {
          if (click != null && tick == click[2]) game.button(1, 1, true);
          if (click != null && tick == click[2] + 2) game.button(1, 1, false);
          expect(
            game.step(increment: 1, milliseconds: tick * 1000 ~/ 60),
            isTrue,
          );
          game.mixStereo(48000, output, 800);
          for (var sample = 0; sample < pcm.length; sample += 2) {
            if (pcm[sample].abs() > 0.00001 ||
                pcm[sample + 1].abs() > 0.00001) {
              audible++;
            }
          }
        }
      });
      expect(audible, greaterThan(0));
      final pixels = game.present();
      final buffer = await ui.ImmutableBuffer.fromUint8List(pixels);
      final desc = ui.ImageDescriptor.raw(
        buffer,
        width: game.width,
        height: game.height,
        pixelFormat: ui.PixelFormat.bgra8888,
      );
      try {
        final codec = await desc.instantiateCodec();
        try {
          final frame = await codec.getNextFrame();
          try {
            final data = (await frame.image.toByteData(
              format: ui.ImageByteFormat.rawRgba,
            ))!;
            final distinct = <int>{};
            for (var i = 0; i < data.lengthInBytes; i += 4 * 257) {
              distinct.add(data.getUint32(i) >> 8);
            }
            expect(distinct.length, greaterThan(1));
            var checksum = 0xcbf29ce484222325;
            for (final byte in pixels) {
              checksum = (checksum ^ byte) * 0x100000001b3;
            }
            final digest =
                (checksum >>> 32).toRadixString(16).padLeft(8, '0') +
                (checksum & 0xffffffff).toRadixString(16).padLeft(8, '0');
            // ignore: avoid_print
            print(
              '${game.width}x${game.height} $rounds rounds, $audible audible frames, BGRA $digest',
            );
          } finally {
            frame.image.dispose();
          }
        } finally {
          codec.dispose();
        }
      } finally {
        desc.dispose();
        buffer.dispose();
      }
    } finally {
      game.close();
    }
  });
}
