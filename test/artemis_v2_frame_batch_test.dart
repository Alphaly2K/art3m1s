import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:art3m1s/engine/backends/artemis_v2_engine_runtime.dart';
import 'package:art3m1s/services/logger.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('v2 prewarms GLSL and allows HLSL with a .txt suffix', () async {
    const channel = MethodChannel('moe.alphaly.art3m1s/artemis_v2');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final project = Directory.systemTemp.createTempSync('artemis-sidecars-');
    final runtime = ArtemisV2EngineRuntime()..setSaveDir(project.path);
    const ini = '[WINDOWS]\nWIDTH=4\nHEIGHT=4\n';
    const glsl = 'void main() { gl_FragColor = vec4(1.0); }';
    File('${project.path}/system.ini').writeAsStringSync(ini);
    final patches = Directory('${project.path}/Patches')..createSync();
    File('${patches.path}/Paint.FRAG').writeAsStringSync(glsl);
    File('${patches.path}/Effect.txt').writeAsStringSync('test HLSL source');
    Map<Object?, Object?>? options;
    messenger.setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'open':
          options = call.arguments as Map<Object?, Object?>;
          return {
            'session': '1',
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
        case 'close':
          return null;
        default:
          throw StateError('Unexpected method: ${call.method}');
      }
    });
    try {
      final bytes = await runtime.prepareProject(
        projectPath: '${project.path}/root.pfs',
        isArchive: true,
        environmentPatchEnabled: false,
        platform: 'WINDOWS',
      );
      expect(await runtime.loadProjectBytes(bytes!), isTrue);
      expect(options?['mixedShaders'], isTrue);
      expect(options?['glslSources'], [utf8.encode(glsl)]);
    } finally {
      await runtime.close();
      messenger.setMockMethodCallHandler(channel, null);
      project.deleteSync(recursive: true);
    }
  });

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

  test('v2 logs Lua print bytes only for the current epoch', () async {
    const channel = MethodChannel('moe.alphaly.art3m1s/artemis_v2');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final saves = Directory.systemTemp.createTempSync('artemis-script-print-');
    final runtime = ArtemisV2EngineRuntime()..setSaveDir(saves.path);
    final debug = Log.debugEnabled;
    Map<String, Object?> event({
      required int domain,
      required int kind,
      required String epoch,
      required String sequence,
      String metadata = '{}',
      List<int> blob = const [],
    }) => {
      'owner': '1',
      'domain': domain,
      'kind': kind,
      'epoch': epoch,
      'sequence': sequence,
      'request': '0',
      'metadata': Uint8List.fromList(utf8.encode(metadata)),
      'blob': Uint8List.fromList(blob),
    };
    messenger.setMockMethodCallHandler(channel, (call) async {
      return switch (call.method) {
        'open' => {
          'session': '1',
          'epoch': '2',
          'width': 4,
          'height': 4,
          'phase': 1,
          'waitFlags': 0,
          'exitRequested': false,
        },
        'poll' => [
          event(
            domain: 1,
            kind: 1,
            epoch: '2',
            sequence: '1',
            metadata: '{"save_path":"save"}',
          ),
          event(domain: 7, kind: 2, epoch: '1', sequence: '2', blob: [97]),
          event(domain: 7, kind: 2, epoch: '2', sequence: '3', blob: [98, 255]),
        ],
        'close' => null,
        _ => throw StateError('Unexpected method: ${call.method}'),
      };
    });
    try {
      Log.setDebugEnabled(true);
      final start = Log.entries.length;
      expect(await runtime.loadProjectBytes(Uint8List(0)), isTrue);
      expect(
        Log.entries
            .skip(start)
            .map((entry) => entry.message)
            .where((message) => message.startsWith('[ArtemisV2] [Lua] ')),
        ['[ArtemisV2] [Lua] b\uFFFD'],
      );
    } finally {
      Log.setDebugEnabled(debug);
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

  test('v2 saves the old project before opening the next one', () async {
    const channel = MethodChannel('moe.alphaly.art3m1s/artemis_v2');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final saves = Directory.systemTemp.createTempSync('artemis-switch-save-');
    final runtime = ArtemisV2EngineRuntime()..setSaveDir(saves.path);
    final shutdownSent = Completer<void>();
    final allowShutdown = Completer<void>();
    final saving = Completer<void>();
    final acknowledge = Completer<void>();
    final calls = <String>[];
    final opening = <String>{};
    var opens = 0;
    var writePending = false;
    var written = false;
    var closedPending = false;
    Map<String, Object?> state(String session, int phase) => {
      'session': session,
      'epoch': '1',
      'width': 4,
      'height': 4,
      'phase': phase,
      'waitFlags': phase == 3 ? 1 : 0,
      'exitRequested': false,
      'stepFlags': 0,
      'backpressured': false,
    };
    Map<String, Object?> event(
      String session,
      int domain,
      int kind,
      int sequence,
      Map<String, Object?> metadata, {
      String request = '0',
      String blob = '',
    }) => {
      'owner': session,
      'domain': domain,
      'kind': kind,
      'epoch': '1',
      'sequence': '$sequence',
      'request': request,
      'metadata': Uint8List.fromList(utf8.encode(jsonEncode(metadata))),
      'blob': Uint8List.fromList(utf8.encode(blob)),
    };
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'open') {
        final session = '${++opens}';
        calls.add('open:$session');
        opening.add(session);
        return state(session, opens == 1 ? 2 : 1);
      }
      final session = call.arguments['session'] as String;
      switch (call.method) {
        case 'poll':
          if (opening.remove(session)) {
            return [
              event(session, 1, 1, 1, {'save_path': 'save-$session'}),
            ];
          }
          if (writePending) {
            writePending = false;
            return [
              event(
                session,
                3,
                4,
                2,
                {'namespace': 'save', 'key': 'saveg.dat'},
                request: '1',
                blob: 'old project state',
              ),
            ];
          }
          if (closedPending) {
            closedPending = false;
            return [
              event(session, 1, 4, 3, {'save_status': 'written'}),
            ];
          }
          return <Object>[];
        case 'submit':
          final message = (call.arguments['batch'] as List).single as Map;
          expect(session, '1');
          if (message['domain'] == 1 && message['kind'] == 16) {
            calls.add('shutdown:$session');
            shutdownSent.complete();
            await allowShutdown.future;
          } else {
            expect(message['request'], '1');
            expect(jsonDecode(utf8.decode(message['metadata'] as Uint8List)), {
              'status': 'ok',
            });
            calls.add('write:$session');
            saving.complete();
            await acknowledge.future;
            written = true;
          }
          return true;
        case 'step':
          expect(call.arguments['backgroundAutosave'], isNull);
          if (written) {
            closedPending = true;
            return state(session, 4);
          }
          writePending = true;
          return state(session, 3);
        case 'close':
          calls.add('close:$session');
          return null;
        default:
          throw StateError('Unexpected method: ${call.method}');
      }
    });
    Future<bool>? switching;
    try {
      expect(await runtime.loadProjectBytes(Uint8List(0)), isTrue);
      switching = runtime.loadProjectBytes(Uint8List(0));
      await shutdownSent.future.timeout(const Duration(seconds: 2));
      runtime.notifyLifecycle(1);
      await Future<void>.delayed(Duration.zero);
      expect(calls, ['open:1', 'shutdown:1']);
      allowShutdown.complete();
      await saving.future.timeout(const Duration(seconds: 2));
      expect(calls, ['open:1', 'shutdown:1', 'write:1']);
      expect(
        File('${saves.path}/save-1/saveg.dat').readAsStringSync(),
        'old project state',
      );
      acknowledge.complete();
      expect(await switching, isTrue);
      expect(calls, ['open:1', 'shutdown:1', 'write:1', 'close:1', 'open:2']);
      expect(File('${saves.path}/save-2/saveg.dat').existsSync(), isFalse);
    } finally {
      if (!allowShutdown.isCompleted) allowShutdown.complete();
      if (!acknowledge.isCompleted) acknowledge.complete();
      await switching;
      await runtime.close();
      messenger.setMockMethodCallHandler(channel, null);
      saves.deleteSync(recursive: true);
    }
  });

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

  for (final pollFails in [false, true]) {
    test(
      pollFails
          ? 'v2 continues to step after a native video poll fails'
          : 'v2 presents a video frame before applying its terminal status',
      () async {
        const channel = MethodChannel('moe.alphaly.art3m1s/artemis_v2');
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        final saves = Directory.systemTemp.createTempSync(
          'artemis-video-batch-',
        );
        final runtime = ArtemisV2EngineRuntime()..setSaveDir(saves.path);
        final videoOpened = Completer<void>();
        final calls = <String>[];
        final closedVideos = <String>[];
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
        var videoPolls = 0;
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
              videoPolls++;
              if (videoStarted && pollFails) {
                throw PlatformException(code: 'video_poll_failed');
              }
              final started = !videoStarted;
              videoStarted = true;
              return [
                {
                  'playback': playback,
                  'status': started ? 'started' : 'ended',
                  if (started) ...{'texture': 1, 'width': 4, 'height': 4},
                },
              ];
            case 'videoClose':
              closedVideos.add(call.arguments['playback'] as String);
              return null;
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
          expect(calls, [
            'started',
            'present',
            pollFails ? 'failed' : 'ended',
            'present',
          ]);
          expect(steps, 4);
          expect(runtime.media.videoPlayback.value, isNull);
          expect(closedVideos, pollFails ? [playback] : isEmpty);
          if (pollFails) {
            await runtime.advanceTextureBatch([16]);
            expect(calls, [
              'started',
              'present',
              'failed',
              'present',
              'present',
            ]);
            expect(steps, 5);
            expect(videoPolls, 2);
          }
        } finally {
          await runtime.close();
          messenger.setMockMethodCallHandler(channel, null);
          saves.deleteSync(recursive: true);
        }
      },
    );
  }
}
