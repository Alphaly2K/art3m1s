import 'package:art3m1s/services/profiler_snapshot.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('profiler snapshot keeps interpreter and host FFI timings separate', () {
    final snapshot = ProfilerSnapshot.fromJson({
      'enabled': true,
      'window_ms': 500,
      'tick_hz': 60.0,
      'rendered_fps': 12.0,
      'average': {
        'ffi_call_ms': 3.0,
        'logic_ms': 2.0,
        'interpreter_ms': 1.25,
        'host_ffi_ms': 0.5,
      },
      'maximum': {'interpreter_ms': 4.0},
      'damage_percent': 8.5,
      'texture_count': 42,
    });

    expect(snapshot.enabled, isTrue);
    expect(snapshot.average.interpreterMs, 1.25);
    expect(snapshot.average.hostFfiMs, 0.5);
    expect(snapshot.maximum.interpreterMs, 4.0);
    expect(snapshot.damagePercent, 8.5);
    expect(snapshot.textureCount, 42);
  });
}
