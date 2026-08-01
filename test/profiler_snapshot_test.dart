import 'package:art3m1s/services/profiler_snapshot.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('profiler snapshot keeps interpreter and host FFI timings separate', () {
    final snapshot = ProfilerSnapshot.fromJson({
      'enabled': true,
      'window_ms': 500,
      'session_ms': 12500,
      'sample_window_ms': 10000,
      'sample_count': 600,
      'tick_hz': 60.0,
      'rendered_fps': 12.0,
      'current': {
        'interpreter_ms': 2.5,
        'damage_compute_ms': 0.25,
        'texture_upload_ms': 1.5,
      },
      'average': {
        'ffi_call_ms': 3.0,
        'logic_ms': 2.0,
        'interpreter_ms': 1.25,
        'host_ffi_ms': 0.5,
      },
      'one_percent': {'interpreter_ms': 4.0},
      'damage_percent': 8.5,
      'draw_calls': 17,
      'vertices': 102,
      'current_rendered': true,
      'texture_count': 42,
    });

    expect(snapshot.enabled, isTrue);
    expect(snapshot.sessionMs, 12500);
    expect(snapshot.sampleWindowMs, 10000);
    expect(snapshot.current.interpreterMs, 2.5);
    expect(snapshot.current.damageComputeMs, 0.25);
    expect(snapshot.current.textureUploadMs, 1.5);
    expect(snapshot.average.interpreterMs, 1.25);
    expect(snapshot.average.hostFfiMs, 0.5);
    expect(snapshot.onePercent.interpreterMs, 4.0);
    expect(snapshot.damagePercent, 8.5);
    expect(snapshot.drawCalls, 17);
    expect(snapshot.vertices, 102);
    expect(snapshot.currentRendered, isTrue);
    expect(snapshot.textureCount, 42);
  });

  test('profiler snapshot accepts the previous aggregate-only schema', () {
    final snapshot = ProfilerSnapshot.fromJson({
      'window_ms': 500,
      'average': {'logic_ms': 2.0},
      'maximum': {'logic_ms': 8.0},
    });

    expect(snapshot.sessionMs, 500);
    expect(snapshot.sampleWindowMs, 500);
    expect(snapshot.current.logicMs, 2.0);
    expect(snapshot.onePercent.logicMs, 8.0);
  });
}
