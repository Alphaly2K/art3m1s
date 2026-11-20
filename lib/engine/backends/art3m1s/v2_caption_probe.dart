import 'dart:typed_data';

import '../../../services/logger.dart';
import 'caption_table_probe.dart';
import 'project_charset.dart';
import 'project_vfs.dart';
import 'v2_sdk/artemis_file_service.dart';
import 'v2_sdk/artemis_flutter_session.dart';

Future<String?> probeArtemisV2Caption({
  required String projectPath,
  required bool isArchive,
  required String platform,
}) async {
  ProjectVfs? files;
  ArtemisFlutterSession? session;
  ArtemisFileService? service;
  try {
    final project = ProjectVfs.openWithIni(
      path: projectPath,
      isArchive: isArchive,
      platform: platform,
    );
    files = project.files;
    final ini = project.ini;
    if (ini == null || ini.isEmpty) return null;
    Uint8List? readAsset(String key, {int? maxBytes}) => project.files
        .readAsset(key, environmentPatchEnabled: true, maxBytes: maxBytes);
    try {
      final title = CaptionTableProbe.find(
        paths: files.listFiles(extension: '.tbl'),
        readFile: readAsset,
        charset: ProjectCharset.detect(ini, platform),
      );
      if (title != null) return title;
    } on Exception catch (error) {
      Log.warn('[ArtemisV2] Caption table: $error');
    }

    final opened = await ArtemisFlutterSession.open(
      ini: ini,
      platform: platform,
      hostCaps: ArtemisFileService.capabilities,
      headless: true,
    );
    session = opened.session;
    service = ArtemisFileService.assetsOnly(
      readAsset: (key, {maxBytes}) {
        final bytes = readAsset(key, maxBytes: maxBytes);
        return bytes == null ? null : (bytes: bytes, modified: null);
      },
    );
    final budget = Stopwatch()..start();
    final time = DateTime.now();
    var frame = 1;
    for (var turn = 0; turn < 512 && frame <= 120; turn++) {
      if (budget.elapsed >= const Duration(seconds: 2)) return null;
      final step = await session.step(
        frame: frame,
        monotonicNS: frame * 16000000,
        time: time.add(Duration(milliseconds: frame * 16)),
      );
      final replies = <ArtemisFlutterMessage>[];
      final events = await session.pollEvents();
      for (final event in events) {
        final caption = event.metadata['text'];
        if (event.domain == 4 &&
            event.kind == 1 &&
            caption is String &&
            caption.trim().isNotEmpty) {
          return caption.trim();
        }
        final reply = service.handle(
          ArtemisFileEvent(
            event.domain,
            event.kind,
            int.parse(event.epoch),
            event.requiresReply,
            event.metadata,
            event.blob,
          ),
        );
        if (reply != null) {
          replies.add(event.reply(reply.metadata, blob: reply.blob));
        } else if (event.requiresReply) {
          return null;
        }
      }
      if (replies.isNotEmpty && !await session.submit(replies)) return null;
      if (step.state.exitRequested || step.state.phase == 4) return null;
      if (!step.backpressured && step.state.waitFlags & 1 == 0) frame++;
    }
    return null;
  } on Exception catch (error) {
    Log.warn('[ArtemisV2] Caption probe: $error');
    return null;
  } finally {
    service?.close();
    files?.close();
    try {
      await session?.close();
    } on Exception catch (error) {
      Log.warn('[ArtemisV2] Close caption probe: $error');
    }
  }
}
