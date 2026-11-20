import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:art3m1s/engine/backends/artemis_v2_engine_runtime.dart';
import 'package:art3m1s/services/logger.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('v2 warns once per unsupported shader language', () async {
    const channel = MethodChannel('moe.alphaly.art3m1s/artemis_v2');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final saves = Directory.systemTemp.createTempSync('artemis-shader-diag-');
    final runtime = ArtemisV2EngineRuntime()..setSaveDir(saves.path);
    Map<String, Object?> event(int domain, int sequence, String metadata) => {
      'owner': '1',
      'domain': domain,
      'kind': 1,
      'epoch': '1',
      'sequence': '$sequence',
      'request': '0',
      'metadata': Uint8List.fromList(utf8.encode(metadata)),
      'blob': Uint8List(0),
    };
    messenger.setMockMethodCallHandler(channel, (call) async {
      return switch (call.method) {
        'open' => {
          'session': '1',
          'epoch': '1',
          'width': 4,
          'height': 4,
          'phase': 1,
          'waitFlags': 0,
          'exitRequested': false,
        },
        'poll' => [
          event(1, 1, '{"save_path":"save"}'),
          event(7, 2, '{"language":"hlsl","id":"a","key":"a.hlsl"}'),
          event(7, 3, '{"language":"hlsl","id":"b","key":"b.hlsl"}'),
          event(7, 4, '{"language":"glsl","id":"c","key":"c.frag"}'),
        ],
        'close' => null,
        _ => throw StateError('Unexpected method: ${call.method}'),
      };
    });
    try {
      final start = Log.entries.length;
      expect(await runtime.loadProjectBytes(Uint8List(0)), isTrue);
      final warnings = Log.entries.skip(start).map((entry) => entry.message);
      expect(
        warnings.where((text) => text.contains('support HLSL effects')),
        hasLength(1),
      );
      expect(
        warnings.where((text) => text.contains('support GLSL effects')),
        hasLength(1),
      );
    } finally {
      await runtime.close();
      messenger.setMockMethodCallHandler(channel, null);
      saves.deleteSync(recursive: true);
    }
  });

  for (final exitDuringOpen in [false, true]) {
    test(
      exitDuringOpen
          ? 'v2 exit waits for the pending native open to be cleaned up'
          : 'v2 serializes project changes through native close and open',
      () async {
        const channel = MethodChannel('moe.alphaly.art3m1s/artemis_v2');
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        final project = Directory.systemTemp.createTempSync('artemis-replace-');
        final runtime = ArtemisV2EngineRuntime()..setSaveDir(project.path);
        final closeStarted = Completer<void>();
        final allowClose = Completer<void>();
        final openStarted = Completer<void>();
        final allowOpen = Completer<void>();
        final closedSessions = <String>[];
        var opened = 0;
        const ini = '[WINDOWS]\nWIDTH=4\nHEIGHT=4\n';
        File('${project.path}/system.ini').writeAsStringSync(ini);
        messenger.setMockMethodCallHandler(channel, (call) async {
          switch (call.method) {
            case 'open':
              final id = ++opened;
              if (id == 2) {
                openStarted.complete();
                await allowOpen.future;
              }
              return {
                'session': '$id',
                'epoch': '1',
                'width': 4,
                'height': 4,
                'phase': 1,
                'waitFlags': 0,
                'exitRequested': false,
              };
            case 'poll':
              return [
                {
                  'owner': call.arguments['session'],
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
            case 'close':
              final session = call.arguments['session'] as String;
              if (session == '1') {
                closeStarted.complete();
                await allowClose.future;
              }
              closedSessions.add(session);
              return null;
            default:
              throw StateError('Unexpected method: ${call.method}');
          }
        });
        Future<Uint8List?>? preparing;
        Future<bool>? loading;
        Future<bool>? nextLoad;
        Future<void>? closing;
        try {
          final bytes = Uint8List.fromList(utf8.encode(ini));
          expect(await runtime.loadProjectBytes(bytes), isTrue);
          preparing = runtime.prepareProject(
            projectPath: project.path,
            isArchive: false,
            environmentPatchEnabled: false,
            platform: 'WINDOWS',
          );
          await closeStarted.future.timeout(const Duration(seconds: 2));
          loading = runtime.loadProjectBytes(bytes);
          await Future<void>.delayed(Duration.zero);
          expect(opened, 1);
          allowClose.complete();
          expect(await preparing, bytes);
          await openStarted.future.timeout(const Duration(seconds: 2));
          var shutdownFinished = false;
          if (exitDuringOpen) {
            closing = runtime.close().then<void>((_) {
              shutdownFinished = true;
            });
          } else {
            nextLoad = runtime.loadProjectBytes(bytes);
          }
          await Future<void>.delayed(Duration.zero);
          expect(opened, 2);
          expect(shutdownFinished, isFalse);
          expect(closedSessions, ['1']);
          allowOpen.complete();
          expect(await loading, !exitDuringOpen);
          if (exitDuringOpen) {
            await closing;
          } else {
            expect(await nextLoad, isTrue);
            expect(opened, 3);
          }
          expect(closedSessions, ['1', '2']);
        } finally {
          if (!allowClose.isCompleted) allowClose.complete();
          if (!allowOpen.isCompleted) allowOpen.complete();
          await preparing;
          await loading;
          await nextLoad;
          await runtime.close();
          messenger.setMockMethodCallHandler(channel, null);
          project.deleteSync(recursive: true);
        }
      },
    );
  }

  test(
    'v2 preserves frame timing and retries shutdown after pending IO',
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
      var exitWritePending = false;
      var exitWriteReplied = false;
      var finalWritePending = false;
      String? finalWriteStatus;
      var closedPending = false;
      var shutdownAttempts = 0;
      var closingSteps = 0;
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
            if (writePending || exitWritePending || finalWritePending) {
              final (request, key) = finalWritePending
                  ? ('3', 'system.dat')
                  : exitWritePending
                  ? ('2', 'exit-pending')
                  : ('1', '__autosave.dat');
              writePending = false;
              exitWritePending = false;
              finalWritePending = false;
              return [
                {
                  'owner': '1',
                  'domain': 3,
                  'kind': 4,
                  'epoch': '1',
                  'sequence': '${int.parse(request) + 1}',
                  'request': request,
                  'metadata': Uint8List.fromList(
                    utf8.encode(jsonEncode({'namespace': 'save', 'key': key})),
                  ),
                  'blob': Uint8List.fromList(utf8.encode('snapshot')),
                },
              ];
            }
            if (closedPending) {
              closedPending = false;
              return [
                {
                  'owner': '1',
                  'domain': 1,
                  'kind': 4,
                  'epoch': '1',
                  'sequence': '5',
                  'request': '0',
                  'metadata': Uint8List.fromList(
                    utf8.encode(
                      jsonEncode({
                        'save_status': 'failed',
                        'reason': finalWriteStatus,
                        'files_written': 1,
                      }),
                    ),
                  ),
                  'blob': Uint8List(0),
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
            final saving = closing && closingSteps++ == 0;
            if (saving) finalWritePending = true;
            if (closing && !saving) {
              expect(finalWriteStatus, 'denied');
              closedPending = true;
            }
            return {
              ...state,
              'phase': saving ? 3 : (closing ? 4 : 2),
              'waitFlags': blocked || saving ? 1 : 0,
              'backpressured': false,
              'stepFlags': 0,
            };
          case 'submit':
            for (final event in call.arguments['batch'] as List) {
              final wire = event as Map;
              final kind = (wire['domain'] as int, wire['kind'] as int);
              submitted.add(kind);
              if (kind == (3, 4)) {
                final reply = jsonDecode(
                  utf8.decode(wire['metadata'] as Uint8List),
                );
                if (wire['request'] == '3') {
                  finalWriteStatus = reply['status'] as String;
                } else {
                  expect(reply, {'status': 'ok'});
                  if (wire['request'] == '2') exitWriteReplied = true;
                }
              }
              if (kind == (1, 16)) {
                shutdownAttempts++;
                if (!exitWriteReplied) {
                  exitWritePending = true;
                  return false;
                }
                closing = true;
              }
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

        Directory('${saves.path}/save/system.dat').createSync();
        final logStart = Log.entries.length;
        await runtime.close();
        expect(shutdownAttempts, 2);
        expect(exitWriteReplied, isTrue);
        expect(closing, isTrue);
        expect(closingSteps, 2);
        expect(
          Log.entries.skip(logStart).map((entry) => entry.message),
          contains('[ArtemisV2] Final save failed: denied (1 files written)'),
        );
        expect(
          File('${saves.path}/save/exit-pending').readAsStringSync(),
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

  test(
    'v2 presents a video frame before applying its terminal status',
    () async {
      const channel = MethodChannel('moe.alphaly.art3m1s/artemis_v2');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final saves = Directory.systemTemp.createTempSync('artemis-video-batch-');
      final runtime = ArtemisV2EngineRuntime()..setSaveDir(saves.path);
      final videoOpened = Completer<void>();
      final calls = <String>[];
      const playback = '9223372036854775809';
      const state = {
        'session': '1',
        'epoch': '1',
        'width': 4,
        'height': 4,
        'phase': 1,
        'waitFlags': 0,
        'exitRequested': false,
      };
      var opening = true;
      var videoStarted = false;
      var steps = 0;
      Map<String, Object?> event(
        int domain,
        int kind,
        Map<String, Object?> metadata,
      ) => {
        'owner': '1',
        'domain': domain,
        'kind': kind,
        'epoch': '1',
        'sequence': '$domain',
        'request': '0',
        'metadata': Uint8List.fromList(utf8.encode(jsonEncode(metadata))),
        'blob': Uint8List(0),
      };
      messenger.setMockMethodCallHandler(channel, (call) async {
        switch (call.method) {
          case 'open':
            return state;
          case 'surface':
            return 0;
          case 'poll':
            if (!opening) return <Object>[];
            opening = false;
            return [
              event(1, 1, {'save_path': 'save'}),
              event(5, 2, {
                'op': 'play',
                'playback_id': playback,
                'key': 'clip.mp4',
                'loop': false,
                'skip': 0,
              }),
            ];
          case 'videoOpen':
            videoOpened.complete();
            return null;
          case 'videoPoll':
            final started = !videoStarted;
            videoStarted = true;
            return [
              {
                'playback': playback,
                'status': started ? 'started' : 'ended',
                if (started) ...{'texture': 1, 'width': 4, 'height': 4},
              },
            ];
          case 'submit':
            for (final message in call.arguments['batch'] as List) {
              final wire = message as Map;
              final data = jsonDecode(
                utf8.decode(wire['metadata'] as Uint8List),
              );
              expect(data['playback_id'], playback);
              calls.add(data['status'] as String);
            }
            return true;
          case 'step':
            steps++;
            return {...state, 'backpressured': false, 'stepFlags': 0};
          case 'present':
            calls.add('present');
            return '1';
          case 'videoSuspend' || 'close':
            return null;
          default:
            throw StateError('Unexpected method: ${call.method}');
        }
      });
      try {
        runtime.media.configureAssetReader((_) => Uint8List(1));
        expect(await runtime.loadProjectBytes(Uint8List(0)), isTrue);
        expect(await runtime.enableSharedTexture(), 0);
        await videoOpened.future.timeout(const Duration(seconds: 2));

        await runtime.advanceTextureBatch([16, 17, 17]);
        expect(calls, ['started', 'present']);
        expect(steps, 3);
        expect(runtime.media.videoPlayback.value, isNotNull);

        await runtime.advanceTextureBatch([16]);
        expect(calls, ['started', 'present', 'ended', 'present']);
        expect(steps, 4);
        expect(runtime.media.videoPlayback.value, isNull);
      } finally {
        await runtime.close();
        messenger.setMockMethodCallHandler(channel, null);
        saves.deleteSync(recursive: true);
      }
    },
  );
}
