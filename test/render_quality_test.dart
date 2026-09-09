import 'package:art3m1s/models/render_quality.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('native output follows aspect-fit physical pixels', () {
    expect(
      resolveRenderOutputExtent(
        stageWidth: 1920,
        stageHeight: 1080,
        physicalViewWidth: 2560,
        physicalViewHeight: 1600,
      ),
      (width: 2560, height: 1440),
    );
  });

  test('native output never degrades below authored game resolution', () {
    expect(
      resolveRenderOutputExtent(
        stageWidth: 1920,
        stageHeight: 1080,
        physicalViewWidth: 1280,
        physicalViewHeight: 720,
      ),
      (width: 1920, height: 1080),
    );
  });

  test('invalid view dimensions safely fall back to the game resolution', () {
    expect(
      resolveRenderOutputExtent(
        stageWidth: 1280,
        stageHeight: 720,
        physicalViewWidth: 0,
        physicalViewHeight: double.nan,
      ),
      (width: 1280, height: 720),
    );
  });
}
