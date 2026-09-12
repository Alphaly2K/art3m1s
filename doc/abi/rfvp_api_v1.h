/*
 * RFVP host ABI, version 1 (draft).
 *
 * This header is the design target for the RFVP host adapter. No RFVP build
 * exports rfvp_get_api_v1 until the implementation phases are wired and the
 * table is tested against this layout.
 *
 * Ownership rule:
 * - Objects cross the ABI as opaque, nonzero uint64_t handles.
 * - Object operations take handles plus scalar arguments.
 * - Bulk data uses POD pointers plus element counts or byte lengths. RFVP
 *   copies input blobs when it needs stable storage.
 * - A frame owns the command, texture, vertex, effect, and hit-proxy arrays
 *   exposed by its getter functions until rfvp_frame_release is called.
 *
 * The only eventual flat export in this ABI is rfvp_get_api_v1. Legacy
 * rfvp_run_entry, rfvp_pump_*, rfvp_ios_*, and rfvp_android_* symbols remain
 * outside this versioned table.
 */

#ifndef RFVP_API_V1_H
#define RFVP_API_V1_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define RFVP_API_ABI_VERSION 1u
#define RFVP_API_ABI_MAGIC UINT64_C(0x4950413150564652) /* "RFVP1API" */
#define RFVP_INVALID_HANDLE UINT64_C(0)

typedef int32_t RfvpStatusV1;

enum {
    RFVP_STATUS_OK = 0,
    RFVP_STATUS_NO_FRAME = 1,
    RFVP_STATUS_NO_COMMAND = 2,
    RFVP_STATUS_INVALID_ARGUMENT = -1,
    RFVP_STATUS_INVALID_HANDLE = -2,
    RFVP_STATUS_INVALID_STATE = -3,
    RFVP_STATUS_NOT_FOUND = -4,
    RFVP_STATUS_INVALID_DATA = -5,
    RFVP_STATUS_UNSUPPORTED = -6,
    RFVP_STATUS_OUT_OF_MEMORY = -7,
    RFVP_STATUS_BUSY = -8,
    RFVP_STATUS_IO = -9,
    RFVP_STATUS_ENGINE = -10
};

typedef enum RfvpNlsV1 {
    RFVP_NLS_SHIFT_JIS = 1,
    RFVP_NLS_GBK = 2,
    RFVP_NLS_UTF8 = 3
} RfvpNlsV1;

typedef enum RfvpSerializationV1 {
    RFVP_SERIALIZATION_UTF8_TEXT = 1,
    RFVP_SERIALIZATION_JSON = 2,
    RFVP_SERIALIZATION_BINARY_V1 = 3
} RfvpSerializationV1;

typedef enum RfvpEventKindV1 {
    RFVP_EVENT_LOG = 1,
    RFVP_EVENT_MEDIA = 2,
    RFVP_EVENT_UI = 3,
    RFVP_EVENT_TEXT_TRANSLATION = 4
} RfvpEventKindV1;

typedef enum RfvpInputKindV1 {
    RFVP_INPUT_KEY = 1,
    RFVP_INPUT_TEXT = 2,
    RFVP_INPUT_POINTER_MOVE = 3,
    RFVP_INPUT_POINTER_BUTTON = 4,
    RFVP_INPUT_WHEEL = 5,
    RFVP_INPUT_TOUCH = 6,
    RFVP_INPUT_FOCUS = 7,
    RFVP_INPUT_QUIT = 8
} RfvpInputKindV1;

enum {
    RFVP_INPUT_PHASE_DOWN = 0,
    RFVP_INPUT_PHASE_UP = 1,
    RFVP_INPUT_PHASE_REPEAT = 2,
    RFVP_INPUT_PHASE_MOVE = 3
};

enum {
    RFVP_POINTER_LEFT = 1u << 0,
    RFVP_POINTER_RIGHT = 1u << 1,
    RFVP_POINTER_MIDDLE = 1u << 2
};

