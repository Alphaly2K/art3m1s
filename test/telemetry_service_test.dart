import 'dart:async';

import 'package:art3m1s/services/logger.dart';
import 'package:art3m1s/services/telemetry_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TelemetryService', () {
    test('maps existing log levels to telemetry levels', () async {
      final service = TelemetryService();
      final sink = _RecordingSink();
      service.registerSink(sink);

      service.captureLog(level: 'D', message: 'debug');
      service.captureLog(level: 'I', message: 'info');
      service.captureLog(level: 'W', message: 'warning');
      service.captureLog(level: 'E', message: 'error');
      await Future<void>.delayed(Duration.zero);

      expect(sink.records.map((record) => record.level), [
        TelemetryLevel.debug,
        TelemetryLevel.info,
        TelemetryLevel.warning,
        TelemetryLevel.error,
      ]);
    });

    test('keeps dispatch stable when a sink logs recursively', () async {
      final service = TelemetryService();
      final sink = _RecursiveSink(service);
      service.registerSink(sink);

      service.captureLog(level: 'I', message: 'outer');
      await Future<void>.delayed(Duration.zero);

      expect(sink.records.length, 1);
      expect(sink.records.single.message, 'outer');
    });

    test('unregisters sinks by stable name', () async {
      final service = TelemetryService();
      final sink = _RecordingSink();
      service.registerSink(sink);
      service.unregisterSink(sink.name);

      service.captureLog(level: 'I', message: 'ignored');
      await Future<void>.delayed(Duration.zero);

      expect(sink.records, isEmpty);
    });

    test('does not dispatch while disabled', () async {
      final service = TelemetryService();
      final sink = _RecordingSink();
      service.registerSink(sink);
      service.setEnabled(false);

      service.captureLog(level: 'E', message: 'ignored');
      await Future<void>.delayed(Duration.zero);

      expect(sink.records, isEmpty);
    });

    test('receives entries from the existing Log handler', () async {
      final sink = _RecordingSink();
      TelemetryService.instance.registerSink(sink);
      try {
        Log.info('handler bridge');
        await Future<void>.delayed(Duration.zero);

        expect(sink.records, hasLength(1));
        expect(sink.records.single.message, 'handler bridge');
      } finally {
        TelemetryService.instance.unregisterSink(sink.name);
      }
    });
  });

  group('TelemetrySanitizer', () {
    test('redacts Unix and Windows paths', () {
      expect(
        TelemetrySanitizer.redact(
          'open /Users/alice/Games/secret/game.bin and C:\\Users\\alice\\game',
        ),
        'open <redacted-path> and <redacted-path>',
      );
    });

    test('redacts common credentials', () {
      expect(
        TelemetrySanitizer.redact(
          'Authorization: Bearer abc.def token=12345 api_key: secret',
        ),
        'Authorization: Bearer <redacted> token=<redacted> api_key: <redacted>',
      );
    });
  });
}

class _RecordingSink implements TelemetrySink {
  final List<TelemetryRecord> records = <TelemetryRecord>[];

  @override
  String get name => 'recording';

  @override
  FutureOr<void> capture(TelemetryRecord record) {
    records.add(record);
  }

  @override
  FutureOr<void> flush() {}
}

class _RecursiveSink implements TelemetrySink {
  _RecursiveSink(this.service);

  final TelemetryService service;
  final List<TelemetryRecord> records = <TelemetryRecord>[];

  @override
  String get name => 'recursive';

  @override
  FutureOr<void> capture(TelemetryRecord record) {
    records.add(record);
    service.captureLog(level: 'I', message: 'nested');
  }

  @override
  FutureOr<void> flush() {}
}
