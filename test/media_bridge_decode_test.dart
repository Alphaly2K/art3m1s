import 'dart:io';
import 'dart:typed_data';

import 'package:art3m1s/engine/backends/art3m1s/media_bridge.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Darwin playback converts and caches both A/B OGG segments', () async {
    final assets = <String, Uint8List>{
      'bgm/intro.ogg': Uint8List.fromList([
        0x4f,
        0x67,
        0x67,
        0x53,
        ...List<int>.filled(12, 1),
      ]),
      'bgm/loop.ogg': Uint8List.fromList([
        0x4f,
        0x67,
        0x67,
        0x53,
        ...List<int>.filled(12, 2),
      ]),
    };
    var decodeCalls = 0;
    final bridge = MediaBridge(
      onVideoFinished: (_) {},
      onSoundFinished: (_) {},
      decodeCompressedAudio: true,
      audioDecoder: (bytes, outputPath) async {
        decodeCalls += 1;
        File(outputPath).writeAsBytesSync(<int>[
          ...('RIFF'.codeUnits),
          ...List<int>.filled(40, 0),
        ], flush: true);
      },
    )..configureAssetReader((path) => assets[path]);

    final intro = await bridge.resolveAssetForTest({'file': 'bgm/intro'});
    final loop = await bridge.resolveAssetForTest({'file': 'bgm/loop'});
    final introAgain = await bridge.resolveAssetForTest({'file': 'bgm/intro'});

    expect(intro, isNotNull);
    expect(loop, isNotNull);
    expect(intro!.path, endsWith('.wav'));
    expect(loop!.path, endsWith('.wav'));
    expect(introAgain!.path, intro.path);
    expect(decodeCalls, 2);
    expect(intro.existsSync(), isTrue);
    expect(loop.existsSync(), isTrue);

    await bridge.dispose();
    expect(intro.existsSync(), isFalse);
    expect(loop.existsSync(), isFalse);
  });
}