enum {
    RFVP_KEY_BACKSPACE = 8,
    RFVP_KEY_TAB = 9,
    RFVP_KEY_RETURN = 13,
    RFVP_KEY_ESCAPE = 27,
    RFVP_KEY_SPACE = 32,
    RFVP_KEY_PAGE_UP = 33,
    RFVP_KEY_PAGE_DOWN = 34,
    RFVP_KEY_END = 35,
    RFVP_KEY_HOME = 36,
    RFVP_KEY_LEFT = 37,
    RFVP_KEY_UP = 38,
    RFVP_KEY_RIGHT = 39,
    RFVP_KEY_DOWN = 40,
    RFVP_KEY_INSERT = 45,
    RFVP_KEY_DELETE = 46,
    RFVP_KEY_SHIFT = 16,
    RFVP_KEY_CONTROL = 17,
    RFVP_KEY_ALT = 18
};

#define RFVP_MODIFIER_SHIFT (1u << 0)
#define RFVP_MODIFIER_CONTROL (1u << 1)
#define RFVP_MODIFIER_ALT (1u << 2)
#define RFVP_MODIFIER_SUPER (1u << 3)

typedef enum RfvpTextureFormatV1 {
    RFVP_TEXTURE_FORMAT_RGBA8 = 1,
    RFVP_TEXTURE_FORMAT_LUMA_A8 = 2
} RfvpTextureFormatV1;

typedef enum RfvpTextureCommandKindV1 {
    RFVP_TEXTURE_CREATE = 1,
    RFVP_TEXTURE_UPDATE = 2,
    RFVP_TEXTURE_DESTROY = 3
} RfvpTextureCommandKindV1;

typedef enum RfvpBlendModeV1 {
    RFVP_BLEND_NORMAL = 0,
    RFVP_BLEND_ADD = 1,
    RFVP_BLEND_REVERSE_SUBTRACT = 2,
    RFVP_BLEND_MULTIPLY = 3,
    RFVP_BLEND_SCREEN = 4
} RfvpBlendModeV1;

typedef enum RfvpTextureFilterV1 {
    RFVP_TEXTURE_FILTER_NEAREST = 0,
    RFVP_TEXTURE_FILTER_LINEAR = 1
} RfvpTextureFilterV1;

typedef enum RfvpDrawKindV1 {
    RFVP_DRAW_IMAGE = 1,
    RFVP_DRAW_GLYPH = 2,
    RFVP_DRAW_SOLID = 3
} RfvpDrawKindV1;

typedef enum RfvpMeshTopologyV1 {
    RFVP_MESH_TRIANGLE_LIST = 1,
    RFVP_MESH_TRIANGLE_STRIP = 2
} RfvpMeshTopologyV1;

typedef enum RfvpLifecycleStateV1 {
    RFVP_LIFECYCLE_BACKGROUND = 1,
    RFVP_LIFECYCLE_FOREGROUND = 2,
    RFVP_LIFECYCLE_EXIT = 3
} RfvpLifecycleStateV1;

typedef enum RfvpRenderQualityPresetV1 {
    RFVP_RENDER_QUALITY_NATIVE = 0,
    RFVP_RENDER_QUALITY_QUALITY = 1,
    RFVP_RENDER_QUALITY_BALANCED = 2,
    RFVP_RENDER_QUALITY_PERFORMANCE = 3
} RfvpRenderQualityPresetV1;

typedef enum RfvpVolumeChannelV1 {
    RFVP_VOLUME_MASTER = 1,
    RFVP_VOLUME_BGM = 2,
    RFVP_VOLUME_SE = 3,
    RFVP_VOLUME_VOICE = 4
} RfvpVolumeChannelV1;

