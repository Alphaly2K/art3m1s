class ProfilerTimings {
  const ProfilerTimings({
    this.ffiCallMs = 0,
    this.logicMs = 0,
    this.inputMs = 0,
    this.interpreterMs = 0,
    this.eventsMs = 0,
    this.emoteMs = 0,
    this.audioMediaMs = 0,
    this.compositorMs = 0,
    this.textMs = 0,
    this.frameBuildMs = 0,
    this.transitionCaptureMs = 0,
    this.gpuSubmitMs = 0,
    this.presentMs = 0,
    this.readbackMs = 0,
    this.hostFfiMs = 0,
  });

  factory ProfilerTimings.fromJson(Object? value) {
    final json = value is Map<String, dynamic>
        ? value
        : const <String, dynamic>{};
    double number(String key) => (json[key] as num?)?.toDouble() ?? 0;
    return ProfilerTimings(
      ffiCallMs: number('ffi_call_ms'),
      logicMs: number('logic_ms'),
      inputMs: number('input_ms'),
      interpreterMs: number('interpreter_ms'),
      eventsMs: number('events_ms'),
      emoteMs: number('emote_ms'),
      audioMediaMs: number('audio_media_ms'),
      compositorMs: number('compositor_ms'),
      textMs: number('text_ms'),
      frameBuildMs: number('frame_build_ms'),
      transitionCaptureMs: number('transition_capture_ms'),
      gpuSubmitMs: number('gpu_submit_ms'),
      presentMs: number('present_ms'),
      readbackMs: number('readback_ms'),
      hostFfiMs: number('host_ffi_ms'),
    );
  }

  final double ffiCallMs;
  final double logicMs;
  final double inputMs;
  final double interpreterMs;
  final double eventsMs;
  final double emoteMs;
  final double audioMediaMs;
  final double compositorMs;
  final double textMs;
  final double frameBuildMs;
  final double transitionCaptureMs;
  final double gpuSubmitMs;
  final double presentMs;
  final double readbackMs;
  final double hostFfiMs;

  double get logicOtherMs =>
      (logicMs -
              inputMs -
              interpreterMs -
              eventsMs -
              emoteMs -
              audioMediaMs -
              compositorMs -
              textMs)
          .clamp(0, double.infinity)
          .toDouble();
}

class ProfilerSnapshot {
  const ProfilerSnapshot({
    required this.enabled,
    required this.windowMs,
    required this.tickHz,
    required this.renderedFps,
    required this.average,
    required this.maximum,
    required this.damagePercent,
    required this.drawCalls,
    required this.hostFfiCallsPerSecond,
    required this.hostFfiMibPerSecond,
    required this.textureCount,
    required this.textureGpuMib,
    required this.textureCpuMib,
    required this.emoteLayers,
    required this.emoteSourceMib,
    required this.droppedSamples,
  });

  factory ProfilerSnapshot.fromJson(Map<String, dynamic> json) {
    double number(String key) => (json[key] as num?)?.toDouble() ?? 0;
    int integer(String key) => (json[key] as num?)?.toInt() ?? 0;
    return ProfilerSnapshot(
      enabled: json['enabled'] == true,
      windowMs: integer('window_ms'),
      tickHz: number('tick_hz'),
      renderedFps: number('rendered_fps'),
      average: ProfilerTimings.fromJson(json['average']),
      maximum: ProfilerTimings.fromJson(json['maximum']),
      damagePercent: number('damage_percent'),
      drawCalls: number('draw_calls'),
      hostFfiCallsPerSecond: number('host_ffi_calls_per_second'),
      hostFfiMibPerSecond: number('host_ffi_mib_per_second'),
      textureCount: integer('texture_count'),
      textureGpuMib: number('texture_gpu_mib'),
      textureCpuMib: number('texture_cpu_mib'),
      emoteLayers: integer('emote_layers'),
      emoteSourceMib: number('emote_source_mib'),
      droppedSamples: integer('dropped_samples'),
    );
  }

  final bool enabled;
  final int windowMs;
  final double tickHz;
  final double renderedFps;
  final ProfilerTimings average;
  final ProfilerTimings maximum;
  final double damagePercent;
  final double drawCalls;
  final double hostFfiCallsPerSecond;
  final double hostFfiMibPerSecond;
  final int textureCount;
  final double textureGpuMib;
  final double textureCpuMib;
  final int emoteLayers;
  final double emoteSourceMib;
  final int droppedSamples;
}
