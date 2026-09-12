import 'dart:typed_data';

import 'package:art3m1s/engine/backends/rfvp/rfvp_api.dart';
import 'package:art3m1s/engine/backends/rfvp/rfvp_software_renderer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('renders an RGBA texture through RFVP vertices', () {
    final renderer = RfvpSoftwareRenderer();
    final pixels = renderer.render(
      RfvpFrame(
        width: 2,
        height: 2,
        textures: [
          RfvpTextureCommand(
            kind: rfvpTextureCreate,
            textureId: 1,
            format: rfvpTextureFormatRgba8,
            width: 1,
            height: 1,
            mipCount: 1,
            rowBytes: 4,
            rect: const RfvpRectI32(0, 0, 1, 1),
            generation: 1,
            pixels: Uint8List.fromList(const [255, 0, 0, 255]),
          ),
        ],
        hitProxies: const [],
        commands: [_quad(textureId: 1, left: 0, top: 0, right: 2, bottom: 2)],
      ),
    );

    expect(pixels, everyElement(isNotNull));
    for (var offset = 0; offset < pixels.length; offset += 4) {
      expect(pixels[offset], 255);
      expect(pixels[offset + 1], 0);
      expect(pixels[offset + 2], 0);
      expect(pixels[offset + 3], 255);
    }
  });

  test('honors clipped draw commands', () {
    final renderer = RfvpSoftwareRenderer();
    final pixels = renderer.render(
      RfvpFrame(
        width: 2,
        height: 1,
        textures: [
          RfvpTextureCommand(
            kind: rfvpTextureCreate,
            textureId: 2,
            format: rfvpTextureFormatRgba8,
            width: 1,
            height: 1,
            mipCount: 1,
            rowBytes: 4,
            rect: const RfvpRectI32(0, 0, 1, 1),
            generation: 1,
            pixels: Uint8List.fromList(const [0, 0, 255, 255]),
          ),
        ],
        hitProxies: const [],
        commands: [
          _quad(
            textureId: 2,
            left: 0,
            top: 0,
            right: 2,
            bottom: 1,
            clip: const RfvpRectI32(1, 0, 1, 1),
          ),
        ],
      ),
    );

    expect(pixels.sublist(0, 4), [0, 0, 0, 255]);
    expect(pixels.sublist(4, 8), [0, 0, 255, 255]);
  });
}

RfvpDrawCommand _quad({
  required int textureId,
  required double left,
  required double top,
  required double right,
  required double bottom,
  RfvpRectI32? clip,
}) {
  const color = RfvpColor(1, 1, 1, 1);
  return RfvpDrawCommand(
    kind: rfvpDrawImage,
    flags: clip == null ? 0 : rfvpDrawFlagHasClip,
    textureId: textureId,
    blend: 0,
    filter: 0,
    effectId: 0,
    meshTopology: 1,
    srcRect: const RfvpRectU16(0, 0, 0, 0),
    dstRect: RfvpRectI32(
      left.toInt(),
      top.toInt(),
      (right - left).toInt(),
      (bottom - top).toInt(),
    ),
    clipRect: clip ?? const RfvpRectI32(0, 0, 0, 0),
    color: color,
    vertices: [
      RfvpVertex(x: left, y: bottom, u: 0, v: 1, color: color),
      RfvpVertex(x: left, y: top, u: 0, v: 0, color: color),
      RfvpVertex(x: right, y: bottom, u: 1, v: 1, color: color),
      RfvpVertex(x: right, y: top, u: 1, v: 0, color: color),
    ],
    mesh: const [],
    effectData: Uint8List(0),
  );
}