typedef enum RfvpAudioCommandKindV1 {
    RFVP_AUDIO_LOAD_ENCODED = 1,
    RFVP_AUDIO_CREATE_STREAM = 2,
    RFVP_AUDIO_SUBMIT_I16 = 3,
    RFVP_AUDIO_SUBMIT_F32 = 4,
    RFVP_AUDIO_PLAY = 5,
    RFVP_AUDIO_STOP = 6,
    RFVP_AUDIO_PAUSE = 7,
    RFVP_AUDIO_RESUME = 8,
    RFVP_AUDIO_SET_PARAMS = 9,
    RFVP_AUDIO_DESTROY_STREAM = 10,
    RFVP_AUDIO_MASTER_VOLUME = 11
} RfvpAudioCommandKindV1;

typedef enum RfvpAudioSampleFormatV1 {
    RFVP_AUDIO_SAMPLE_I16 = 1,
    RFVP_AUDIO_SAMPLE_F32 = 2
} RfvpAudioSampleFormatV1;

typedef enum RfvpAudioEncodedKindV1 {
    RFVP_AUDIO_ENCODED_UNKNOWN = 0,
    RFVP_AUDIO_ENCODED_WAV = 1,
    RFVP_AUDIO_ENCODED_OGG = 2,
    RFVP_AUDIO_ENCODED_MP3 = 3,
    RFVP_AUDIO_ENCODED_FLAC = 4
} RfvpAudioEncodedKindV1;

enum {
    RFVP_DRAW_FLAG_HAS_CLIP = 1u << 0,
    RFVP_DRAW_FLAG_HAS_MESH = 1u << 1,
    RFVP_DRAW_FLAG_HAS_EFFECT = 1u << 2,
    RFVP_DRAW_FLAG_HAS_SRC_RECT = 1u << 3
};

enum {
    RFVP_HIT_PROXY_ENABLED = 1u << 0,
    RFVP_HIT_PROXY_VISIBLE = 1u << 1
};

enum {
    RFVP_CAPABILITY_EVENTS = UINT64_C(1) << 0,
    RFVP_CAPABILITY_TEXTURES = UINT64_C(1) << 1,
    RFVP_CAPABILITY_DRAW_IMAGE = UINT64_C(1) << 2,
    RFVP_CAPABILITY_DRAW_GLYPH = UINT64_C(1) << 3,
    RFVP_CAPABILITY_DRAW_MESH = UINT64_C(1) << 4,
    RFVP_CAPABILITY_DRAW_EFFECTS = UINT64_C(1) << 5,
    RFVP_CAPABILITY_HIT_PROXIES = UINT64_C(1) << 6,
    RFVP_CAPABILITY_TEXT_REPLACEMENTS = UINT64_C(1) << 7,
    RFVP_CAPABILITY_TEXT_TRANSLATION = UINT64_C(1) << 8,
    RFVP_CAPABILITY_NATIVE_SURFACE = UINT64_C(1) << 9,
    RFVP_CAPABILITY_AUDIO_COMMANDS = UINT64_C(1) << 10
};

#define RFVP_TEXTURE_ID_WHITE UINT32_MAX

typedef struct RfvpResourcesConfigV1 {
    uint32_t struct_size;
    uint32_t flags;
    uint32_t nls; /* RfvpNlsV1 */
    uint32_t reserved0;

    const uint8_t* save_root_utf8;
    size_t save_root_len;
    uint64_t reserved[4];
} RfvpResourcesConfigV1;

typedef struct RfvpRuntimeConfigV1 {
    uint32_t struct_size;
    uint32_t flags;
    uint64_t resources;
    uint32_t requested_width;
    uint32_t requested_height;
    uint64_t reserved[4];
} RfvpRuntimeConfigV1;

/*
 * Input is an array of fixed-size POD records. Meaning by kind:
 * - KEY: code=RFVP_KEY_*, phase, id=0, modifiers
 * - TEXT: code=Unicode scalar value, phase=DOWN
 * - POINTER_MOVE: x/y, id=0
 * - POINTER_BUTTON: code=RFVP_POINTER_*, phase=DOWN/UP, x/y
 * - WHEEL: x=delta_x, y=delta_y
 * - TOUCH: id=touch id, phase=DOWN/MOVE/UP, x/y
 * - FOCUS: phase=0 lost/1 gained
 * - QUIT: no additional fields
 */
