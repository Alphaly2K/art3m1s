import 'package:art3m1s/services/profiler_snapshot.dart';
import 'package:art3m1s/widgets/profiler_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('profiler overlay fits a compact landscape viewport', (tester) async {
    tester.view.physicalSize = const Size(844, 390);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final snapshot = ValueNotifier<ProfilerSnapshot?>(
      ProfilerSnapshot.fromJson({
        'enabled': true,
        'session_ms': 12000,
        'sample_window_ms': 10000,
        'current': <String, dynamic>{},
        'average': <String, dynamic>{},
        'one_percent': <String, dynamic>{},
      }),
    );
    addTearDown(snapshot.dispose);
    await tester.pumpWidget(
      MaterialApp(home: Stack(children: [ProfilerOverlay(snapshot: snapshot)])),
    );

    expect(tester.takeException(), isNull);
    final panel = find.descendant(
      of: find.byType(ProfilerOverlay),
      matching: find.byType(DecoratedBox),
    ).first;
    expect(tester.getBottomRight(panel).dy, lessThanOrEqualTo(390));
  });
}
