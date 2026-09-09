import 'dart:math' as math;

enum RenderQualityPreset {
  native('原生', 0),
  quality('质量', 1),
  balanced('均衡', 2),
  performance('性能', 3);

  const RenderQualityPreset(this.label, this.ffiValue);
  final String label;
  final int ffiValue;
}

/// Resolves the native output texture extent for an aspect-fit game view.
///
/// Flutter lays widgets out in logical pixels, while external textures contain
/// physical pixels. Keeping this calculation in the Host policy layer lets the
/// core render/upscale from the authored stage to the actual displayed pixel
/// extent without making game scripts aware of window size or device DPI.
({int width, int height}) resolveRenderOutputExtent({
  required int stageWidth,
  required int stageHeight,
  required double physicalViewWidth,
  required double physicalViewHeight,
}) {
  if (stageWidth <= 0 ||
      stageHeight <= 0 ||
      !physicalViewWidth.isFinite ||
      !physicalViewHeight.isFinite ||
      physicalViewWidth <= 0 ||
      physicalViewHeight <= 0) {
    return (width: math.max(stageWidth, 1), height: math.max(stageHeight, 1));
  }
  final displayScale = math.min(
    physicalViewWidth / stageWidth,
    physicalViewHeight / stageHeight,
  );
  return (
    width: math.max(stageWidth, (stageWidth * displayScale).floor()),
    height: math.max(stageHeight, (stageHeight * displayScale).floor()),
  );
}