typedef struct RfvpInputEventV1 {
    uint32_t struct_size;
    uint32_t kind; /* RfvpInputKindV1 */
    uint32_t code;
    uint32_t phase;
    int32_t x;
    int32_t y;
    int32_t value;
    uint32_t modifiers;
    uint64_t id;
} RfvpInputEventV1;

/*
 * Audio commands are copied into the caller-provided structure by
 * rfvp_runtime_poll_audio_command(). payload points at RFVP-owned storage and
 * remains valid until the next poll call or runtime destruction.
 *
 * stream_id is the RFVP logical stream id: BGM slots are 0..255 and SE slots
 * start at 0x1000. The host maps these ids to its own audio backend.
 */
typedef struct RfvpAudioCommandV1 {
    uint32_t struct_size;
    uint32_t kind;          /* RfvpAudioCommandKindV1 */
    uint32_t stream_id;
    uint32_t sample_format; /* RfvpAudioSampleFormatV1 */
    uint32_t encoded_kind;  /* RfvpAudioEncodedKindV1 */
    uint32_t sample_rate;
    uint32_t channels;
    uint32_t repeat;
    uint32_t fade_ms;
    float volume;
    float pan;
    size_t sample_count;
    const uint8_t* payload;
    size_t payload_size;
    uint64_t reserved[2];
} RfvpAudioCommandV1;

typedef struct RfvpColorV1 {
    float r;
    float g;
    float b;
    float a;
} RfvpColorV1;

typedef struct RfvpRectU16V1 {
    uint16_t x;
    uint16_t y;
    uint16_t width;
    uint16_t height;
} RfvpRectU16V1;

typedef struct RfvpRectI32V1 {
    int32_t x;
    int32_t y;
    int32_t width;
    int32_t height;
} RfvpRectI32V1;

typedef struct RfvpVertexV1 {
    float x;
    float y;
    float u;
    float v;
    RfvpColorV1 color;
} RfvpVertexV1;

/*
 * Texture commands are frame-owned and must be applied before draw commands.
 *
 * CREATE uploads or replaces the complete texture identified by texture_id.
 * UPDATE replaces rect inside the current texture and uses row_bytes for the
 * first row of rect. DESTROY releases the texture.
 *
 * generation changes when the same runtime-local texture id receives new
 * pixels. A repeated CREATE with the same (texture_id, generation) may be
 * ignored by a host that already has that revision. Pixels point directly at
 * RFVP CPU storage and remain valid until rfvp_frame_release.
 */
typedef struct RfvpTextureCommandV1 {
    uint32_t struct_size;
    uint32_t kind; /* RfvpTextureCommandKindV1 */
    uint32_t texture_id;
    uint32_t format; /* RfvpTextureFormatV1 */
    uint32_t width;
    uint32_t height;
    uint32_t mip_count;
    uint32_t row_bytes;

    RfvpRectI32V1 rect;
    uint64_t generation;

    const uint8_t* pixels;
    size_t pixels_size;
    uint64_t reserved[2];
} RfvpTextureCommandV1;

/*
 * Draw commands are fixed-size POD.
 *
 * IMAGE and GLYPH use texture_id and vertices[4]. SRC_RECT is valid only when
 * HAS_SRC_RECT is set. SOLID uses dst_rect and color.
 *
 * When HAS_MESH is set, mesh points into frame-owned vertex storage and is
 * valid until rfvp_frame_release. When HAS_EFFECT is set, effect_data is a
 * frame-owned POD/uniform block and effect_id selects the engine effect.
 */
