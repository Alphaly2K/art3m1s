import 'package:flutter_test/flutter_test.dart';

import '../tool/build.dart';

void main() {
  test('optional engines reach every native target', () {
    for (final target in [
      'android',
      'ios',
      'ios-obsolete',
      'macos',
      'windows',
      'linux',
    ]) {
      final options = BuildOptions.parse([target, '--krkr', '--siglus']);
      expect(options.krkr, isTrue);
      expect(options.siglus, isTrue);
      final features = coreFeaturesForTarget(
        target,
        krkr: options.krkr,
        siglus: options.siglus,
      );
      expect(features, containsAll(['krkr-engine', 'siglus-engine']));
      final darwin = ['ios', 'ios-obsolete', 'macos'].contains(target);
      expect(features.contains('metal-backend'), darwin);
      expect(features.contains('vulkan-backend'), !darwin);
      expect(features.contains('ffmpeg'), darwin);
    }
  });

  test('portable builds can opt into FFmpeg and omit optional engines', () {
    final features = coreFeaturesForTarget(
      'linux',
      krkr: false,
      siglus: false,
      ffmpeg: true,
    );
    expect(features, contains('ffmpeg'));
    expect(features, isNot(contains('krkr-engine')));
    expect(features, isNot(contains('siglus-engine')));
  });
}
