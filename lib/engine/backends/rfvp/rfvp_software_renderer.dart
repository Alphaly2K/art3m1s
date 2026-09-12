import 'dart:math' as math;
import 'dart:typed_data';

import 'rfvp_api.dart';

/// CPU fallback for RFVP's backend-neutral draw commands.
///
/// The host renderer is intentionally independent from `art3m1s-core`. It is
/// sufficient for bringing the RFVP runtime up while the shared native render
/// backend remains the long-term path.
class RfvpSoftwareRenderer {
  final Map<int, _RfvpTexture> _textures = {};

  Uint8List render(RfvpFrame frame) {
    _applyTextureCommands(frame.textures);

    final width = frame.width;
    final height = frame.height;
    final pixels = Uint8List(width * height * 4);
    for (var offset = 3; offset < pixels.length; offset += 4) {
      pixels[offset] = 255;
    }

    for (final command in frame.commands) {
      _drawCommand(pixels, width, height, command);
    }
    return pixels;
  }

  void reset() {
    _textures.clear();
  }

  void _applyTextureCommands(List<RfvpTextureCommand> commands) {
    for (final command in commands) {
      switch (command.kind) {
        case rfvpTextureCreate:
          _textures[command.textureId] = _RfvpTexture.create(command);
        case rfvpTextureUpdate:
          _textures[command.textureId]?.update(command);
        case rfvpTextureDestroy:
          _textures.remove(command.textureId);
      }
    }
  }

  void _drawCommand(
    Uint8List target,
    int width,
    int height,
    RfvpDrawCommand command,
  ) {
    if (command.kind == rfvpDrawSolid && command.vertices.length < 4) return;
    final texture = command.textureId == rfvpTextureIdWhite
        ? _whiteTexture
        : _textures[command.textureId];
    if (texture == null) return;

    final clip = command.hasClip
        ? _clipRect(command.clipRect, width, height)
        : (0, 0, width, height);
    if (clip == null) return;

    final vertices = command.hasMesh || command.mesh.isNotEmpty
        ? command.mesh
        : command.vertices;
    if (vertices.length < 3) return;

    if (command.meshTopology == 2) {
      for (var index = 0; index + 2 < vertices.length; index++) {
        final a = vertices[index];
        final b = vertices[index + 1];
        final c = vertices[index + 2];
        if (index.isEven) {
          _rasterTriangle(
            target,
            width,
            height,
            clip,
            a,
            b,
            c,
            command,
            texture,
          );
        } else {
          _rasterTriangle(
            target,
            width,
            height,
            clip,
            b,
            a,
            c,
            command,
            texture,
          );
        }
      }
      return;
    }

    if (vertices.length == 4 && !command.hasMesh && command.mesh.isEmpty) {
      _rasterTriangle(
        target,
        width,
        height,
        clip,
        vertices[0],
        vertices[1],
        vertices[2],
        command,
        texture,
      );
      _rasterTriangle(
        target,
        width,
        height,
        clip,
        vertices[2],
        vertices[1],
        vertices[3],
        command,
        texture,
      );
      return;
    }

    for (var index = 0; index + 2 < vertices.length; index += 3) {
      _rasterTriangle(
        target,
        width,
        height,
        clip,
        vertices[index],
        vertices[index + 1],
        vertices[index + 2],
        command,
        texture,
      );
    }
  }

