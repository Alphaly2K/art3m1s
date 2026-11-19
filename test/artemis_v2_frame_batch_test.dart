import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:art3m1s/engine/backends/artemis_v2_engine_runtime.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'v2 retains the frame clock across IO and background autosave',
    () async {
      const channel = MethodChannel('moe.alphaly.art3m1s/artemis_v2');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final saves = Directory.systemTemp.createTempSync('artemis-frame-batch-');
      final runtime = ArtemisV2EngineRuntime()..setSaveDir(saves.path);
      final frames = <(int, int)>[];
      final autosaveFrames = <(int, int)>[];
      final submitted = <(int, int)>[];
      final submitStarted = Completer<void>();
      final releaseSubmit = Completer<void>();
      final autosaveStarted = Completer<void>();
      final releaseAutosave = Completer<void>();
      var opening = true;
      var blocked = false;
      var holdSubmit = false;
      var writePending = false;
      var closing = false;
      var presentations = 0;
      const state = {
        'session': '1',
        'epoch': '1',
        'width': 4,
        'height': 4,
        'phase': 1,
        'waitFlags': 0,
        'exitRequested': false,
      };
      messenger.setMockMethodCallHandler(channel, (call) async {
        switch (call.method) {
          case 'open':
            return state;
          case 'surface':
            return 0;
          case 'poll':
            if (writePending) {
              writePending = false;
              return [
                {
                  'owner': '1',
                  'domain': 3,
                  'kind': 4,
                  'epoch': '1',
                  'sequence': '2',
                  'request': '1',
                  'metadata': Uint8List.fromList(
                    utf8.encode('{"namespace":"save","key":"__autosave.dat"}'),
                  ),
                  'blob': Uint8List.fromList(utf8.encode('snapshot')),
                },
              ];
            }
            if (!opening) return <Object>[];
            opening = false;
            return [
              {
                'owner': '1',
                'domain': 1,
                'kind': 1,
                'epoch': '1',
                'sequence': '1',
                'request': '0',
                'metadata': Uint8List.fromList(
                  utf8.encode('{"save_path":"save"}'),
                ),
                'blob': Uint8List(0),
              },
            ];
          case 'step':
            final frame = (
              call.arguments['frame'] as int,
              call.arguments['monotonicNS'] as int,
            );
            if (call.arguments['backgroundAutosave'] == true) {
              autosaveFrames.add(frame);
              final first = !autosaveStarted.isCompleted;
              if (first) {
                autosaveStarted.complete();
                await releaseAutosave.future;
                writePending = true;
              }
              return {
                ...state,
                'phase': 2,
                'waitFlags': first ? 1 : 0,
                'backpressured': false,
                'stepFlags': 0,
              };
            }
            frames.add(frame);
            return {
              ...state,
              'phase': closing ? 4 : 2,
              'waitFlags': blocked ? 1 : 0,
              'backpressured': false,
              'stepFlags': 0,
            };
          case 'submit':
            for (final event in call.arguments['batch'] as List) {
              final wire = event as Map;
              final kind = (wire['domain'] as int, wire['kind'] as int);
              submitted.add(kind);
              if (kind == (3, 4)) {
                expect(jsonDecode(utf8.decode(wire['metadata'] as Uint8List)), {
                  'status': 'ok',
                });
              }
              if (kind == (1, 16)) closing = true;
            }
            if (holdSubmit) {
              holdSubmit = false;
              submitStarted.complete();
              await releaseSubmit.future;
            }
            return true;
          case 'present':
            presentations++;
            return frames.last.$1.toString();
          case 'close':
            return null;
          default:
            throw StateError('Unexpected method: ${call.method}');
        }
      });
      try {
        expect(await runtime.loadProjectBytes(Uint8List(0)), isTrue);
        expect(await runtime.enableSharedTexture(), 0);

        expect(await runtime.advanceTextureBatch([16, 17, 17]), isTrue);
        expect(frames, [(1, 16000000), (2, 33000000), (3, 50000000)]);
        expect(presentations, 1);

        frames.clear();
        blocked = true;
        await runtime.advanceTextureBatch([16, 17, 17]);
        expect(frames, [(4, 66000000)]);

        blocked = false;
        await runtime.advanceTextureBatch([17, 17]);
        expect(frames, [(4, 66000000), (4, 66000000), (5, 83000000)]);
        expect(presentations, 3);

        frames.clear();
        holdSubmit = true;
        runtime.feedKey(70, true);
        final advancing = runtime.advanceTextureBatch([16, 17]);
        await submitStarted.future.timeout(const Duration(seconds: 2));
        runtime.notifyLifecycle(1);
        releaseSubmit.complete();
        expect(await advancing, isFalse);
        expect(frames, isEmpty);
        expect(presentations, 3);

        await autosaveStarted.future.timeout(const Duration(seconds: 2));
        runtime.notifyLifecycle(2);
        final resumed = runtime.advanceTextureBatch([17]);
        expect(frames, isEmpty);
        releaseAutosave.complete();
        expect(await resumed, isTrue);
        expect(autosaveFrames, [(6, 83000000), (6, 83000000)]);
        expect(frames, [(6, 100000000)]);
        expect(submitted, [(2, 1), (3, 4), (2, 4)]);
        expect(
          File('${saves.path}/save/__autosave.dat').readAsStringSync(),
          'snapshot',
        );
      } finally {
        if (!releaseSubmit.isCompleted) releaseSubmit.complete();
        if (!releaseAutosave.isCompleted) releaseAutosave.complete();
        await runtime.close();
        messenger.setMockMethodCallHandler(channel, null);
        saves.deleteSync(recursive: true);
      }
    },
  );
}
