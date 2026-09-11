import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class StartupDiagnostics {
  static const _channel = MethodChannel('moe.alphaly.art3m1s/startup');

  static Future<void> _send(String method, String message) async {
    if (!Platform.isIOS) return;
    try {
      await _channel.invokeMethod<void>(method, message);
    } on MissingPluginException {
      // Older diagnostic hosts do not provide this channel.
    } on PlatformException {
      // Diagnostics must not prevent application initialization.
    }
  }

  static Future<T> step<T>(
    String name,
    FutureOr<T> Function() operation,
  ) async {
    if (!Platform.isIOS) return await operation();
    if (!kReleaseMode) await _send('stage', 'BEGIN $name');
    try {
      final result = await operation();
      if (!kReleaseMode) await _send('stage', 'END $name');
      return result;
    } catch (error, stack) {
      await _send('failed', '$name: $error\n$stack');
      rethrow;
    }
  }
}
