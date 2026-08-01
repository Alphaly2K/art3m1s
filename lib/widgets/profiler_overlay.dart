import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../services/profiler_snapshot.dart';

class ProfilerOverlay extends StatelessWidget {
  const ProfilerOverlay({super.key, required this.snapshot});

  final ValueListenable<ProfilerSnapshot?> snapshot;

  @override
  Widget build(BuildContext context) {
    final width = math.min(360.0, MediaQuery.sizeOf(context).width - 16);
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
    final average = value.average;
    final maximum = value.maximum;
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
                '累计 ${_formatElapsed(value.windowMs)}',
                style: const TextStyle(color: Color(0xFFA7A7AE)),
              ),
            ],
          ),
          _ValueRow(
            '采样速率',
            '${value.tickHz.toStringAsFixed(1)} tick/s  '
                '${value.renderedFps.toStringAsFixed(1)} render/s',
          ),
          const SizedBox(height: 5),
          const _SectionTitle('CPU / 累计每 tick', showColumns: true),
          _TimingRow('FFI 调用总计', average.ffiCallMs, maximum.ffiCallMs),
          _TimingRow('逻辑总计', average.logicMs, maximum.logicMs),
          _TimingRow('  解释器', average.interpreterMs, maximum.interpreterMs),
          _TimingRow('  输入 / 命中', average.inputMs, maximum.inputMs),
          _TimingRow('  事件派发', average.eventsMs, maximum.eventsMs),
          _TimingRow('  合成器', average.compositorMs, maximum.compositorMs),
          _TimingRow('  E-Mote', average.emoteMs, maximum.emoteMs),
          _TimingRow('  文本', average.textMs, maximum.textMs),
          _TimingRow('  音频 / 媒体', average.audioMediaMs, maximum.audioMediaMs),
          _TimingRow('  其他', average.logicOtherMs, maximum.logicOtherMs),
          const _SectionTitle('渲染 / 累计每 tick', showColumns: true),
          _TimingRow(
            'DrawList / 纹理',
            average.frameBuildMs,
            maximum.frameBuildMs,
          ),
          _TimingRow(
            '转场捕获',
            average.transitionCaptureMs,
            maximum.transitionCaptureMs,
          ),
          _TimingRow('GPU 命令提交', average.gpuSubmitMs, maximum.gpuSubmitMs),
          _TimingRow('共享纹理提交', average.presentMs, maximum.presentMs),
          _TimingRow('RGBA 回读', average.readbackMs, maximum.readbackMs),
          _TimingRow('宿主文件 FFI', average.hostFfiMs, maximum.hostFfiMs),
          const _SectionTitle('状态'),
          _ValueRow(
            '脏区 / Draw calls',
            '${value.damagePercent.toStringAsFixed(1)}% / ${value.drawCalls.toStringAsFixed(1)}',
          ),
          _ValueRow(
            '宿主 FFI',
            '${value.hostFfiCallsPerSecond.toStringAsFixed(0)}/s  ${value.hostFfiMibPerSecond.toStringAsFixed(1)} MiB/s',
          ),
          _ValueRow(
            '纹理 GPU / CPU',
            '${value.textureCount}  ${value.textureGpuMib.toStringAsFixed(1)} / ${value.textureCpuMib.toStringAsFixed(1)} MiB',
          ),
          _ValueRow(
            'E-Mote',
            '${value.emoteLayers} layer  ${value.emoteSourceMib.toStringAsFixed(1)} MiB',
          ),
          if (value.droppedSamples > 0)
            _ValueRow('丢弃样本', '${value.droppedSamples}', warning: true),
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
        Text(text, style: const TextStyle(color: Color(0xFF8E8E98))),
        if (showColumns) ...[
          const Spacer(),
          const SizedBox(
            width: 52,
            child: Text('avg', textAlign: TextAlign.right),
          ),
          const SizedBox(
            width: 52,
            child: Text('max', textAlign: TextAlign.right),
          ),
        ],
      ],
    ),
  );
}

class _TimingRow extends StatelessWidget {
  const _TimingRow(this.label, this.average, this.maximum);
  final String label;
  final double average;
  final double maximum;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(child: Text(label, overflow: TextOverflow.ellipsis)),
      SizedBox(
        width: 52,
        child: Text(
          '${average.toStringAsFixed(2)}ms',
          textAlign: TextAlign.right,
        ),
      ),
      SizedBox(
        width: 52,
        child: Text(
          '${maximum.toStringAsFixed(2)}ms',
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
      Expanded(child: Text(label)),
      Text(
        value,
        style: TextStyle(
          color: warning ? const Color(0xFFFFB86C) : const Color(0xFFD7D7DB),
        ),
      ),
    ],
  );
}
