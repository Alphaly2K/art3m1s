import 'dart:math' as math;

import 'rfvp_api.dart';

class RfvpDamage {
  const RfvpDamage._({
    required this.full,
    required this.rect,
    required this.pixels,
  });

  const RfvpDamage.none()
    : full = false,
      rect = null,
      pixels = 0;

  const RfvpDamage.full(int width, int height)
    : full = true,
      rect = null,
      pixels = width * height;

  final bool full;
  final RfvpRectI32? rect;
  final int pixels;

  bool get hasDamage => full || (rect?.width ?? 0) > 0 && (rect?.height ?? 0) > 0;
}

class RfvpDamageTracker {
  RfvpFrame? _previousFrame;
  Map<int, int> _textureGenerations = const {};

  RfvpDamage update(RfvpFrame frame) {
    final previous = _previousFrame;
    _previousFrame = frame;

    if (previous == null) {
      _textureGenerations = _readTextureGenerations(frame);
      return RfvpDamage.full(frame.width, frame.height);
    }
    if (previous.width != frame.width || previous.height != frame.height) {
      _textureGenerations = _readTextureGenerations(frame);
      return RfvpDamage.full(frame.width, frame.height);
    }
    if (frame.commands.length != previous.commands.length) {
      _textureGenerations = _readTextureGenerations(frame);
      return RfvpDamage.full(frame.width, frame.height);
    }

    final dirtyTextures = <int>{};
    final nextGenerations = _readTextureGenerations(frame);
    for (final texture in frame.textures) {
      if (texture.kind == rfvpTextureDestroy) {
        _textureGenerations = nextGenerations;
        return RfvpDamage.full(frame.width, frame.height);
      }
      final generation = nextGenerations[texture.textureId];
      if (generation != null &&
          _textureGenerations[texture.textureId] != generation) {
        dirtyTextures.add(texture.textureId);
      }
    }
    _textureGenerations = nextGenerations;

    var damage = _emptyRect();
    var found = false;
    for (var index = 0; index < frame.commands.length; index++) {
      final current = frame.commands[index];
      final old = previous.commands[index];
      if (current.hasClip != old.hasClip ||
          (current.hasClip && !_sameRect(current.clipRect, old.clipRect))) {
        return RfvpDamage.full(frame.width, frame.height);
      }
      final textureChanged = dirtyTextures.contains(current.textureId);
      if (!textureChanged && _sameDrawCommand(current, old)) {
        continue;
      }
      damage = _union(damage, _commandBounds(old));
      damage = _union(damage, _commandBounds(current));
      found = true;
    }

    if (!found) return const RfvpDamage.none();
    final area =
        math.max(0, damage.width).toInt() *
        math.max(0, damage.height).toInt();
    final stageArea = math.max(1, frame.width * frame.height).toInt();
    if (area * 10 >= stageArea * 8) {
      return RfvpDamage.full(frame.width, frame.height);
    }
    return RfvpDamage._(full: false, rect: damage, pixels: area);
  }

  static Map<int, int> _readTextureGenerations(RfvpFrame frame) {
    final generations = <int, int>{};
    for (final texture in frame.textures) {
      if (texture.kind != rfvpTextureDestroy) {
        generations[texture.textureId] = texture.generation;
      }
    }
    return generations;
  }

  static bool _sameDrawCommand(RfvpDrawCommand a, RfvpDrawCommand b) {
    if (a.kind != b.kind ||
        a.flags != b.flags ||
        a.textureId != b.textureId ||
        a.blend != b.blend ||
        a.filter != b.filter ||
        a.effectId != b.effectId ||
        a.meshTopology != b.meshTopology ||
        !_sameRectU16(a.srcRect, b.srcRect) ||
        !_sameRect(a.dstRect, b.dstRect) ||
        !_sameRect(a.clipRect, b.clipRect) ||
        !_sameColor(a.color, b.color) ||
        a.mesh.length != b.mesh.length ||
        a.effectData.length != b.effectData.length) {
      return false;
    }
    for (var index = 0; index < a.vertices.length; index++) {
      if (!_sameVertex(a.vertices[index], b.vertices[index])) return false;
    }
    for (var index = 0; index < a.mesh.length; index++) {
      if (!_sameVertex(a.mesh[index], b.mesh[index])) return false;
    }
    for (var index = 0; index < a.effectData.length; index++) {
      if (a.effectData[index] != b.effectData[index]) return false;
    }
    return true;
  }

  static bool _sameColor(RfvpColor a, RfvpColor b) {
    return a.r == b.r && a.g == b.g && a.b == b.b && a.a == b.a;
  }

  static bool _sameVertex(RfvpVertex a, RfvpVertex b) {
    return a.x == b.x &&
        a.y == b.y &&
        a.u == b.u &&
        a.v == b.v &&
        _sameColor(a.color, b.color);
  }

  static bool _sameRect(RfvpRectI32 a, RfvpRectI32 b) {
    return a.x == b.x &&
        a.y == b.y &&
        a.width == b.width &&
        a.height == b.height;
  }

  static bool _sameRectU16(RfvpRectU16 a, RfvpRectU16 b) {
    return a.x == b.x &&
        a.y == b.y &&
        a.width == b.width &&
        a.height == b.height;
  }

  static RfvpRectI32 _commandBounds(RfvpDrawCommand command) {
    return RfvpRectI32(
      math.min(command.dstRect.x, command.dstRect.x + command.dstRect.width),
      math.min(command.dstRect.y, command.dstRect.y + command.dstRect.height),
      command.dstRect.width.abs(),
      command.dstRect.height.abs(),
    );
  }

  static RfvpRectI32 _emptyRect() => const RfvpRectI32(0, 0, 0, 0);

  static RfvpRectI32 _union(RfvpRectI32 a, RfvpRectI32 b) {
    if (a.width <= 0 || a.height <= 0) return b;
    if (b.width <= 0 || b.height <= 0) return a;
    final left = math.min(a.x, b.x);
    final top = math.min(a.y, b.y);
    final right = math.max(a.x + a.width, b.x + b.width);
    final bottom = math.max(a.y + a.height, b.y + b.height);
    return RfvpRectI32(left, top, right - left, bottom - top);
  }
}
