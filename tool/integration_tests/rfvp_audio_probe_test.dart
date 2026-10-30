import 'dart:ffi';
import 'dart:io';

import 'package:art3m1s/engine/backends/rfvp/core_rfvp_api.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final gameRoot = Platform.environment['RFVP_SMOKE_GAME'];
  final library = Platform.environment['ART3M1S_CORE_LIBRARY'];

  test(
    'probe RFVP audio commands',
    () {
      final api = CoreRfvpApiV1.tryLoad(DynamicLibrary.open(library!))!;
      final saveRoot = Directory.systemTemp.createTempSync('rfvp-audio-');
      final runtime = api.createRuntime(
        gameRoot: gameRoot!,
        saveRoot: saveRoot.path,
        width: 1280,
        height: 720,
        backend: 0,
      );
      try {
        expect(runtime, greaterThan(0), reason: '${api.lastStatus}');
        final counts = <int, int>{};
        for (var frame = 0; frame < 1200; frame++) {
          final status = api.step(runtime, 16);
          expect(status, art3m1sRfvpStatusOk);
          while (true) {
            final command = api.pollAudioCommand(runtime);
            if (command == null) break;
            counts.update(
              command.kind,
              (value) => value + 1,
              ifAbsent: () => 1,
            );
            if (command.kind == art3m1sRfvpAudioLoadEncoded) {
              final prefix = command.payload.take(16).toList();
              final extension =
                  command.payload.length >= 4 &&
                      command.payload[0] == 79 &&
                      command.payload[1] == 103 &&
                      command.payload[2] == 103 &&
                      command.payload[3] == 83
                  ? 'ogg'
                  : command.payload.length >= 4 &&
                        command.payload[0] == 82 &&
                        command.payload[1] == 73 &&
                        command.payload[2] == 70 &&
                        command.payload[3] == 70
                  ? 'wav'
                  : 'bin';
              File(
                '/tmp/rfvp_audio_probe_${command.streamId}.$extension',
              ).writeAsBytesSync(command.payload);
              stdout.writeln(
                'load stream=${command.streamId} encoded=${command.encodedKind} '
                'bytes=${command.payload.length} prefix=$prefix',
              );
            } else if (command.kind == art3m1sRfvpAudioPlay) {
              stdout.writeln(
                'play stream=${command.streamId} volume=${command.volume} '
                'repeat=${command.repeat} fade=${command.fadeMs}',
              );
            }
          }
        }
        stdout.writeln('RFVP audio command counts: $counts');
      } finally {
        api.destroyRuntime(runtime);
        saveRoot.deleteSync(recursive: true);
      }
    },
    skip: gameRoot == null || library == null
        ? 'RFVP_SMOKE_GAME or ART3M1S_CORE_LIBRARY is not set'
        : false,
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
