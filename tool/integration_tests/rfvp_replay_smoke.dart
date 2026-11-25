import 'dart:ffi';
import 'dart:io';

import 'package:art3m1s/engine/backends/rfvp/core_rfvp_api.dart';

void main(List<String> args) {
  if (args.length != 2) {
    throw ArgumentError(
      'Expected the RFVP library and synthetic project paths',
    );
  }
  final api = CoreRfvpReplayApi.tryLoad(DynamicLibrary.open(args[0]));
  if (api == null) throw StateError('RFVP v2 table not available');
  final session = api.openDirectory(args[1], nls: art3m1sRfvpNlsUtf8);
  RfvpReplayFrame? frame;
  try {
    assert(session.acquireFrame() == null);
    session.pushInput(const [
      RfvpCoreInputEvent(kind: art3m1sRfvpInputFocus, code: 0, phase: 1),
    ]);
    final exitedFirst = session.step(16);
    final exitedSecond = session.step(16);
    assert(!exitedFirst && !exitedSecond);
    frame = session.acquireFrame() ?? (throw StateError('No RFVP frame'));
    session.close();
    final handle = frame.withView((view) {
      assert(view.width == 640 && view.height == 480);
      assert(view.drawCount == 1 && view.textureCount == 1);
      final draw = view.draws[0];
      assert(draw.kind == 1);
      assert(draw.destination.x == 8 && draw.destination.y == 12);
      assert(draw.destination.width == 16 && draw.destination.height == 20);
      assert(draw.vertices[0].x == 8);
      return draw.texture;
    });
    frame.withTexture(0, (texture) {
      assert(texture.texture == handle && texture.generation > 0);
      assert(texture.format == 1 && texture.width == 1 && texture.height == 1);
      assert(texture.pixels.length == 4);
      assert(texture.pixels.every((value) => value == 255));
    });
  } finally {
    frame?.close();
    session.close();
  }
  stdout.writeln('RFVP Dart replay smoke passed');
}
