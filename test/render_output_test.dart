import 'package:art3m1s/models/render_output.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const common = (
    stageWidth: 1920,
    stageHeight: 1080,
    physicalViewWidth: 2560.0,
    physicalViewHeight: 1600.0,
    customWidth: 3440,
    customHeight: 1440,
  );

  test('output modes expose original, display, 1.5x and 2x targets', () {
    ({int width, int height}) resolve(RenderOutputMode mode) =>
        resolveRenderOutputExtent(
          mode: mode,
          stageWidth: common.stageWidth,
          stageHeight: common.stageHeight,
          physicalViewWidth: common.physicalViewWidth,
          physicalViewHeight: common.physicalViewHeight,
          customWidth: common.customWidth,
          customHeight: common.customHeight,
        );

    expect(resolve(RenderOutputMode.original), (width: 1920, height: 1080));
    expect(resolve(RenderOutputMode.matchDisplay), (width: 2560, height: 1440));
    expect(resolve(RenderOutputMode.fixed1_5x), (width: 2880, height: 1620));
    expect(resolve(RenderOutputMode.fixed2x), (width: 3840, height: 2160));
  });

  test('custom resolution preserves the authored aspect ratio', () {
    expect(
      resolveRenderOutputExtent(
        mode: RenderOutputMode.custom,
        stageWidth: common.stageWidth,
        stageHeight: common.stageHeight,
        physicalViewWidth: common.physicalViewWidth,
        physicalViewHeight: common.physicalViewHeight,
        customWidth: common.customWidth,
        customHeight: common.customHeight,
      ),
      (width: 2560, height: 1440),
    );
  });

  test('output never degrades below authored game resolution', () {
    expect(
      resolveRenderOutputExtent(
        mode: RenderOutputMode.matchDisplay,
        stageWidth: 1920,
        stageHeight: 1080,
        physicalViewWidth: 1280,
        physicalViewHeight: 720,
        customWidth: 2560,
        customHeight: 1440,
      ),
      (width: 1920, height: 1080),
    );
  });

  test('authored SceneColor scale matches fixed upscale ratios', () {
    expect(
      authoredSceneRenderScale(
        stageWidth: 1920,
        stageHeight: 1080,
        outputWidth: 2880,
        outputHeight: 1620,
      ),
      closeTo(2 / 3, 1e-6),
    );
    expect(
      authoredSceneRenderScale(
        stageWidth: 1920,
        stageHeight: 1080,
        outputWidth: 3840,
        outputHeight: 2160,
      ),
      0.5,
    );
  });
}
