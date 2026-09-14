import 'dart:async';

/// Serializes access to the platform's process-wide shared-texture channel.
///
/// Engine runtimes remain independent, but the current native Host exposes one
/// presentation surface. Acquiring it first revokes the previous owner so a
/// frozen/suspended runtime can never retain a stale native surface pointer.
abstract final class SharedTextureSessionCoordinator {
  static Future<void> _tail = Future<void>.value();
  static Object? _owner;
  static Future<void> Function()? _revokeOwner;

  /// Acquires the process-wide surface and keeps the ownership hand-off
  /// serialized until [operation] has finished creating/attaching it.
  static Future<T> runWithOwnership<T>(
    Object owner,
    Future<void> Function() revoke,
    Future<T> Function() operation,
  ) {
    return _enqueueValue(() async {
      if (!identical(_owner, owner)) {
        final previousRevoke = _revokeOwner;
        _owner = null;
        _revokeOwner = null;
        if (previousRevoke != null) await previousRevoke();
      }
      _owner = owner;
      _revokeOwner = revoke;
      return operation();
    });
  }

  static Future<void> release(Object owner) {
    return _enqueue(() async {
      if (!identical(_owner, owner)) return;
      final revoke = _revokeOwner;
      _owner = null;
      _revokeOwner = null;
      if (revoke != null) await revoke();
    });
  }

  /// Drops ownership after the caller has already detached/released its
  /// surface synchronously (used by synchronous runtime shutdown paths).
  static Future<void> abandon(Object owner) {
    return _enqueue(() async {
      if (!identical(_owner, owner)) return;
      _owner = null;
      _revokeOwner = null;
    });
  }

  static Future<void> _enqueue(Future<void> Function() operation) {
    final next = _tail.then((_) => operation(), onError: (_) => operation());
    _tail = next.catchError((_) {});
    return next;
  }

  static Future<T> _enqueueValue<T>(Future<T> Function() operation) {
    final next = _tail.then((_) => operation(), onError: (_) => operation());
    _tail = next.then<void>((_) {}, onError: (_) {});
    return next;
  }
}