typedef struct RfvpDrawCommandV1 {
    uint32_t struct_size;
    uint32_t kind; /* RfvpDrawKindV1 */
    uint32_t flags;
    uint32_t texture_id;
    uint32_t blend;  /* RfvpBlendModeV1 */
    uint32_t filter; /* RfvpTextureFilterV1 */
    uint32_t effect_id;
    uint32_t mesh_topology; /* RfvpMeshTopologyV1 */

    RfvpRectU16V1 src_rect;
    RfvpRectI32V1 dst_rect;
    RfvpRectI32V1 clip_rect;
    RfvpColorV1 color;
    RfvpVertexV1 vertices[4];

    const RfvpVertexV1* mesh;
    size_t mesh_vertex_count;
    const uint8_t* effect_data;
    size_t effect_data_size;
    uint64_t reserved[2];
} RfvpDrawCommandV1;

typedef struct RfvpHitProxyV1 {
    uint32_t prim_id;
    uint32_t flags;
    RfvpRectI32V1 rect;
    uint32_t order;
    uint32_t reserved0;
} RfvpHitProxyV1;

typedef struct RfvpEventHeaderV1 {
    uint32_t abi_version;
    uint32_t kind; /* RfvpEventKindV1 */
    uint64_t sequence;
    uint32_t payload_size;
    uint32_t aux;
} RfvpEventHeaderV1;

/*
 * RFVP_EVENT_TEXT_TRANSLATION payload:
 *   RfvpTextTranslationEventV1 followed by UTF-8 source and ruby bytes at
 *   source_offset and ruby_offset. ruby_len may be zero.
 *
 * Submit the result with rfvp_runtime_submit_text_translation(serial, ...).
 * RFVP rejects stale results after slot generation changes.
 */
typedef struct RfvpTextTranslationEventV1 {
    uint32_t struct_size;
    uint32_t encoding; /* RfvpSerializationV1 */
    uint64_t serial;
    uint64_t generation;
    uint32_t slot;
    uint32_t source_offset;
    uint32_t source_len;
    uint32_t ruby_offset;
    uint32_t ruby_len;
    uint32_t reserved0;
} RfvpTextTranslationEventV1;

typedef int32_t (*RfvpResourcesCreateFn)(
    const RfvpResourcesConfigV1* config,
    uint64_t* out_resources);

typedef void (*RfvpResourcesDestroyFn)(uint64_t resources);
typedef void (*RfvpResourcesClearFn)(uint64_t resources);

typedef int32_t (*RfvpResourcesMountDirectoryFn)(
    uint64_t resources,
    const uint8_t* path_utf8,
    size_t path_len);

typedef int32_t (*RfvpResourcesMountPackFn)(
    uint64_t resources,
    const uint8_t* folder_utf8,
    size_t folder_len,
    const uint8_t* pack_data,
    size_t pack_size);

typedef int32_t (*RfvpResourcesSetOverrideFn)(
    uint64_t resources,
    const uint8_t* path_utf8,
    size_t path_len,
    const uint8_t* data,
    size_t data_size);

typedef void (*RfvpResourcesClearOverridesFn)(uint64_t resources);

typedef int32_t (*RfvpResourcesSetSaveRootFn)(
    uint64_t resources,
    const uint8_t* path_utf8,
    size_t path_len);

typedef int32_t (*RfvpRuntimeCreateFn)(
    const RfvpRuntimeConfigV1* config,
    uint64_t* out_runtime);

typedef void (*RfvpRuntimeDestroyFn)(uint64_t runtime);
typedef int32_t (*RfvpRuntimeStepFn)(uint64_t runtime, uint32_t delta_ms);
typedef int32_t (*RfvpRuntimeIsExitRequestedFn)(uint64_t runtime);
typedef int32_t (*RfvpRuntimeEventsEnableFn)(uint64_t runtime, int32_t enabled);
typedef size_t (*RfvpRuntimeNextEventSizeFn)(uint64_t runtime);

typedef size_t (*RfvpRuntimePollEventsFn)(
    uint64_t runtime,
    uint8_t* out,
    size_t capacity,
    uint32_t* out_count);

