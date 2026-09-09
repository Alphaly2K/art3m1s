import 'package:art3m1s/services/vndb_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'offline VNDB failure stops retries and keeps import fallback available',
    () async {
      var attempts = 0;
      final result = await VndbService.lookupGameWith('Game - Another Title', (
        _,
      ) async {
        attempts++;
        return const VndbQueryAttempt(tryAnotherCandidate: false);
      });

      expect(result, isNull);
      expect(attempts, 1);
    },
  );

  test('reachable VNDB miss may try the next cleaned title', () async {
    var attempts = 0;
    final result = await VndbService.lookupGameWith('Game - Another Title', (
      candidate,
    ) async {
      attempts++;
      if (attempts == 1) {
        return const VndbQueryAttempt(tryAnotherCandidate: true);
      }
      return const VndbQueryAttempt(
        info: VndbGameInfo(title: 'Matched'),
        tryAnotherCandidate: false,
      );
    });

    expect(result?.title, 'Matched');
    expect(attempts, 2);
  });
}
