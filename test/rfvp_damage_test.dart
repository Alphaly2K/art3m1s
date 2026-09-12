import 'dart:typed_data';

import 'package:art3m1s/services/rfvp_api.dart';
import 'package:art3m1s/services/rfvp_damage.dart';
import 'package:flutter_test/flutter_test.dart';

const _white = RfvpColor(1, 1, 1, 1);

RfvpDrawCommand _command({
  required int textureId,
  required int x,
  int y = 0,
  int width = 10,
  int height = 10,
}) {
  return RfvpDrawCommand(
    kind: rfvpDrawImage,
    flags: 0,
    textureId: textureId,
    blend: 0,
    filter: 1,
    effectId: 0,
    meshTopology: 1,
    srcRect: const RfvpRectU16(0, 0, 0, 0),
    dstRect: RfvpRectI32(x, y, width, height),
    clipRect: const RfvpRectI32(0, 0, 0, 0),
    color: _white,
    vertices: const [
      RfvpVertex(x: 0, y: 0, u: 0, v: 0, color: _white),
      RfvpVertex(x: 0, y: 0, u: 0, v: 0, color: _white),
      RfvpVertex(x: 0, y: 0, u: 0, v: 0, color: _white),
      RfvpVertex(x: 0, y: 0, u: 0, v: 0, color: _white),
    ],
    mesh: const [],
    effectData: Uint8List(0),
  );
}

RfvpFrame _frame(
  List<RfvpDrawCommand> commands, {
  List<RfvpTextureCommand> textures = const [],
}) {
  return RfvpFrame(
    width: 100,
    height: 100,
    commands: commands,
    textures: textures,
    hitProxies: const [],
  );
}

RfvpTextureCommand _texture(int id, int generation) {
  return RfvpTextureCommand(
    kind: rfvpTextureUpdate,
    textureId: id,
    format: rfvpTextureFormatRgba8,
    width: 10,
    height: 10,
    mipCount: 1,
    rowBytes: 40,
    rect: const RfvpRectI32(0, 0, 10, 10),
    generation: generation,
    pixels: Uint8List(0),
  );
}

void main() {
  test('first frame is full and identical frame has no damage', () {
    final tracker = RfvpDamageTracker();
    final frame = _frame([_command(textureId: 1, x: 10)]);

    expect(tracker.update(frame).full, isTrue);
    expect(tracker.update(frame).hasDamage, isFalse);
  });

  test('moved command damages old and new bounds', () {
    final tracker = RfvpDamageTracker();
    tracker.update(_frame([_command(textureId: 1, x: 10)]));

    final damage = tracker.update(
      _frame([_command(textureId: 1, x: 30)]),
    );

    expect(damage.full, isFalse);
    expect(damage.rect?.x, 10);
    expect(damage.rect?.width, 30);
  });

  test('texture generation change damages commands using that texture', () {
    final tracker = RfvpDamageTracker();
    tracker.update(
      _frame(
        [_command(textureId: 1, x: 10), _command(textureId: 2, x: 50)],
        textures: [_texture(1, 1), _texture(2, 1)],
      ),
    );

    final damage = tracker.update(
      _frame(
        [_command(textureId: 1, x: 10), _command(textureId: 2, x: 50)],
        textures: [_texture(1, 2)],
      ),
    );

    expect(damage.full, isFalse);
    expect(damage.rect?.x, 10);
    expect(damage.rect?.width, 10);
  });

  test('large changed region falls back to full frame', () {
    final tracker = RfvpDamageTracker();
    tracker.update(_frame([_command(textureId: 1, x: 0)]));

    final damage = tracker.update(
      _frame([_command(textureId: 1, x: 0, width: 100, height: 100)]),
    );

    expect(damage.full, isTrue);
  });
}
