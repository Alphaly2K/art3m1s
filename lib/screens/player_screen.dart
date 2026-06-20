import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/game_entry.dart';
import '../providers/settings_provider.dart';
import '../services/core_bridge.dart';
import '../services/file_provider.dart';

class PlayerScreen extends ConsumerStatefulWidget {
  final String projectPath;
  final GameSource source;

  const PlayerScreen({
    super.key,
    required this.projectPath,
    required this.source,
  });

  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen> {
  final _bridge = CoreBridge();
  Timer? _timer;
  ui.Image? _frameImage;
  int _stageW = 1280;
  int _stageH = 720;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await _bridge.initialize();
    if (!_bridge.isInitialized) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Core 库加载失败')),
        );
      }
      return;
    }

    String iniContent;
    if (widget.source == GameSource.pfsArchive) {
      FileProvider.openPfs(widget.projectPath);
      final bytes = FileProvider.readFile('system.ini');
      if (bytes == null) return;
      iniContent = String.fromCharCodes(bytes);
    } else {
      FileProvider.openDirectory(widget.projectPath);
      iniContent = File('${widget.projectPath}${Platform.pathSeparator}system.ini')
          .readAsStringSync();
    }

    _parseStageSize(iniContent);

    _bridge.registerFileReader();
    _bridge.createRuntime(_stageW, _stageH,
        backend: ref.read(settingsProvider).backend);
    if (!_bridge.loadProject(iniContent)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('项目加载失败')),
        );
      }
      return;
    }

    setState(() {});
    _startGameLoop();
  }

  void _parseStageSize(String ini) {
    for (final line in ini.split('\n')) {
      final trimmed = line.trim().toUpperCase();
      if (trimmed.startsWith('WIDTH=')) {
        _stageW = int.tryParse(trimmed.split('=').last.trim()) ?? 1280;
      }
      if (trimmed.startsWith('HEIGHT=')) {
        _stageH = int.tryParse(trimmed.split('=').last.trim()) ?? 720;
      }
    }
  }

  void _startGameLoop() {
    const frameMs = 16;
    var lastTime = DateTime.now();

    _timer = Timer.periodic(Duration(milliseconds: frameMs), (_) {
      final now = DateTime.now();
      final deltaMs = now.difference(lastTime).inMilliseconds;
      lastTime = now;

      final pixels = _bridge.advanceAndRender(deltaMs.clamp(0, 100));
      if (pixels != null && mounted) {
        _decodeFrame(pixels);
      }
    });
  }

  void _decodeFrame(Uint8List pixels) {
    final w = _stageW;
    final h = _stageH;
    ui.decodeImageFromPixels(pixels, w, h, ui.PixelFormat.rgba8888, (image) {
      if (mounted) {
        final old = _frameImage;
        _frameImage = image;
        old?.dispose();
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _frameImage?.dispose();
    _bridge.shutdown();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.projectPath.split('/').last,
            overflow: TextOverflow.ellipsis),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: _frameImage != null
          ? _buildGameView()
          : const Center(child: CircularProgressIndicator()),
    );
  }

  Widget _buildGameView() {
    final image = _frameImage!;

    return LayoutBuilder(
      builder: (context, constraints) {
        final cw = constraints.maxWidth;
        final ch = constraints.maxHeight;

        // Calculate the actual display rect for the game content
        final scaleX = cw / _stageW;
        final scaleY = ch / _stageH;
        final scale = scaleX < scaleY ? scaleX : scaleY;
        final dw = _stageW * scale;
        final dh = _stageH * scale;
        final ox = (cw - dw) / 2;
        final oy = (ch - dh) / 2;

        return GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTapDown: (details) => _handleTap(details, ox, oy, scale),
          onPanUpdate: (details) => _handlePan(details, ox, oy, scale),
          child: MouseRegion(
            onHover: (event) => _handleHover(event, ox, oy, scale),
            child: Center(
              child: SizedBox(
                width: dw,
                height: dh,
                child: RawImage(image: image, fit: BoxFit.fill),
              ),
            ),
          ),
        );
      },
    );
  }

  void _handleHover(PointerEvent event, double ox, double oy, double scale) {
    final mx = ((event.localPosition.dx - ox) / scale).clamp(0.0, _stageW.toDouble() - 1);
    final my = ((event.localPosition.dy - oy) / scale).clamp(0.0, _stageH.toDouble() - 1);
    _bridge.feedMouse(mx.toInt(), my.toInt());
  }

  void _handleTap(TapDownDetails details, double ox, double oy, double scale) {
    final mx = ((details.localPosition.dx - ox) / scale).clamp(0.0, _stageW.toDouble() - 1);
    final my = ((details.localPosition.dy - oy) / scale).clamp(0.0, _stageH.toDouble() - 1);
    _bridge.feedMouse(mx.toInt(), my.toInt());
    _bridge.feedClick();
  }

  void _handlePan(DragUpdateDetails details, double ox, double oy, double scale) {
    final mx = ((details.localPosition.dx - ox) / scale).clamp(0.0, _stageW.toDouble() - 1);
    final my = ((details.localPosition.dy - oy) / scale).clamp(0.0, _stageH.toDouble() - 1);
    _bridge.feedMouse(mx.toInt(), my.toInt());
  }
}
