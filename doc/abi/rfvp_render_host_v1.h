/*
 * Draft RFVP -> Art3m1s render-host ABI, version 1.
 *
 * This header is an interface proposal for the Host/rfvp integration. It is
 * not yet installed into either runtime.
 *
 * Ownership and lifetime:
 * - Every pointer in a callback argument is non-owning unless explicitly
 *   documented otherwise.
 * - Pointers passed to submit_commands remain valid only until that callback
 *   returns. The host must copy or consume the commands synchronously.
 * - Texture pixels passed to create_texture/update_texture remain valid only
 *   until that callback returns.
 * - The host owns the render target and presentation surface. RFVP only emits
 *   commands into that target.
 *
 * Error convention:
 * - Callbacks return 0 on success and a negative RFVP_RENDER_ERROR_* value on
 *   failure.
 * - Once begin_frame succeeds, end_frame must be called even if a submit
 *   fails. present is optional after a failed frame.
 */

#ifndef RFVP_RENDER_HOST_V1_H
#define RFVP_RENDER_HOST_V1_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define RFVP_RENDER_HOST_ABI_VERSION 1u

typedef enum RfvpRenderErrorV1 {
    RFVP_RENDER_ERROR_NONE = 0,
    RFVP_RENDER_ERROR_INVALID_ARGUMENT = -1,
    RFVP_RENDER_ERROR_UNSUPPORTED = -2,
    RFVP_RENDER_ERROR_OUT_OF_MEMORY = -3,
    RFVP_RENDER_ERROR_DEVICE_LOST = -4,
    RFVP_RENDER_ERROR_BACKEND = -5
} RfvpRenderErrorV1;

typedef enum RfvpTextureFormatV1 {
    RFVP_TEXTURE_FORMAT_RGBA8 = 1,
    RFVP_TEXTURE_FORMAT_LUMA_A8 = 2
} RfvpTextureFormatV1;

typedef enum RfvpBlendModeV1 {
    RFVP_BLEND_OPAQUE = 0,
    RFVP_BLEND_ALPHA = 1,
    RFVP_BLEND_ADD = 2,
    RFVP_BLEND_REVERSE_SUBTRACT = 3,
    RFVP_BLEND_MULTIPLY = 4,
    RFVP_BLEND_SCREEN = 5
} RfvpBlendModeV1;

typedef enum RfvpTextureFilterV1 {
    RFVP_TEXTURE_FILTER_NEAREST = 0,
    RFVP_TEXTURE_FILTER_LINEAR = 1
} RfvpTextureFilterV1;

typedef enum RfvpDrawCommandKindV1 {
    RFVP_DRAW_IMAGE = 1,
    RFVP_DRAW_SOLID = 2,
    RFVP_DRAW_GLYPH = 3
} RfvpDrawCommandKindV1;

enum {
    RFVP_DRAW_FLAG_HAS_CLIP = 1u << 0,
    RFVP_DRAW_FLAG_HAS_MESH = 1u << 1,
    RFVP_DRAW_FLAG_HAS_EFFECT = 1u << 2
};

typedef struct RfvpColorV1 {
    float r;
    float g;
    float b;
    float a;
} RfvpColorV1;

typedef struct RfvpRectI32V1 {
    int32_t x;
    int32_t y;
    int32_t width;
    int32_t height;
} RfvpRectI32V1;

typedef struct RfvpTextureDescV1 {
    uint32_t width;
    uint32_t height;
    uint32_t format; /* RfvpTextureFormatV1 */
    uint32_t row_bytes;
} RfvpTextureDescV1;

typedef struct RfvpTextureRectV1 {
    uint32_t x;
    uint32_t y;
    uint32_t width;
    uint32_t height;
} RfvpTextureRectV1;

typedef struct RfvpVertexV1 {
    float x;
    float y;
    float u;
    float v;
    RfvpColorV1 color;
} RfvpVertexV1;

/*
 * A draw command is a fixed-size POD. Dynamic mesh data is referenced by
 * mesh/mesh_count and is valid only for the duration of submit_commands.
 *
 * image:
 *   texture_id + vertices[4] are authoritative. dst_rect may describe the
 *   untransformed source bounds.
 * solid:
 *   dst_rect + color are authoritative.
 * glyph:
 *   texture_id + dst_rect + color are authoritative.
 */
typedef struct RfvpDrawCommandV1 {
    uint32_t kind; /* RfvpDrawCommandKindV1 */
    uint32_t flags;
    uint32_t texture_id;
    uint32_t blend;  /* RfvpBlendModeV1 */
    uint32_t filter; /* RfvpTextureFilterV1 */
    uint32_t effect_id;

    RfvpRectI32V1 dst_rect;
    RfvpRectI32V1 clip_rect;
    RfvpColorV1 color;

    RfvpVertexV1 vertices[4];

    const RfvpVertexV1* mesh;
    uint32_t mesh_count;
    uint32_t reserved0;
} RfvpDrawCommandV1;

/*
 * The callback table is copied by rfvp_host_create(). The caller may release
 * this structure after create returns.
 */
typedef struct RfvpRenderHostV1 {
    uint32_t abi_version;
    uint32_t struct_size;
    void* user_data;

    int32_t (*create_texture)(
        void* user_data,
        uint32_t texture_id,
        const RfvpTextureDescV1* desc,
        const uint8_t* pixels,
        size_t pixels_size);

    int32_t (*update_texture)(
        void* user_data,
        uint32_t texture_id,
        const RfvpTextureRectV1* rect,
        const uint8_t* pixels,
        size_t pixels_size,
        uint32_t row_bytes);

    void (*destroy_texture)(void* user_data, uint32_t texture_id);

    int32_t (*begin_frame)(
        void* user_data,
        uint32_t width,
        uint32_t height,
        const RfvpColorV1* clear_color);

    int32_t (*submit_commands)(
        void* user_data,
        const RfvpDrawCommandV1* commands,
        uint32_t command_count);

    int32_t (*end_frame)(void* user_data);

    int32_t (*readback)(
        void* user_data,
        uint8_t* rgba,
        size_t capacity,
        size_t* written);

    int32_t (*present)(void* user_data);
} RfvpRenderHostV1;

typedef struct RfvpLogMessageV1 {
    uint32_t level;
    const char* message_utf8;
} RfvpLogMessageV1;

typedef void (*RfvpLogCallbackV1)(
    void* user_data,
    const RfvpLogMessageV1* message);

/*
 * The create signature is proposed, not provided by rfvp 0.6.0.
 *
 * game_root_utf8 and nls_utf8 are required.
 * save_root_utf8 may be NULL to preserve the legacy game_root/save path.
 * render_host may be NULL only for launches that do not render.
 * The returned handle is owned by the caller and released with
 * rfvp_host_destroy().
 */
void* rfvp_host_create(
    const char* game_root_utf8,
    const char* save_root_utf8,
    const char* nls_utf8,
    const RfvpRenderHostV1* render_host,
    RfvpLogCallbackV1 log_callback,
    void* log_user_data);

/* Returns 1 when the engine requests exit, 0 to continue, negative on error. */
int32_t rfvp_host_step(void* handle, uint32_t dt_ms);

/* Deliver one input event through the existing platform-neutral event ABI. */
int32_t rfvp_host_push_event(
    void* handle,
    const void* event,
    size_t event_size);

void rfvp_host_destroy(void* handle);

#ifdef __cplusplus
}
#endif

#endif /* RFVP_RENDER_HOST_V1_H */
