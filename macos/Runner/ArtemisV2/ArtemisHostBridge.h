#ifndef ARTEMIS_HOST_BRIDGE_H
#define ARTEMIS_HOST_BRIDGE_H

#include "art3m1s_metal_host_v1.h"
#include "art3m1s_media_host_v1.h"

enum {
    ArtSwiftOK = ART_OK,
    ArtSwiftNoData = ART_NO_DATA,
    ArtSwiftWouldBlock = ART_WOULD_BLOCK,
    ArtSwiftBuffer = ART_E_BUFFER,
    ArtSwiftStale = ART_E_STALE,
    ArtSwiftUnsupported = ART_E_UNSUPPORTED,
    ArtSwiftMajor = ART_ABI_V2_MAJOR,
    ArtSwiftRuntime = ART_INTERFACE_RUNTIME,
    ArtSwiftSessionChanged = ART_RUNTIME_SESSION_CHANGED,
    ArtSwiftRuntimeClosed = ART_RUNTIME_CLOSED_EVENT,
    ArtSwiftFrame = ART_INTERFACE_FRAME,
    ArtSwiftCapabilities = ART_INTERFACE_CAPABILITIES,
    ArtSwiftOpenBrowserCapability = ART_HOST_CAP_OPEN_BROWSER,
    ArtSwiftSubmitVersion = ART_SUBMIT_SCHEMA_VERSION,
    ArtSwiftEventEnvelopeVersion = ART_EVENT_ENVELOPE_VERSION,
    ArtSwiftEventEnvelopeBytes = ART_EVENT_ENVELOPE_BYTES,
    ArtSwiftEventBodyHeaderBytes = ART_EVENT_BODY_HEADER_BYTES,
    ArtSwiftIo = ART_DOMAIN_IO,
    ArtSwiftIoStat = ART_IO_STAT,
    ArtSwiftIoRead = ART_IO_READ,
    ArtSwiftIoWrite = ART_IO_WRITE_ATOMIC,
    ArtSwiftWaitIo = ART_WAIT_IO,
    ArtSwiftBackgroundAutosave = ART_STEP_BACKGROUND_AUTOSAVE,
    ArtSwiftUI = ART_DOMAIN_UI,
    ArtSwiftHttpRequest = ART_UI_HTTP_REQUEST,
    ArtSwiftHttpCancel = ART_UI_HTTP_CANCEL,
    ArtSwiftCaption = ART_UI_CAPTION,
    ArtSwiftMedia = ART_DOMAIN_MEDIA,
    ArtSwiftAudioCommand = ART_MEDIA_AUDIO_COMMAND,
    ArtSwiftPlaybackStatus = ART_MEDIA_PLAYBACK_STATUS,
    ArtSwiftMediaCapability = ART_HOST_CAP_MEDIA,
    ArtSwiftVideoFrame = ART_MEDIA_VIDEO_FRAME,
    ArtSwiftRender = ART_DOMAIN_RENDER,
    ArtSwiftCapture = ART_RENDER_CAPTURE,
};

static inline uint64_t art_swift_io_cap(void) { return ART_HOST_CAP_IO; }
static inline uint64_t art_swift_renderer_caps(int screenshot) {
    return screenshot ? ART_METAL_HOST_V1_RENDERER_CAPS
                      : ART_METAL_HOST_V1_RENDERER_CAPS & ~ART_RENDERER_CAP_SCREENSHOT;
}
static inline uint64_t art_swift_angle_renderer_caps(int screenshot) {
    return screenshot ? ART_ANGLE_HOST_V1_RENDERER_CAPS
                      : ART_ANGLE_HOST_V1_RENDERER_CAPS & ~ART_RENDERER_CAP_SCREENSHOT;
}
static inline uint64_t art_swift_mixed_renderer_caps(int screenshot) {
    return screenshot ? ART_MIXED_HOST_V1_RENDERER_CAPS
                      : ART_MIXED_HOST_V1_RENDERER_CAPS & ~ART_RENDERER_CAP_SCREENSHOT;
}

static inline int art_swift_header_valid(ArtApiHeader header, uint32_t id, uint32_t size) {
    return header.magic == ART_API_MAGIC && header.interface_id == id &&
           header.abi_major == ART_ABI_V2_MAJOR && header.struct_size >= size;
}

typedef __typeof__(art3m1s_get_api_v2) *ArtSwiftGetAPI;
typedef __typeof__(art3m1s_metal_host_v1_create) *ArtSwiftMetalCreate;
typedef __typeof__(art3m1s_metal_host_v1_create_angle) *ArtSwiftAngleCreate;
typedef __typeof__(art3m1s_metal_host_v1_set_glsl_cache) *ArtSwiftGlslCache;
typedef __typeof__(art3m1s_metal_host_v1_prepare_glsl) *ArtSwiftPrepareGlsl;
typedef __typeof__(art3m1s_metal_host_v1_create_dxvk) *ArtSwiftDxvkCreate;
typedef __typeof__(art3m1s_metal_host_v1_create_mixed) *ArtSwiftMixedCreate;
typedef __typeof__(art3m1s_metal_host_v1_prepare_ade2) *ArtSwiftPrepareADE2;
typedef __typeof__(art3m1s_metal_host_v1_destroy) *ArtSwiftMetalDestroy;
typedef __typeof__(art3m1s_metal_host_v1_set_surface) *ArtSwiftMetalSurface;
typedef __typeof__(art3m1s_metal_host_v1_supports_spatial_upscaling) *ArtSwiftMetalSupportsSpatial;
typedef __typeof__(art3m1s_metal_host_v1_set_spatial_upscale) *ArtSwiftMetalSetSpatial;
typedef __typeof__(art3m1s_metal_host_v1_present) *ArtSwiftMetalPresent;
typedef __typeof__(art3m1s_metal_host_v1_capture) *ArtSwiftMetalCapture;

#endif