  void _rasterTriangle(
    Uint8List target,
    int width,
    int height,
    (int, int, int, int) clip,
    RfvpVertex a,
    RfvpVertex b,
    RfvpVertex c,
    RfvpDrawCommand command,
    _RfvpTexture texture,
  ) {
    final area = _edge(a.x, a.y, b.x, b.y, c.x, c.y);
    if (area.abs() <= 1e-6) return;

    final minX = math.max(clip.$1, math.min(a.x, math.min(b.x, c.x)).floor());
    final minY = math.max(clip.$2, math.min(a.y, math.min(b.y, c.y)).floor());
    final maxX = math.min(
      clip.$1 + clip.$3,
      math.max(a.x, math.max(b.x, c.x)).ceil(),
    );
    final maxY = math.min(
      clip.$2 + clip.$4,
      math.max(a.y, math.max(b.y, c.y)).ceil(),
    );
    if (minX >= maxX || minY >= maxY) return;

    final inverseArea = 1.0 / area;
    for (var y = minY; y < maxY; y++) {
      for (var x = minX; x < maxX; x++) {
        final px = x + 0.5;
        final py = y + 0.5;
        final wa = _edge(b.x, b.y, c.x, c.y, px, py) * inverseArea;
        final wb = _edge(c.x, c.y, a.x, a.y, px, py) * inverseArea;
        final wc = _edge(a.x, a.y, b.x, b.y, px, py) * inverseArea;
        if (wa < 0 || wb < 0 || wc < 0) continue;

        final u = a.u * wa + b.u * wb + c.u * wc;
        final v = a.v * wa + b.v * wb + c.v * wc;
        final sampled = texture.sample(
          u,
          v,
          nearest: command.filter == 0 || command.kind == rfvpDrawGlyph,
        );
        if (sampled.a <= 0) continue;

        final color = RfvpColor(
          a.color.r * wa + b.color.r * wb + c.color.r * wc,
          a.color.g * wa + b.color.g * wb + c.color.g * wc,
          a.color.b * wa + b.color.b * wb + c.color.b * wc,
          a.color.a * wa + b.color.a * wb + c.color.a * wc,
        );
        _blendPixel(
          target,
          width,
          height,
          x,
          y,
          sampled.r * color.r,
          sampled.g * color.g,
          sampled.b * color.b,
          sampled.a * color.a,
          command.blend,
        );
      }
    }
  }

  void _blendPixel(
    Uint8List target,
    int width,
    int height,
    int x,
    int y,
    double sourceR,
    double sourceG,
    double sourceB,
    double sourceA,
    int blend,
  ) {
    if (x < 0 || y < 0 || x >= width || y >= height || sourceA <= 0) return;
    final offset = (y * width + x) * 4;
    final dstR = target[offset] / 255.0;
    final dstG = target[offset + 1] / 255.0;
    final dstB = target[offset + 2] / 255.0;

    final (outR, outG, outB) = switch (blend) {
      1 => (
        (dstR + sourceR).clamp(0.0, 1.0),
        (dstG + sourceG).clamp(0.0, 1.0),
        (dstB + sourceB).clamp(0.0, 1.0),
      ),
      2 => (
        (dstR - sourceR).clamp(0.0, 1.0),
        (dstG - sourceG).clamp(0.0, 1.0),
        (dstB - sourceB).clamp(0.0, 1.0),
      ),
      3 => (dstR * sourceR, dstG * sourceG, dstB * sourceB),
      4 => (
        1 - (1 - dstR) * (1 - sourceR),
        1 - (1 - dstG) * (1 - sourceG),
        1 - (1 - dstB) * (1 - sourceB),
      ),
      _ => (
        sourceR * sourceA + dstR * (1 - sourceA),
        sourceG * sourceA + dstG * (1 - sourceA),
        sourceB * sourceA + dstB * (1 - sourceA),
      ),
    };

    target[offset] = _toByte(outR);
    target[offset + 1] = _toByte(outG);
    target[offset + 2] = _toByte(outB);
    target[offset + 3] = math.max(target[offset + 3], _toByte(sourceA));
  }

  static int _toByte(double value) => (value.clamp(0.0, 1.0) * 255).round();

  static double _edge(
    double ax,
    double ay,
    double bx,
    double by,
    double px,
    double py,
  ) => (px - ax) * (by - ay) - (py - ay) * (bx - ax);

  static (int, int, int, int)? _clipRect(
    RfvpRectI32 rect,
    int width,
    int height,
  ) {
    final left = math.max(0, rect.x).toInt();
    final top = math.max(0, rect.y).toInt();
    final right = math.min(width, rect.x + math.max(0, rect.width)).toInt();
    final bottom = math.min(height, rect.y + math.max(0, rect.height)).toInt();
    if (left >= right || top >= bottom) return null;
    return (left, top, right - left, bottom - top);
  }

