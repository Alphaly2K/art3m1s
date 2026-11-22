import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:art3m1s/engine/backends/artemis_v2_engine_runtime.dart';
import 'package:art3m1s/engine/engine_runtime.dart';
import 'package:art3m1s/services/logger.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('v2 forwards one-based mouse buttons with Artemis key codes', () async {
    const channel = MethodChannel('moe.alphaly.art3m1s/artemis_v2');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final saves = Directory.systemTemp.createTempSync('artemis-mouse-input-');
    final runtime = ArtemisV2EngineRuntime()..setSaveDir(saves.path);
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
    final forwarded = <Object?>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'open':
          return state;
        case 'step':
          return {...state, 'backpressured': false, 'stepFlags': 0};
        case 'poll':
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
        case 'submit':
          for (final message in call.arguments['batch'] as List) {
            expect(message['domain'], 2);
            expect(message['kind'], 1);
            forwarded.add(
              jsonDecode(utf8.decode(message['metadata'] as Uint8List)),
            );
          }
          return true;
        case 'close':
          return null;
        default:
          throw StateError('Unexpected method: ${call.method}');
      }
    });
    try {
      expect(await runtime.loadProjectBytes(Uint8List(0)), isTrue);
      for (final button in [1, 2, 3]) {
        runtime.feedMouseButton(button, true);
        runtime.feedMouseButton(button, false);
      }
      runtime.feedClick();
      await runtime.advanceTexture(16);
      expect(forwarded, [
        for (final code in [1, 2, 4, 1]) ...[
          {'code': code, 'down': true},
          {'code': code, 'down': false},
        ],
      ]);
      forwarded.clear();
      for (final button in [0, 4]) {
        runtime.feedMouseButton(button, true);
        runtime.feedMouseButton(button, false);
      }
      await runtime.advanceTexture(16);
      expect(forwarded, isEmpty);
    } finally {
      await runtime.close();
      messenger.setMockMethodCallHandler(channel, null);
      saves.deleteSync(recursive: true);
    }
  });

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
        case 'hasDxvkRuntime':
          return false;
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
      expect(options?['hlslOnDemand'], isNull);
      expect(options?['hlslEffects'], isNull);
    } finally {
      await runtime.close();
      messenger.setMockMethodCallHandler(channel, null);
      project.deleteSync(recursive: true);
    }
  });

  test('v2 loads ADE2 after prewarm and runtime shader failures', () async {
    const channel = MethodChannel('moe.alphaly.art3m1s/artemis_v2');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final project = Directory.systemTemp.createTempSync('artemis-sidecars-');
    final runtime = ArtemisV2EngineRuntime()..setSaveDir(project.path);
    File('${project.path}/system.ini').writeAsStringSync('[WINDOWS]\n');
    final sidecars = Directory('${project.path}/artemis-shaders/ade2')
      ..createSync(recursive: true);
    File sidecar(String key, List<int> source) =>
        File('${sidecars.path}/$key.${sha256.convert(source)}.ade2');
    for (var index = 0; index < 256; index++) {
      final key = 'prewarm-$index.hlsl';
      final bytes = utf8.encode('warmup $index');
      File('${project.path}/$key').writeAsBytesSync(bytes);
      sidecar(key, bytes).writeAsStringSync('prewarmed ADE2');
    }
    final rejectedKeys = List.generate(256, (i) => 'late-rejected-$i.txt');
    const key = 'late.txt';
    final reads = [
      rejectedKeys.first,
      ...rejectedKeys,
      key,
      key,
      rejectedKeys.first,
    ];
    final source = utf8.encode('HLSL read after prewarm');
    final artifact = utf8.encode('runtime ADE2');
    final rejectedArtifact = utf8.encode('rejected ADE2');
    var rejected = 0;
    var accepted = 0;
    Map<String, Object> event(
      int sequence,
      int domain,
      int kind,
      Map<String, String> metadata, {
      String request = '0',
    }) => {
      'owner': '1',
      'domain': domain,
      'kind': kind,
      'epoch': '1',
      'sequence': '$sequence',
      'request': request,
      'metadata': Uint8List.fromList(utf8.encode(jsonEncode(metadata))),
      'blob': Uint8List(0),
    };
    messenger.setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'hasDxvkRuntime':
          return true;
        case 'open':
          expect(call.arguments['hlslOnDemand'], isTrue);
          expect(call.arguments['hlslEffects'], hasLength(256));
          File('${project.path}/$key').writeAsBytesSync(source);
          sidecar(key, source).writeAsBytesSync(artifact);
          for (final rejectedKey in rejectedKeys) {
            File('${project.path}/$rejectedKey').writeAsBytesSync(source);
            sidecar(rejectedKey, source).writeAsBytesSync(rejectedArtifact);
          }
          return {
            'session': '1',
            'epoch': '1',
            'width': 4,
            'height': 4,
            'phase': 1,
            'waitFlags': 0,
            'exitRequested': false,
            'dxvk': true,
            'preparedHlsl': List.generate(256, (index) => index),
          };
        case 'poll':
          return [
            event(1, 1, 1, {'save_path': 'save'}),
            for (var i = 0; i < reads.length; i++) ...[
              event(2 + 2 * i, 3, 1, {
                'key': reads[i],
                'namespace': 'asset',
              }, request: '${1 + 2 * i}'),
              event(3 + 2 * i, 3, 2, {
                'key': reads[i],
                'namespace': 'asset',
                'revision': '${1 + i}',
                'offset': '0',
                'length': '${source.length}',
                'shader_language': 'hlsl',
              }, request: '${2 + 2 * i}'),
            ],
          ];
        case 'prepareHlsl':
          expect(call.arguments['source'], source);
          final input = call.arguments['artifact'] as Uint8List;
          if (utf8.decode(input) == 'rejected ADE2') {
            rejected++;
            throw PlatformException(code: 'invalid_ade2');
          }
          expect(input, artifact);
          accepted++;
          return null;
        case 'close':
          return null;
        default:
          throw StateError('Unexpected method: ${call.method}');
      }
    });
    try {
      final ini = await runtime.prepareProject(
        projectPath: '${project.path}/root.pfs',
        isArchive: true,
        environmentPatchEnabled: false,
        platform: 'WINDOWS',
      );
      expect(await runtime.loadProjectBytes(ini!), isTrue);
      expect(rejected, rejectedKeys.length);
      expect(accepted, 1);
    } finally {
      await runtime.close();
      messenger.setMockMethodCallHandler(channel, null);
      project.deleteSync(recursive: true);
    }
  });

  test('v2 can step after Core rejects an invalid font override', () async {
    const channel = MethodChannel('moe.alphaly.art3m1s/artemis_v2');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final saves = Directory.systemTemp.createTempSync('artemis-font-');
    final runtime = ArtemisV2EngineRuntime()
      ..setSaveDir(saves.path)
      ..setFontOverride(Uint8List.fromList([0, 1, 2]));
    const state = {
      'session': '1',
      'epoch': '1',
      'width': 4,
      'height': 4,
      'phase': 1,
      'waitFlags': 0,
      'exitRequested': false,
    };
    var opened = false;
    var rejected = false;
    var stepped = false;
    messenger.setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'open':
          return state;
        case 'poll':
          if (opened) return [];
          opened = true;
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
        case 'submit':
          final batch = call.arguments['batch'] as List<Object?>;
          final message = batch.single as Map<Object?, Object?>;
          if (message['kind'] == 17) {
            expect(message['blob'], [0, 1, 2]);
            rejected = true;
            throw PlatformException(code: 'artemis_v2');
          }
          return true;
        case 'step':
          stepped = true;
          return {...state, 'backpressured': false, 'stepFlags': 0};
        case 'close':
          return null;
        default:
          throw StateError('Unexpected method: ${call.method}');
      }
    });
    try {
      expect(await runtime.loadProjectBytes(Uint8List(0)), isTrue);
      expect(rejected, isTrue);
      await runtime.advanceTexture(16);
      expect(stepped, isTrue);
    } finally {
      await runtime.close();
      messenger.setMockMethodCallHandler(channel, null);
      saves.deleteSync(recursive: true);
    }
  });

  test('v2 redraws at the stage size after a failed upscale request', () async {
    const channel = MethodChannel('moe.alphaly.art3m1s/artemis_v2');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final saves = Directory.systemTemp.createTempSync('artemis-surface-');
    final runtime = ArtemisV2EngineRuntime()..setSaveDir(saves.path);
    final requests = <(int, int, double?)>[];
    final resizeEntered = Completer<void>();
    final allowResize = Completer<void>();
    var opening = true;
    var presentations = 0;
    const state = {
      'session': '1',
      'epoch': '1',
      'width': 4,
      'height': 4,
      'phase': 1,
      'waitFlags': 0,
      'exitRequested': false,
      'spatialUpscaling': true,
    };
    messenger.setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'open':
          return state;
        case 'poll':
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
        case 'surface':
          final width = call.arguments['width'] as int;
          requests.add((
            width,
            call.arguments['height'] as int,
            call.arguments['spatialScale'] as double?,
          ));
          if (width == 8) throw PlatformException(code: 'surface_failed');
          if (width == 16) {
            resizeEntered.complete();
            await allowResize.future;
            throw PlatformException(code: 'stale_surface_failed');
          }
          return requests.length;
        case 'step':
          return {...state, 'backpressured': false, 'stepFlags': 0};
        case 'present':
          return '${++presentations}';
        case 'close':
          return null;
        default:
          throw StateError('Unexpected method: ${call.method}');
      }
    });
    try {
      expect(await runtime.loadProjectBytes(Uint8List(0)), isTrue);
      expect(await runtime.enableSharedTexture(), 1);
      expect(
        await runtime.enableSharedTexture(outputWidth: 8, outputHeight: 8),
        3,
      );
      expect(runtime.sharedTextureWidth, 4);
      expect(runtime.sharedTextureHeight, 4);
      expect(await runtime.advanceTexture(16), isTrue);
      expect(presentations, 1);

      final earlier = runtime.enableSharedTexture(
        outputWidth: 16,
        outputHeight: 16,
      );
      await resizeEntered.future.timeout(const Duration(seconds: 2));
      expect(
        await runtime.enableSharedTexture(outputWidth: 6, outputHeight: 6),
        5,
      );
      allowResize.complete();
      expect(await earlier, isNull);
      expect(runtime.sharedTextureId, 5);
      expect(runtime.sharedTextureWidth, 6);
      expect(requests, [
        (4, 4, null),
        (8, 8, 0.5),
        (4, 4, null),
        (16, 16, 0.25),
        (6, 6, 2 / 3),
      ]);
    } finally {
      if (!allowResize.isCompleted) allowResize.complete();
      await runtime.close();
      messenger.setMockMethodCallHandler(channel, null);
      saves.deleteSync(recursive: true);
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

  test('v2 handles only current browser requests and diagnostics', () async {
    const channel = MethodChannel('moe.alphaly.art3m1s/artemis_v2');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final saves = Directory.systemTemp.createTempSync('artemis-script-print-');
    final runtime = ArtemisV2EngineRuntime()..setSaveDir(saves.path);
    final debug = Log.debugEnabled;
    final browserRequests = <(String, String)>[];
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
      if (call.method == 'openBrowser') {
        browserRequests.add((call.arguments['epoch'], call.arguments['url']));
        return true;
      }
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
          event(
            domain: 1,
            kind: 5,
            epoch: '1',
            sequence: '4',
            metadata:
                '{"operation":"autosave","status":"failed",'
                '"reason":"io_error","files_written":1}',
          ),
          event(
            domain: 1,
            kind: 5,
            epoch: '2',
            sequence: '5',
            metadata:
                '{"operation":"autosave","status":"failed",'
                '"reason":"denied","files_written":2}',
          ),
          event(
            domain: 1,
            kind: 5,
            epoch: '2',
            sequence: '6',
            metadata: '{"operation":"autosave","status":"written"}',
          ),
          event(
            domain: 4,
            kind: 8,
            epoch: '1',
            sequence: '7',
            metadata: '{"url":"https://example.invalid/stale"}',
          ),
          event(
            domain: 4,
            kind: 8,
            epoch: '2',
            sequence: '8',
            metadata: '{"url":"https://example.invalid/current"}',
          ),
          event(
            domain: 7,
            kind: 3,
            epoch: '1',
            sequence: '9',
            metadata: '{"level":"warn"}',
            blob: utf8.encode('Script fixture stale'),
          ),
          event(
            domain: 7,
            kind: 3,
            epoch: '2',
            sequence: '10',
            metadata: '{"level":"warn"}',
            blob: utf8.encode('Script fixture current'),
          ),
        ],
        'close' => null,
        _ => throw StateError('Unexpected method: ${call.method}'),
      };
    });
    try {
      Log.setDebugEnabled(true);
      final start = Log.entries.length;
      expect(await runtime.loadProjectBytes(Uint8List(0)), isTrue);
      expect(browserRequests, [('2', 'https://example.invalid/current')]);
      expect(
        Log.entries
            .skip(start)
            .map((entry) => entry.message)
            .where((message) => message.startsWith('[ArtemisV2] Script fixture')),
        ['[ArtemisV2] Script fixture current'],
      );
      expect(
        Log.entries
            .skip(start)
            .map((entry) => entry.message)
            .where((message) => message.startsWith('[ArtemisV2] [Lua] ')),
        ['[ArtemisV2] [Lua] b\uFFFD'],
      );
      expect(
        Log.entries
            .skip(start)
            .map((entry) => entry.message)
            .where(
              (message) => message.startsWith('[ArtemisV2] Automatic save'),
            ),
        ['[ArtemisV2] Automatic save failed: denied (2 files written)'],
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
          : 'v2 serializes project changes after a native close error',
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
            case 'hasDxvkRuntime':
              return false;
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
              if (session == '1' && !exitDuringOpen) {
                throw PlatformException(
                  code: 'artemis_v2',
                  message: 'destroy renderer failed',
                );
              }
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
          await preparing?.then<void>((_) {}, onError: (Object _) {});
          await loading;
          await nextLoad;
          await runtime.close();
          messenger.setMockMethodCallHandler(channel, null);
          project.deleteSync(recursive: true);
        }
      },
    );
  }

  test('v2 saves the old project and switches after a frame fails', () async {
    const channel = MethodChannel('moe.alphaly.art3m1s/artemis_v2');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final saves = Directory.systemTemp.createTempSync('artemis-switch-save-');
    final runtime = ArtemisV2EngineRuntime()..setSaveDir(saves.path);
    final presenting = Completer<void>();
    final failPresentation = Completer<void>();
    final shutdownSent = Completer<void>();
    final allowShutdown = Completer<void>();
    final saving = Completer<void>();
    final acknowledge = Completer<void>();
    final calls = <String>[];
    final opening = <String>{};
    var opens = 0;
    var shuttingDown = false;
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
            shuttingDown = true;
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
          if (!shuttingDown) return state(session, 2);
          if (written) {
            closedPending = true;
            return state(session, 4);
          }
          writePending = true;
          return state(session, 3);
        case 'surface':
          return 0;
        case 'present':
          expect(session, '1');
          presenting.complete();
          await failPresentation.future;
          throw PlatformException(code: 'presentation_failed');
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
      expect(await runtime.enableSharedTexture(), 0);
      final frameFailed = expectLater(
        runtime.advanceTexture(16),
        throwsA(
          isA<PlatformException>().having(
            (error) => error.code,
            'code',
            'presentation_failed',
          ),
        ),
      );
      const timeout = Duration(seconds: 2);
      await presenting.future.timeout(timeout);
      switching = runtime.loadProjectBytes(Uint8List(0));
      final shutdownStarted = Future.any<void>([
        shutdownSent.future,
        switching.then<void>((_) {}),
      ]);
      await Future<void>.delayed(Duration.zero);
      expect(calls, ['open:1']);
      failPresentation.complete();
      await frameFailed;
      await shutdownStarted.timeout(timeout);
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
      if (!failPresentation.isCompleted) failPresentation.complete();
      if (!allowShutdown.isCompleted) allowShutdown.complete();
      if (!acknowledge.isCompleted) acknowledge.complete();
      await switching?.then<void>((_) {}, onError: (Object _) {});
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
        runtime.notifyLifecycle(0);
        runtime.notifyLifecycle(1);
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

  for (final (pollFails, layerIo) in [
    (false, false),
    (true, false),
    (false, true),
  ]) {
    test(
      switch ((pollFails, layerIo)) {
        (true, _) => 'v2 continues to step after a native video poll fails',
        (_, true) => 'v2 presents the last layer video frame after host IO resumes',
        _ => 'v2 presents a video frame before applying its terminal status',
      },
      () async {
        const channel = MethodChannel('moe.alphaly.art3m1s/artemis_v2');
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        final saves = Directory.systemTemp.createTempSync(
          'artemis-video-batch-',
        );
        final runtime = ArtemisV2EngineRuntime()..setSaveDir(saves.path);
        final videoOpened = Completer<void>();
        final videoClosing = Completer<void>();
        final allowVideoClose = Completer<void>();
        final videoPaused = Completer<void>();
        final detachStarted = Completer<void>();
        final allowDetach = Completer<void>();
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
        var layerIoPending = layerIo;
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
            case 'hasDxvkRuntime':
              return false;
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
                  if (layerIo) 'layer': 'clip',
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
              if (layerIo && videoPolls == 2) return <Object>[];
              if (videoStarted && pollFails) {
                throw PlatformException(code: 'video_poll_failed');
              }
              final started = !videoStarted;
              videoStarted = true;
              return [
                {
                  'playback': playback,
                  'status': started ? 'started' : 'ended',
                  if (started && !layerIo) ...{
                    'texture': 1,
                    'width': 4,
                    'height': 4,
                  },
                },
              ];
            case 'videoClose':
              closedVideos.add(call.arguments['playback'] as String);
              videoClosing.complete();
              await allowVideoClose.future;
              return null;
            case 'submit':
              for (final message in call.arguments['batch'] as List) {
                final wire = message as Map;
                final data = jsonDecode(
                  utf8.decode(wire['metadata'] as Uint8List),
                );
                if (wire['domain'] == 2) {
                  expect(wire['kind'], 4);
                  expect(data, isEmpty);
                  continue;
                }
                expect(data['playback_id'], playback);
                calls.add(data['status'] as String);
              }
              return true;
            case 'step':
              steps++;
              return {
                ...state,
                if (layerIoPending && videoPolls == 2) 'waitFlags': 1,
                'backpressured': false,
                'stepFlags': 0,
              };
            case 'present':
              if (layerIoPending && videoPolls == 2) return null;
              calls.add('present');
              return '1';
            case 'videoSuspend':
              if (call.arguments['suspended'] == true) videoPaused.complete();
              return null;
            case 'detach':
              detachStarted.complete();
              await allowDetach.future;
              return null;
            case 'close':
              return null;
            default:
              throw StateError('Unexpected method: ${call.method}');
          }
        });
        try {
          File('${saves.path}/system.ini').writeAsStringSync('[WINDOWS]\n');
          File('${saves.path}/clip.mp4').writeAsBytesSync([1]);
          final ini = await runtime.prepareProject(
            projectPath: saves.path,
            isArchive: false,
            environmentPatchEnabled: false,
            platform: 'WINDOWS',
          );
          expect(await runtime.loadProjectBytes(ini!), isTrue);
          expect(await runtime.enableSharedTexture(), 0);
          await videoOpened.future.timeout(const Duration(seconds: 2));

          await runtime.advanceTextureBatch([16, 17, 17]);
          expect(calls, ['started', 'present']);
          expect(steps, 3);
          if (layerIo) {
            expect(runtime.media.videoPlayback.value, isNull);
            expect(await runtime.advanceTextureBatch([16, 17]), isFalse);
            expect(steps, 4);
            expect(calls, ['started', 'present']);

            layerIoPending = false;
            expect(await runtime.advanceTextureBatch([16, 17]), isTrue);
            expect(steps, 6);
            expect(calls, ['started', 'present', 'present']);

            await runtime.advanceTextureBatch([16]);
            expect(calls, ['started', 'present', 'present', 'ended', 'present']);
            expect(steps, 7);
            expect(videoPolls, 3);
            return;
          }
          expect(runtime.media.videoPlayback.value, isNotNull);

          const timeout = Duration(seconds: 2);
          if (!pollFails) {
            final suspending = runtime.setSessionState(
              EngineSessionState.suspended,
            );
            try {
              await detachStarted.future.timeout(timeout);
              await videoPaused.future.timeout(timeout);
              expect(runtime.sharedTextureId, isNull);
              expect(await runtime.advanceTextureBatch([16]), isFalse);
              expect(steps, 3);
            } finally {
              allowDetach.complete();
              await suspending;
            }
            expect(
              await runtime.setSessionState(EngineSessionState.active),
              EngineSessionState.active,
            );
            expect(await runtime.enableSharedTexture(), 0);
          }
          await runtime.advanceTextureBatch([16]).timeout(timeout);
          if (pollFails) {
            await videoClosing.future.timeout(timeout);
            expect(calls, ['started', 'present', 'present']);
            expect(runtime.media.videoPlayback.value, isNotNull);
            await runtime.advanceTextureBatch([16]).timeout(timeout);
            expect(calls.last, 'present');
            expect(steps, 5);
            expect(videoPolls, 2);
            allowVideoClose.complete();
            await Future<void>.delayed(Duration.zero);
            await runtime.advanceTextureBatch([16]);
            expect(calls, [
              'started',
              'present',
              'present',
              'present',
              'failed',
              'present',
            ]);
            expect(closedVideos, [playback]);
            expect(steps, 6);
          } else {
            expect(calls, ['started', 'present', 'ended', 'present']);
            expect(closedVideos, isEmpty);
            expect(steps, 4);
          }
          expect(runtime.media.videoPlayback.value, isNull);
        } finally {
          if (!allowVideoClose.isCompleted) allowVideoClose.complete();
          await runtime.close();
          messenger.setMockMethodCallHandler(channel, null);
          saves.deleteSync(recursive: true);
        }
      },
    );
  }
}
