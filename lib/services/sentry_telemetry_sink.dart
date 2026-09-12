import 'package:sentry_flutter/sentry_flutter.dart';

import 'telemetry_service.dart';

/// [TelemetrySink] backed by Sentry.
///
/// Routing policy: records carrying an error/stack trace, or with level
/// error/fatal, become Sentry exceptions; everything else is attached as a
/// breadcrumb so a later crash report keeps recent context without uploading
/// every log line.
class SentryTelemetrySink implements TelemetrySink {
  const SentryTelemetrySink();

  @override
  String get name => 'sentry';

  @override
  Future<void> capture(TelemetryRecord record) async {
    final level = switch (record.level) {
      TelemetryLevel.debug => SentryLevel.debug,
      TelemetryLevel.info => SentryLevel.info,
      TelemetryLevel.warning => SentryLevel.warning,
      TelemetryLevel.error => SentryLevel.error,
      TelemetryLevel.fatal => SentryLevel.fatal,
    };
    final isError =
        record.error != null ||
        record.level == TelemetryLevel.error ||
        record.level == TelemetryLevel.fatal;
    if (isError) {
      await Sentry.captureException(
        record.error ?? record.message,
        stackTrace: record.stackTrace,
        withScope: (scope) {
          scope.level = level;
          for (final entry in record.context.entries) {
            scope.setContexts(entry.key, entry.value);
          }
        },
      );
      return;
    }
    await Sentry.addBreadcrumb(
      Breadcrumb(
        message: record.message,
        level: level,
        timestamp: record.timestamp,
        type: 'log',
      ),
    );
  }

  @override
  Future<void> flush() async {
    // sentry_dart does not expose a public flush; events are queued by the
    // SDK and drained on a best-effort basis at shutdown.
  }
}