typedef int32_t (*RfvpRuntimePushInputFn)(
    uint64_t runtime,
    const RfvpInputEventV1* events,
    size_t event_count);

typedef int32_t (*RfvpRuntimeSetTextHidpiFn)(
    uint64_t runtime,
    int32_t enabled);

typedef int32_t (*RfvpRuntimeSetTextReplacementsFn)(
    uint64_t runtime,
    const uint8_t* blob,
    size_t blob_size,
    uint32_t encoding);

typedef int32_t (*RfvpRuntimeSetTextTranslationEnabledFn)(
    uint64_t runtime,
    int32_t enabled);

typedef int32_t (*RfvpRuntimeSubmitTextTranslationFn)(
    uint64_t runtime,
    uint64_t serial,
    const uint8_t* translated_utf8,
    size_t translated_len);

typedef int32_t (*RfvpRuntimeSetRenderQualityPresetFn)(
    uint64_t runtime,
    int32_t preset);

typedef int32_t (*RfvpRuntimeSetMediaEnabledFn)(
    uint64_t runtime,
    int32_t enabled);

typedef int32_t (*RfvpRuntimeNotifyLifecycleFn)(
    uint64_t runtime,
    int32_t state);

typedef int32_t (*RfvpRuntimeSetVolumeFn)(
    uint64_t runtime,
    uint32_t channel,
    float value);

typedef int32_t (*RfvpRuntimePollAudioCommandFn)(
    uint64_t runtime,
    RfvpAudioCommandV1* out_command);

typedef uint64_t (*RfvpRuntimeCapabilitiesFn)(uint64_t runtime);

typedef int32_t (*RfvpRuntimeAcquireFrameFn)(
    uint64_t runtime,
    uint64_t* out_frame);

typedef void (*RfvpFrameReleaseFn)(uint64_t frame);

typedef int32_t (*RfvpFrameGetSizeFn)(
    uint64_t frame,
    uint32_t* out_width,
    uint32_t* out_height);

typedef int32_t (*RfvpFrameGetCommandsFn)(
    uint64_t frame,
    const RfvpDrawCommandV1** out_commands,
    size_t* out_count);

typedef int32_t (*RfvpFrameGetTexturesFn)(
    uint64_t frame,
    const RfvpTextureCommandV1** out_commands,
    size_t* out_count);

typedef int32_t (*RfvpFrameGetHitProxiesFn)(
    uint64_t frame,
    const RfvpHitProxyV1** out_proxies,
    size_t* out_count);

/*
 * Append-only versioned function table.
 *
 * Hosts must validate struct_size, abi_version, and magic before reading any
 * function pointer. A null function pointer means that capability is absent;
 * callers must not treat table presence as implementation presence.
 */
