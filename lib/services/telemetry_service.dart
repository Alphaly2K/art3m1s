import 'dart:async';

/// Provider-neutral severity level for telemetry records.
enum TelemetryLevel { debug, info, warning, error, fatal }

/// Immutable record delivered to telemetry sinks.
class TelemetryRecord {
  const TelemetryRecord({
    required this.timestamp,
    required this.level,
    required this.message,
    this.error,
    this.stackTrace,
    this.context = const <String, Object?>{},
  });

  final DateTime timestamp;
  final TelemetryLevel level;
  final String message;
  final Object? error;
  final StackTrace? stackTrace;
  final Map<String, Object?> context;
}

/// Destination for logs and errors.
///
/// Implementations may be remote providers, local files, or test recorders.
/// A sink must not throw synchronously; failures are isolated by
/// [TelemetryService].
abstract interface class TelemetrySink {
  String get name;

  FutureOr<void> capture(TelemetryRecord record);

  FutureOr<void> flush();
}

/// Dispatches application events to registered telemetry sinks.
///
/// The service is provider-neutral. Bugly, Sentry, or a custom uploader can be
/// added later without changing logger call sites.
class TelemetryService {
  TelemetryService();

  static final TelemetryService instance = TelemetryService();

  final List<TelemetrySink> _sinks = <TelemetrySink>[];
  bool _enabled = true;

  bool get enabled => _enabled;

  List<String> get sinkNames =>
      List.unmodifiable(_sinks.map((sink) => sink.name));

  void registerSink(TelemetrySink sink) {
    _sinks.removeWhere((existing) => existing.name == sink.name);
    _sinks.add(sink);
  }

  void unregisterSink(String name) {
    _sinks.removeWhere((sink) => sink.name == name);
  }

  void setEnabled(bool enabled) {
    _enabled = enabled;
  }

  void captureLog({
    required String level,
    required String message,
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?> context = const <String, Object?>{},
  }) {
    _dispatch(
      TelemetryRecord(
        timestamp: DateTime.now(),
        level: _levelFromLogCode(level),
        message: TelemetrySanitizer.redact(message),
        error: error,
        stackTrace: stackTrace,
        context: context,
      ),
    );
  }

  void captureError(
    Object error, {
    StackTrace? stackTrace,
    String? message,
    TelemetryLevel level = TelemetryLevel.error,
    Map<String, Object?> context = const <String, Object?>{},
  }) {
    _dispatch(
      TelemetryRecord(
        timestamp: DateTime.now(),
        level: level,
        message: TelemetrySanitizer.redact(message ?? error.toString()),
        error: error,
        stackTrace: stackTrace,
        context: context,
      ),
    );
  }

  Future<void> flush() async {
    if (!_enabled || _sinks.isEmpty) return;
    final sinks = List<TelemetrySink>.of(_sinks);
    await Future.wait(
      sinks.map(
        (sink) => Future<void>.sync(sink.flush).catchError((Object _) {}),
      ),
    );
  }

  void _dispatch(TelemetryRecord record) {
    if (!_enabled ||
        _sinks.isEmpty ||
        Zone.current[_telemetrySinkZone] == true) {
      return;
    }

    for (final sink in List<TelemetrySink>.of(_sinks)) {
      unawaited(_captureSafely(sink, record));
    }
  }

  Future<void> _captureSafely(
    TelemetrySink sink,
    TelemetryRecord record,
  ) async {
    final future =
        runZonedGuarded(
          () async => sink.capture(record),
          (Object _, StackTrace _) {},
          zoneValues: <Object, Object?>{_telemetrySinkZone: true},
        ) ??
        Future<void>.value();
    await future.catchError((Object _) {});
  }

  static TelemetryLevel _levelFromLogCode(String level) {
    return switch (level.toUpperCase()) {
      'D' => TelemetryLevel.debug,
      'W' => TelemetryLevel.warning,
      'E' => TelemetryLevel.error,
      'F' => TelemetryLevel.fatal,
      _ => TelemetryLevel.info,
    };
  }
}

const Object _telemetrySinkZone = Object();

/// Removes common credentials and filesystem paths before telemetry capture.
class TelemetrySanitizer {
  TelemetrySanitizer._();

  static final RegExp _unixPath = RegExp(
    r'(?:(?:/Users|/home|/private|/var|/Volumes|/tmp)/[^ \r\n\t"'
    ']*)',
  );
  static final RegExp _windowsPath = RegExp(
    r'(?:[A-Za-z]:\\[^ \r\n\t"'
    ']*)',
  );
  static final RegExp _bearerToken = RegExp(
    r'(Bearer\s+)[A-Za-z0-9._~+/=-]+',
    caseSensitive: false,
  );
  static final RegExp _namedSecret = RegExp(
    r'((?:api[_-]?key|access[_-]?token|refresh[_-]?token|token|secret|password)\s*[:=]\s*)[^\s,;&]+',
    caseSensitive: false,
  );

  static String redact(String input) {
    var output = input
        .replaceAll(_unixPath, '<redacted-path>')
        .replaceAll(_windowsPath, '<redacted-path>')
        .replaceAllMapped(
          _bearerToken,
          (match) => '${match.group(1)}<redacted>',
        )
        .replaceAllMapped(
          _namedSecret,
          (match) => '${match.group(1)}<redacted>',
        );
    return output;
  }
}
