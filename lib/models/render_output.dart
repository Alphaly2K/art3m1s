import 'dart:math' as math;

enum RenderOutputMode {
  original('原始分辨率'),
  matchDisplay('跟随显示器'),
  fixed1_5x('固定 1.5×'),
  fixed2x('固定 2×'),
  custom('自定义分辨率');

  const RenderOutputMode(this.label);
  final String label;
}

String renderOutputDescription(
  RenderOutputMode mode, {
  required int customWidth,
  required int customHeight,
}) => switch (mode) {
  RenderOutputMode.custom => '$customWidth×$customHeight（保持游戏宽高比）',
  _ => mode.label,
};

/// Resolves the physical output texture extent while preserving the authored
/// stage aspect ratio. Every mode keeps at least the original game resolution.
({int width, int height}) resolveRenderOutputExtent({
  required RenderOutputMode mode,
  required int stageWidth,
  required int stageHeight,
  required double physicalViewWidth,
  required double physicalViewHeight,
  required int customWidth,
  required int customHeight,
}) {
  final safeStageWidth = math.max(stageWidth, 1);
  final safeStageHeight = math.max(stageHeight, 1);
  final bounds = switch (mode) {
    RenderOutputMode.original => (
      width: safeStageWidth.toDouble(),
      height: safeStageHeight.toDouble(),
    ),
    RenderOutputMode.fixed1_5x => (
      width: safeStageWidth * 1.5,
      height: safeStageHeight * 1.5,
    ),
    RenderOutputMode.fixed2x => (
      width: safeStageWidth * 2.0,
      height: safeStageHeight * 2.0,
    ),
    RenderOutputMode.custom => (
      width: math.max(customWidth, safeStageWidth).toDouble(),
      height: math.max(customHeight, safeStageHeight).toDouble(),
    ),
    RenderOutputMode.matchDisplay => (
      width: physicalViewWidth,
      height: physicalViewHeight,
    ),
  };
  if (!bounds.width.isFinite ||
      !bounds.height.isFinite ||
      bounds.width <= 0 ||
      bounds.height <= 0) {
    return (width: safeStageWidth, height: safeStageHeight);
  }
  final displayScale = math.min(
    bounds.width / safeStageWidth,
    bounds.height / safeStageHeight,
  );
  return (
    width: math.max(safeStageWidth, (safeStageWidth * displayScale).floor()),
    height: math.max(safeStageHeight, (safeStageHeight * displayScale).floor()),
  );
}

/// Returns the output-relative SceneColor scale that resolves exactly to the
/// authored stage size under the core's minimum-resolution policy.
double authoredSceneRenderScale({
  required int stageWidth,
  required int stageHeight,
  required int outputWidth,
  required int outputHeight,
}) {
  if (stageWidth <= 0 ||
      stageHeight <= 0 ||
      outputWidth <= stageWidth ||
      outputHeight <= stageHeight) {
    return 1.0;
  }
  return math
      .min(stageWidth / outputWidth, stageHeight / outputHeight)
      .clamp(0.1, 1.0)
      .toDouble();
}