typedef struct RfvpApiV1 {
    uint32_t struct_size;
    uint32_t abi_version;
    uint64_t magic;

    RfvpResourcesCreateFn resources_create;
    RfvpResourcesDestroyFn resources_destroy;
    RfvpResourcesClearFn resources_clear;
    RfvpResourcesMountDirectoryFn resources_mount_directory;
    RfvpResourcesMountPackFn resources_mount_pack;
    RfvpResourcesSetOverrideFn resources_set_override;
    RfvpResourcesClearOverridesFn resources_clear_overrides;
    RfvpResourcesSetSaveRootFn resources_set_save_root;

    RfvpRuntimeCreateFn runtime_create;
    RfvpRuntimeDestroyFn runtime_destroy;
    RfvpRuntimeStepFn runtime_step;
    RfvpRuntimeIsExitRequestedFn runtime_is_exit_requested;

    RfvpRuntimeEventsEnableFn runtime_events_enable;
    RfvpRuntimeNextEventSizeFn runtime_next_event_size;
    RfvpRuntimePollEventsFn runtime_poll_events;

    RfvpRuntimePushInputFn runtime_push_input;
    RfvpRuntimeSetTextHidpiFn runtime_set_text_hidpi;
    RfvpRuntimeSetTextReplacementsFn runtime_set_text_replacements;
    RfvpRuntimeSetTextTranslationEnabledFn runtime_set_text_translation_enabled;
    RfvpRuntimeSubmitTextTranslationFn runtime_submit_text_translation;
    RfvpRuntimeSetRenderQualityPresetFn runtime_set_render_quality_preset;
    RfvpRuntimeSetMediaEnabledFn runtime_set_media_enabled;
    RfvpRuntimeNotifyLifecycleFn runtime_notify_lifecycle;
    RfvpRuntimeSetVolumeFn runtime_set_volume;
    RfvpRuntimePollAudioCommandFn runtime_poll_audio_command;
    RfvpRuntimeCapabilitiesFn runtime_capabilities;

    RfvpRuntimeAcquireFrameFn runtime_acquire_frame;
    RfvpFrameReleaseFn frame_release;
    RfvpFrameGetSizeFn frame_get_size;
    RfvpFrameGetCommandsFn frame_get_commands;
    RfvpFrameGetTexturesFn frame_get_textures;
    RfvpFrameGetHitProxiesFn frame_get_hit_proxies;
} RfvpApiV1;

/*
 * The eventual only exported symbol of the new RFVP ABI.
 *
 * out_size receives the exact table size known to this build. Hosts must keep
 * a copy of the returned table pointer for the process lifetime and reject a
 * shorter table before reading unknown fields.
 */
const RfvpApiV1* rfvp_get_api_v1(size_t* out_size);

#if defined(__cplusplus)
#define RFVP_STATIC_ASSERT static_assert
#else
#define RFVP_STATIC_ASSERT _Static_assert
#endif

RFVP_STATIC_ASSERT(sizeof(RfvpEventHeaderV1) == 24,
                   "RfvpEventHeaderV1 size changed");
RFVP_STATIC_ASSERT(offsetof(RfvpEventHeaderV1, sequence) == 8,
                   "RfvpEventHeaderV1.sequence layout changed");
RFVP_STATIC_ASSERT(offsetof(RfvpEventHeaderV1, payload_size) == 16,
                   "RfvpEventHeaderV1.payload_size layout changed");

RFVP_STATIC_ASSERT(offsetof(RfvpTextTranslationEventV1, serial) == 8,
                   "RfvpTextTranslationEventV1.serial layout changed");
RFVP_STATIC_ASSERT(offsetof(RfvpTextTranslationEventV1, generation) == 16,
                   "RfvpTextTranslationEventV1.generation layout changed");
RFVP_STATIC_ASSERT(offsetof(RfvpTextTranslationEventV1, source_offset) == 28,
                   "RfvpTextTranslationEventV1.source_offset layout changed");
RFVP_STATIC_ASSERT(offsetof(RfvpTextTranslationEventV1, ruby_offset) == 36,
                   "RfvpTextTranslationEventV1.ruby_offset layout changed");

RFVP_STATIC_ASSERT(offsetof(RfvpVertexV1, u) == 8,
                   "RfvpVertexV1.u layout changed");
RFVP_STATIC_ASSERT(offsetof(RfvpVertexV1, color) == 16,
                   "RfvpVertexV1.color layout changed");
RFVP_STATIC_ASSERT(sizeof(RfvpVertexV1) == 32,
                   "RfvpVertexV1 size changed");

RFVP_STATIC_ASSERT(offsetof(RfvpDrawCommandV1, src_rect) == 32,
                   "RfvpDrawCommandV1.src_rect layout changed");
RFVP_STATIC_ASSERT(offsetof(RfvpDrawCommandV1, vertices) == 88,
                   "RfvpDrawCommandV1.vertices layout changed");

#undef RFVP_STATIC_ASSERT

#ifdef __cplusplus
}
#endif

#endif /* RFVP_API_V1_H */
