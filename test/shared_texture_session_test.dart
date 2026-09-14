import 'dart:async';

import 'package:art3m1s/engine/shared_texture_session.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('surface hand-off waits for create and revokes the old owner', () async {
    final firstOwner = Object();
    final secondOwner = Object();
    final allowFirstCreate = Completer<void>();
    final events = <String>[];

    final first = SharedTextureSessionCoordinator.runWithOwnership<void>(
      firstOwner,
      () async => events.add('revoke first'),
      () async {
        events.add('create first');
        await allowFirstCreate.future;
      },
    );
    final second = SharedTextureSessionCoordinator.runWithOwnership<void>(
      secondOwner,
      () async => events.add('revoke second'),
      () async => events.add('create second'),
    );

    await Future<void>.delayed(Duration.zero);
    expect(events, ['create first']);
    allowFirstCreate.complete();
    await Future.wait([first, second]);
    expect(events, ['create first', 'revoke first', 'create second']);

    await SharedTextureSessionCoordinator.release(secondOwner);
    expect(events.last, 'revoke second');
  });
}
