/* macOS Host adapter. Build crates/artemis-metal-host separately from Core. */
#ifndef ART3M1S_METAL_HOST_V1_H
#define ART3M1S_METAL_HOST_V1_H

#include "art3m1s_core_v2.draft.h"
#include <IOSurface/IOSurfaceRef.h>

#ifdef __cplusplus
extern "C" {
#endif

#define ART_METAL_HOST_V1_RENDERER_CAPS \
    (ART_RENDERER_CAP_SPRITE | ART_RENDERER_CAP_TRANSITION | ART_RENDERER_CAP_SCREENSHOT | \
     ART_RENDERER_CAP_GROUP | ART_RENDERER_CAP_EMOTE | ART_RENDERER_CAP_HLSL)
#define ART_ANGLE_HOST_V1_RENDERER_CAPS \
    ((ART_METAL_HOST_V1_RENDERER_CAPS & ~ART_RENDERER_CAP_HLSL) | ART_RENDERER_CAP_GLSL)

typedef struct ArtMetalHost ArtMetalHost;

/* All calls run on the Core runtime's owner thread. Keep the runtime and its
 * library alive until destroy. The adapter never steps or destroys the runtime. */
ArtStatus art3m1s_metal_host_v1_create(const ArtFrameApiV2 *frames, ArtRuntimeHandle runtime,
                                      ArtMetalHost **out);
/* ANGLE/Metal uses GLES shaders. Supply an absolute UTF-8 directory containing
 * the EGL and GLES libraries and negotiate ART_ANGLE_HOST_V1_RENDERER_CAPS. */
ArtStatus art3m1s_metal_host_v1_create_angle(const ArtFrameApiV2 *frames, ArtRuntimeHandle runtime,
                                            const char *directory, ArtMetalHost **out);
/* Optional ANGLE-only disk cache. Pass an absolute UTF-8 Host cache directory.
 * ART_E_UNSUPPORTED leaves normal source compilation available. */
ArtStatus art3m1s_metal_host_v1_set_glsl_cache(ArtMetalHost *host, const char *directory);
/* Prepare exact GLSL source bytes on this ANGLE context before drawing. */
ArtStatus art3m1s_metal_host_v1_prepare_glsl(ArtMetalHost *host, ArtBytes source);
/* Supply a trusted absolute UTF-8 runtime directory. Negotiate the same
 * renderer capabilities as the Metal Host. */
ArtStatus art3m1s_metal_host_v1_create_dxvk(const ArtFrameApiV2 *frames, ArtRuntimeHandle runtime,
                                           const char *directory, ArtMetalHost **out);
/* Prepare a program for the exact HLSL source bytes before frames use it.
 * Both byte ranges are borrowed for this call only. */
ArtStatus art3m1s_metal_host_v1_prepare_ade2(ArtMetalHost *host, ArtBytes source, ArtBytes artifact);
ArtStatus art3m1s_metal_host_v1_destroy(ArtMetalHost *host);

/* Supply a BGRA IOSurface and keep it alive until detached or destroyed.
 * NULL detaches. A failed replacement leaves the adapter detached. */
ArtStatus art3m1s_metal_host_v1_set_surface(ArtMetalHost *host, IOSurfaceRef surface);

/* ART_OK means a complete image is available to the surface consumer. Only
 * then is out_frame_id nonzero. ART_NO_DATA leaves the image untouched. Pass
 * after_frame_id = 0 to redraw the latest frame onto a replacement surface. */
ArtStatus art3m1s_metal_host_v1_present(ArtMetalHost *host, uint64_t after_frame_id,
                                       uint64_t *out_frame_id);

/* Read the exact frame named by a capture request, without changing the
 * shared surface. Width and height must be the frame's stage extent. Output
 * is tightly packed RGBA8, top row first. Host retains and saves the result. */
ArtStatus art3m1s_metal_host_v1_capture(ArtMetalHost *host, uint64_t frame_id,
                                       uint32_t width, uint32_t height,
                                       uint8_t *output, uint64_t capacity);

#ifdef __cplusplus
}
#endif
#endif
