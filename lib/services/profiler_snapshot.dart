class ProfilerTimings {
  const ProfilerTimings({
    this.ffiCallMs = 0,
    this.logicMs = 0,
    this.inputMs = 0,
    this.interpreterMs = 0,
    this.eventsMs = 0,
    this.eventRuntimeMs = 0,
    this.eventMediaMs = 0,
    this.eventTextMs = 0,
    this.eventTransitionMs = 0,
    this.eventCompositorMs = 0,
    this.eventLayerSyncMs = 0,
    this.eventDrainMs = 0,
    this.eventLogMs = 0,
    this.eventPostMs = 0,
    this.emoteMs = 0,
    this.audioMediaMs = 0,
    this.compositorMs = 0,
    this.textMs = 0,
    this.frameBuildMs = 0,
    this.damageComputeMs = 0,
    this.transitionCaptureMs = 0,
    this.textureUploadMs = 0,
    this.videoUploadMs = 0,
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
      eventRuntimeMs: number('event_runtime_ms'),
      eventMediaMs: number('event_media_ms'),
      eventTextMs: number('event_text_ms'),
      eventTransitionMs: number('event_transition_ms'),
      eventCompositorMs: number('event_compositor_ms'),
      eventLayerSyncMs: number('event_layer_sync_ms'),
      eventDrainMs: number('event_drain_ms'),
      eventLogMs: number('event_log_ms'),
      eventPostMs: number('event_post_ms'),
      emoteMs: number('emote_ms'),
      audioMediaMs: number('audio_media_ms'),
      compositorMs: number('compositor_ms'),
      textMs: number('text_ms'),
      frameBuildMs: number('frame_build_ms'),
      damageComputeMs: number('damage_compute_ms'),
      transitionCaptureMs: number('transition_capture_ms'),
      textureUploadMs: number('texture_upload_ms'),
      videoUploadMs: number('video_upload_ms'),
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
  final double eventRuntimeMs;
  final double eventMediaMs;
  final double eventTextMs;
  final double eventTransitionMs;
  final double eventCompositorMs;
  final double eventLayerSyncMs;
  final double eventDrainMs;
  final double eventLogMs;
  final double eventPostMs;
  final double emoteMs;
  final double audioMediaMs;
  final double compositorMs;
  final double textMs;
  final double frameBuildMs;
  final double damageComputeMs;
  final double transitionCaptureMs;
  final double textureUploadMs;
  final double videoUploadMs;
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

  double get eventOtherMs =>
      (eventsMs -
              eventRuntimeMs -
              eventMediaMs -
              eventTextMs -
              eventTransitionMs -
              eventCompositorMs -
              eventLayerSyncMs -
              eventDrainMs -
              eventLogMs -
              eventPostMs)
          .clamp(0, double.infinity)
          .toDouble();
}

class ProfilerSnapshot {
  const ProfilerSnapshot({
    required this.enabled,
    required this.sessionMs,
    required this.sampleWindowMs,
    required this.sampleCount,
    required this.tickHz,
    required this.renderedFps,
    required this.current,
    required this.average,
    required this.onePercent,
    required this.damagePercent,
    required this.currentRendered,
    required this.drawCalls,
    required this.vertices,
    required this.textureBinds,
    required this.drawListCommands,
    required this.renderedFrames,
    required this.skippedFrames,
    required this.hostFfiCallsPerSecond,
    required this.hostFfiMibPerSecond,
    required this.uploadedMibPerSecond,
    required this.videoUploadedMibPerSecond,
    required this.videoUploadedFramesPerSecond,
    required this.dynamicMeshUploadedMibPerSecond,
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
    int integerWithFallback(String key, String fallback) =>
        (json[key] as num?)?.toInt() ?? integer(fallback);
    final average = ProfilerTimings.fromJson(json['average']);
    return ProfilerSnapshot(
      enabled: json['enabled'] == true,
      sessionMs: integerWithFallback('session_ms', 'window_ms'),
      sampleWindowMs: integerWithFallback('sample_window_ms', 'window_ms'),
      sampleCount: integer('sample_count'),
      tickHz: number('tick_hz'),
      renderedFps: number('rendered_fps'),
      current: json.containsKey('current')
          ? ProfilerTimings.fromJson(json['current'])
          : average,
      average: average,
      onePercent: ProfilerTimings.fromJson(
        json['one_percent'] ?? json['maximum'],
      ),
      damagePercent: number('damage_percent'),
      currentRendered: json['current_rendered'] == true,
      drawCalls: integer('draw_calls'),
      vertices: integer('vertices'),
      textureBinds: integer('texture_binds'),
      drawListCommands: integer('draw_list_commands'),
      renderedFrames: integer('rendered_frames'),
      skippedFrames: integer('skipped_frames'),
      hostFfiCallsPerSecond: number('host_ffi_calls_per_second'),
      hostFfiMibPerSecond: number('host_ffi_mib_per_second'),
      uploadedMibPerSecond: number('uploaded_mib_per_second'),
      videoUploadedMibPerSecond: number('video_uploaded_mib_per_second'),
      videoUploadedFramesPerSecond: number('video_uploaded_frames_per_second'),
      dynamicMeshUploadedMibPerSecond: number(
        'dynamic_mesh_uploaded_mib_per_second',
      ),
      textureCount: integer('texture_count'),
      textureGpuMib: number('texture_gpu_mib'),
      textureCpuMib: number('texture_cpu_mib'),
      emoteLayers: integer('emote_layers'),
      emoteSourceMib: number('emote_source_mib'),
      droppedSamples: integer('dropped_samples'),
    );
  }

  final bool enabled;
  final int sessionMs;
  final int sampleWindowMs;
  final int sampleCount;
  final double tickHz;
  final double renderedFps;
  final ProfilerTimings current;
  final ProfilerTimings average;
  final ProfilerTimings onePercent;
  final double damagePercent;
  final bool currentRendered;
  final int drawCalls;
  final int vertices;
  final int textureBinds;
  final int drawListCommands;
  final int renderedFrames;
  final int skippedFrames;
  final double hostFfiCallsPerSecond;
  final double hostFfiMibPerSecond;
  final double uploadedMibPerSecond;
  final double videoUploadedMibPerSecond;
  final double videoUploadedFramesPerSecond;
  final double dynamicMeshUploadedMibPerSecond;
  final int textureCount;
  final double textureGpuMib;
  final double textureCpuMib;
  final int emoteLayers;
  final double emoteSourceMib;
  final int droppedSamples;
}