  static final _RfvpTexture _whiteTexture = _RfvpTexture(
    1,
    1,
    rfvpTextureFormatRgba8,
    Uint8List.fromList(const [255, 255, 255, 255]),
  );
}

class _RfvpTexture {
  _RfvpTexture(this.width, this.height, this.format, this.pixels);

  factory _RfvpTexture.create(RfvpTextureCommand command) {
    final bytesPerPixel = command.format == rfvpTextureFormatLumaA8 ? 2 : 4;
    final expected = command.width * command.height * bytesPerPixel;
    final pixels = Uint8List(expected);
    final copyLength = math.min(expected, command.pixels.length);
    if (copyLength > 0) {
      pixels.setRange(0, copyLength, command.pixels);
    }
    return _RfvpTexture(command.width, command.height, command.format, pixels);
  }

  final int width;
  final int height;
  final int format;
  final Uint8List pixels;

  void update(RfvpTextureCommand command) {
    if (command.width != 0 && command.width != width) return;
    if (command.height != 0 && command.height != height) return;
    final bytesPerPixel = this.bytesPerPixel;
    final rowBytes = width * bytesPerPixel;
    final sourceRowBytes = math.min(
      command.rowBytes == 0 ? rowBytes : command.rowBytes,
      rowBytes,
    );
    final rectX = math.max(0, command.rect.x);
    final rectY = math.max(0, command.rect.y);
    final rectWidth = math.min(command.rect.width, width - rectX);
    final rectHeight = math.min(command.rect.height, height - rectY);
    if (rectWidth <= 0 || rectHeight <= 0) return;

    for (var row = 0; row < rectHeight; row++) {
      final sourceStart = row * sourceRowBytes;
      final sourceEnd = sourceStart + rectWidth * bytesPerPixel;
      if (sourceEnd > command.pixels.length) break;
      final targetStart = (rectY + row) * rowBytes + rectX * bytesPerPixel;
      pixels.setRange(
        targetStart,
        targetStart + rectWidth * bytesPerPixel,
        command.pixels,
        sourceStart,
      );
    }
  }

  int get bytesPerPixel => format == rfvpTextureFormatLumaA8 ? 2 : 4;

  RfvpColor sample(double u, double v, {required bool nearest}) {
    if (width <= 0 || height <= 0) return const RfvpColor(0, 0, 0, 0);
    final x = u.clamp(0.0, 1.0) * (width - 1);
    final y = v.clamp(0.0, 1.0) * (height - 1);
    if (nearest) {
      return _read(x.round(), y.round());
    }
    final x0 = x.floor();
    final y0 = y.floor();
    final x1 = math.min(x0 + 1, width - 1);
    final y1 = math.min(y0 + 1, height - 1);
    final tx = x - x0;
    final ty = y - y0;
    final c00 = _read(x0, y0);
    final c10 = _read(x1, y0);
    final c01 = _read(x0, y1);
    final c11 = _read(x1, y1);
    return RfvpColor(
      _lerp(_lerp(c00.r, c10.r, tx), _lerp(c01.r, c11.r, tx), ty),
      _lerp(_lerp(c00.g, c10.g, tx), _lerp(c01.g, c11.g, tx), ty),
      _lerp(_lerp(c00.b, c10.b, tx), _lerp(c01.b, c11.b, tx), ty),
      _lerp(_lerp(c00.a, c10.a, tx), _lerp(c01.a, c11.a, tx), ty),
    );
  }

  RfvpColor _read(int x, int y) {
    final offset = (y * width + x) * bytesPerPixel;
    if (format == rfvpTextureFormatLumaA8) {
      final luma = pixels[offset] / 255.0;
      return RfvpColor(luma, luma, luma, pixels[offset + 1] / 255.0);
    }
    return RfvpColor(
      pixels[offset] / 255.0,
      pixels[offset + 1] / 255.0,
      pixels[offset + 2] / 255.0,
      pixels[offset + 3] / 255.0,
    );
  }

  static double _lerp(double a, double b, double t) => a + (b - a) * t;
}
