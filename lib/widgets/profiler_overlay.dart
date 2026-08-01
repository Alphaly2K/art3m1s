import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../services/profiler_snapshot.dart';

class ProfilerOverlay extends StatelessWidget {
  const ProfilerOverlay({super.key, required this.snapshot});

  final ValueListenable<ProfilerSnapshot?> snapshot;

  @override
  Widget build(BuildContext context) {
    final availableWidth = MediaQuery.sizeOf(context).width - 16;
    final width = availableWidth >= 780
        ? math.min(840.0, availableWidth)
        : math.min(360.0, availableWidth);
    return Positioned(
      top: 8,
      right: 8,
      width: width,
      child: IgnorePointer(
        child: ValueListenableBuilder<ProfilerSnapshot?>(
          valueListenable: snapshot,
          builder: (context, value, _) {
            return DecoratedBox(
              decoration: BoxDecoration(
                color: const Color(0xEC141417),
                border: Border.all(color: const Color(0x35FFFFFF)),
                borderRadius: BorderRadius.circular(6),
                boxShadow: const [
                  BoxShadow(color: Color(0x55000000), blurRadius: 10),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.all(9),
                child: value == null
                    ? const Text('Profiler 正在采样...')
                    : _ProfilerContents(value),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _ProfilerContents extends StatelessWidget {
  const _ProfilerContents(this.value);

  final ProfilerSnapshot value;

  @override
  Widget build(BuildContext context) {
    final current = value.current;
    final average = value.average;
    final onePercent = value.onePercent;
    return DefaultTextStyle(
      style: const TextStyle(
        color: Color(0xFFD7D7DB),
        fontFamily: 'monospace',
        fontSize: 10.5,
        height: 1.25,
        decoration: TextDecoration.none,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Text(
                'PROFILER',
                style: TextStyle(
                  color: Color(0xFF9BE15D),
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              Text(
                '${_formatElapsed(value.sampleWindowMs)} 窗口  '
                '会话 ${_formatElapsed(value.sessionMs)}',
                style: const TextStyle(color: Color(0xFFA7A7AE)),
              ),
            ],
          ),
          const SizedBox(height: 5),
          LayoutBuilder(
            builder: (context, constraints) {
              final fourColumns = constraints.maxWidth >= 760;
              final columnWidth = fourColumns
                  ? (constraints.maxWidth - 40) / 4
                  : constraints.maxWidth;
              return Flex(
                direction: fourColumns ? Axis.horizontal : Axis.vertical,
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: columnWidth,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const _SectionTitle('CPU / 每 tick', showColumns: true),
                        _TimingRow(
                          'Core Tick 总计',
                          current.ffiCallMs,
                          average.ffiCallMs,
                          onePercent.ffiCallMs,
                        ),
                        _TimingRow(
                          '逻辑总计',
                          current.logicMs,
                          average.logicMs,
                          onePercent.logicMs,
                        ),
                        _TimingRow(
                          '  解释器',
                          current.interpreterMs,
                          average.interpreterMs,
                          onePercent.interpreterMs,
                        ),
                        _TimingRow(
                          '  输入 / 命中',
                          current.inputMs,
                          average.inputMs,
                          onePercent.inputMs,
                        ),
                        _TimingRow(
                          '  事件派发',
                          current.eventsMs,
                          average.eventsMs,
                          onePercent.eventsMs,
                        ),
                        const _SectionTitle('窗口吞吐'),
                        _ValueRow(
                          'Tick / Render',
                          '${value.tickHz.toStringAsFixed(1)} / ${value.renderedFps.toStringAsFixed(1)} fps',
                        ),
                        _ValueRow(
                          '渲染 / 跳过帧',
                          '${value.renderedFrames} / ${value.skippedFrames}',
                        ),
                        _ValueRow(
                          '宿主 FFI',
                          '${value.hostFfiCallsPerSecond.toStringAsFixed(0)}/s  ${value.hostFfiMibPerSecond.toStringAsFixed(1)} MiB/s',
                        ),
                        _ValueRow(
                          '纹理 / Mesh 上传',
                          '${value.uploadedMibPerSecond.toStringAsFixed(1)} / ${value.dynamicMeshUploadedMibPerSecond.toStringAsFixed(1)} MiB/s',
                        ),
                        _ValueRow(
                          '图层视频上传',
                          '${value.videoUploadedFramesPerSecond.toStringAsFixed(1)} fps  ${value.videoUploadedMibPerSecond.toStringAsFixed(1)} MiB/s',
                        ),
                        if (value.droppedSamples > 0)
                          _ValueRow(
                            '丢弃样本',
                            '${value.droppedSamples}',
                            warning: true,
                          ),
                      ],
                    ),
                  ),
                  if (fourColumns) const SizedBox(width: 12),
                  SizedBox(
                    width: columnWidth,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const _SectionTitle('事件细分 / 每 tick', showColumns: true),
                        _TimingRow(
                          '    队列排水',
                          current.eventDrainMs,
                          average.eventDrainMs,
                          onePercent.eventDrainMs,
                        ),
                        _TimingRow(
                          '    运行时副作用',
                          current.eventRuntimeMs,
                          average.eventRuntimeMs,
                          onePercent.eventRuntimeMs,
                        ),
                        _TimingRow(
                          '    媒体事件',
                          current.eventMediaMs,
                          average.eventMediaMs,
                          onePercent.eventMediaMs,
                        ),
                        _TimingRow(
                          '    文本事件',
                          current.eventTextMs,
                          average.eventTextMs,
                          onePercent.eventTextMs,
                        ),
                        _TimingRow(
                          '    转场源重建',
                          current.eventTransitionMs,
                          average.eventTransitionMs,
                          onePercent.eventTransitionMs,
                        ),
                        _TimingRow(
                          '    合成器应用',
                          current.eventCompositorMs,
                          average.eventCompositorMs,
                          onePercent.eventCompositorMs,
                        ),
                        _TimingRow(
                          '    图层快照',
                          current.eventLayerSyncMs,
                          average.eventLayerSyncMs,
                          onePercent.eventLayerSyncMs,
                        ),
                        _TimingRow(
                          '    调试日志',
                          current.eventLogMs,
                          average.eventLogMs,
                          onePercent.eventLogMs,
                        ),
                        _TimingRow(
                          '    派发后回调',
                          current.eventPostMs,
                          average.eventPostMs,
                          onePercent.eventPostMs,
                        ),
                        _TimingRow(
                          '    事件其他',
                          current.eventOtherMs,
                          average.eventOtherMs,
                          onePercent.eventOtherMs,
                        ),
                      ],
                    ),
                  ),
                  if (fourColumns) const SizedBox(width: 12),
                  SizedBox(
                    width: columnWidth,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const _SectionTitle('渲染 / 每 tick', showColumns: true),
                        _TimingRow(
                          'DrawList / 纹理',
                          current.frameBuildMs,
                          average.frameBuildMs,
                          onePercent.frameBuildMs,
                        ),
                        _TimingRow(
                          'Damage 计算',
                          current.damageComputeMs,
                          average.damageComputeMs,
                          onePercent.damageComputeMs,
                        ),
                        _TimingRow(
                          '转场捕获',
                          current.transitionCaptureMs,
                          average.transitionCaptureMs,
                          onePercent.transitionCaptureMs,
                        ),
                        _TimingRow(
                          '纹理上传',
                          current.textureUploadMs,
                          average.textureUploadMs,
                          onePercent.textureUploadMs,
                        ),
                        _TimingRow(
                          '  图层视频',
                          current.videoUploadMs,
                          average.videoUploadMs,
                          onePercent.videoUploadMs,
                        ),
                        _TimingRow(
                          'GL 提交 (CPU)',
                          current.gpuSubmitMs,
                          average.gpuSubmitMs,
                          onePercent.gpuSubmitMs,
                        ),
                        _TimingRow(
                          '共享纹理提交',
                          current.presentMs,
                          average.presentMs,
                          onePercent.presentMs,
                        ),
                        _TimingRow(
                          'RGBA 回读',
                          current.readbackMs,
                          average.readbackMs,
                          onePercent.readbackMs,
                        ),
                        _TimingRow(
                          '宿主文件 FFI',
                          current.hostFfiMs,
                          average.hostFfiMs,
                          onePercent.hostFfiMs,
                        ),
                      ],
                    ),
                  ),
                  if (fourColumns) const SizedBox(width: 12),
                  SizedBox(
                    width: columnWidth,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const _SectionTitle('逻辑续 / 每 tick', showColumns: true),
                        _TimingRow(
                          '  合成器',
                          current.compositorMs,
                          average.compositorMs,
                          onePercent.compositorMs,
                        ),
                        _TimingRow(
                          '  E-Mote',
                          current.emoteMs,
                          average.emoteMs,
                          onePercent.emoteMs,
                        ),
                        _TimingRow(
                          '  文本',
                          current.textMs,
                          average.textMs,
                          onePercent.textMs,
                        ),
                        _TimingRow(
                          '  音频 / 媒体',
                          current.audioMediaMs,
                          average.audioMediaMs,
                          onePercent.audioMediaMs,
                        ),
                        _TimingRow(
                          '  其他',
                          current.logicOtherMs,
                          average.logicOtherMs,
                          onePercent.logicOtherMs,
                        ),
                        const _SectionTitle('瞬时状态'),
                        _ValueRow(
                          '当前帧 / 脏区',
                          '${value.currentRendered ? '渲染' : '跳过'}  ${value.damagePercent.toStringAsFixed(1)}%',
                        ),
                        _ValueRow(
                          'Draw / Vertices',
                          '${value.drawCalls} / ${value.vertices}',
                        ),
                        _ValueRow(
                          'Binds / Commands',
                          '${value.textureBinds} / ${value.drawListCommands}',
                        ),
                        _ValueRow(
                          '纹理 GPU / CPU',
                          '${value.textureCount}  ${value.textureGpuMib.toStringAsFixed(1)} / ${value.textureCpuMib.toStringAsFixed(1)} MiB',
                        ),
                        _ValueRow(
                          'E-Mote',
                          '${value.emoteLayers} layer  ${value.emoteSourceMib.toStringAsFixed(1)} MiB',
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

String _formatElapsed(int milliseconds) {
  final seconds = milliseconds ~/ 1000;
  if (seconds >= 3600) {
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    return '${hours}h ${minutes}m';
  }
  if (seconds >= 60) {
    return '${seconds ~/ 60}m ${seconds % 60}s';
  }
  return '${(milliseconds / 1000).toStringAsFixed(1)}s';
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text, {this.showColumns = false});
  final String text;
  final bool showColumns;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 5, bottom: 2),
    child: Row(
      children: [
        Expanded(
          child: Text(
            text,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Color(0xFF8E8E98)),
          ),
        ),
        if (showColumns) ...[
          const SizedBox(
            width: 48,
            child: Text('now', textAlign: TextAlign.right),
          ),
          const SizedBox(
            width: 48,
            child: Text('avg', textAlign: TextAlign.right),
          ),
          const SizedBox(
            width: 48,
            child: Text('1%', textAlign: TextAlign.right),
          ),
        ],
      ],
    ),
  );
}

class _TimingRow extends StatelessWidget {
  const _TimingRow(this.label, this.current, this.average, this.onePercent);
  final String label;
  final double current;
  final double average;
  final double onePercent;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(child: Text(label, overflow: TextOverflow.ellipsis)),
      SizedBox(
        width: 48,
        child: Text(
          '${current.toStringAsFixed(2)}ms',
          textAlign: TextAlign.right,
        ),
      ),
      SizedBox(
        width: 48,
        child: Text(
          '${average.toStringAsFixed(2)}ms',
          textAlign: TextAlign.right,
        ),
      ),
      SizedBox(
        width: 48,
        child: Text(
          '${onePercent.toStringAsFixed(2)}ms',
          textAlign: TextAlign.right,
        ),
      ),
    ],
  );
}

class _ValueRow extends StatelessWidget {
  const _ValueRow(this.label, this.value, {this.warning = false});
  final String label;
  final String value;
  final bool warning;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        flex: 2,
        child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      Expanded(
        flex: 3,
        child: Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.right,
          style: TextStyle(
            color: warning ? const Color(0xFFFFB86C) : const Color(0xFFD7D7DB),
          ),
        ),
      ),
    ],
  );
}
