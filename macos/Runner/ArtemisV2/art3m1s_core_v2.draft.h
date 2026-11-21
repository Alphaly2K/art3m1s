/* Preview interface. Build with --manifest-path crates/artemis-core/Cargo.toml.
 * See ../HOST_ABI_V2.md for the protocol. The default legacy build exposes v1.
 * Native structs use the target C ABI; queued records use explicit LE encoding.
 */
#ifndef ART3M1S_CORE_V2_DRAFT_H
#define ART3M1S_CORE_V2_DRAFT_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef int32_t ArtStatus;
typedef uint64_t ArtRuntimeHandle;
typedef uint64_t ArtFrameToken;

#define ART_OK INT32_C(0)
#define ART_NO_DATA INT32_C(1)
#define ART_WOULD_BLOCK INT32_C(2)
#define ART_E_ARGUMENT (-INT32_C(1))
#define ART_E_HANDLE (-INT32_C(2))
#define ART_E_THREAD (-INT32_C(3))
#define ART_E_UNSUPPORTED (-INT32_C(4))
#define ART_E_BUFFER (-INT32_C(5))
#define ART_E_STATE (-INT32_C(6))
#define ART_E_STALE (-INT32_C(7))
#define ART_E_LIMIT (-INT32_C(8))
#define ART_E_PANIC (-INT32_C(9))

#define ART_API_MAGIC UINT64_C(0x415254334D324150)
#define ART_INTERFACE_RUNTIME UINT32_C(1)
#define ART_INTERFACE_FRAME UINT32_C(2)
#define ART_INTERFACE_CAPABILITIES UINT32_C(3)
#define ART_ABI_V2_MAJOR UINT32_C(2)
#define ART_SUBMIT_SCHEMA_VERSION UINT16_C(1)

/* poll_events record prefix: little-endian envelope followed by two body lengths. */
#define ART_EVENT_ENVELOPE_VERSION UINT16_C(2)
#define ART_EVENT_ENVELOPE_BYTES UINT32_C(56)
#define ART_EVENT_BODY_HEADER_BYTES UINT32_C(8)
#define ART_EVENT_FLAG_REQUIRES_REPLY UINT32_C(1)
#define ART_EVENT_FLAG_CRITICAL UINT32_C(2)
#define ART_EVENT_FLAG_JSON_BLOB UINT32_C(256)

#define ART_HOST_CAP_IO UINT64_C(1)
#define ART_HOST_CAP_UI UINT64_C(2)
#define ART_HOST_CAP_MEDIA UINT64_C(4)
#define ART_HOST_CAP_HTTP UINT64_C(8)
#define ART_HOST_CAP_TRANSLATION UINT64_C(16)
#define ART_HOST_CAP_CHUNKED_WRITES UINT64_C(32)
#define ART_HOST_CAP_PROJECT_SAVE_PATH UINT64_C(64)
#define ART_HOST_CAP_OPEN_BROWSER UINT64_C(128)
#define ART_RENDERER_CAP_SPRITE UINT64_C(1)
#define ART_RENDERER_CAP_TRANSITION UINT64_C(2)
#define ART_RENDERER_CAP_SCREENSHOT UINT64_C(4)
#define ART_RENDERER_CAP_GROUP UINT64_C(8)
#define ART_RENDERER_CAP_EMOTE UINT64_C(16)
#define ART_RENDERER_CAP_HLSL UINT64_C(32)
#define ART_RENDERER_CAP_GLSL UINT64_C(64)

#define ART_WAIT_IO UINT32_C(1)
#define ART_WAIT_UI UINT32_C(2)
#define ART_WAIT_SCENARIO UINT32_C(4)
#define ART_STEP_SCENARIO_FINISHED UINT32_C(8)
#define ART_WAIT_RENDER UINT32_C(16)
#define ART_STEP_BACKGROUND_AUTOSAVE UINT32_C(1) /* ArtStepInfo.flags */

#define ART_RUNTIME_CREATED UINT32_C(0)
#define ART_RUNTIME_LOADING UINT32_C(1)
#define ART_RUNTIME_RUNNING UINT32_C(2)
#define ART_RUNTIME_CLOSING UINT32_C(3)
#define ART_RUNTIME_CLOSED UINT32_C(4)
#define ART_RUNTIME_FAULTED UINT32_C(5)

#define ART_DOMAIN_RUNTIME UINT16_C(1)
#define ART_DOMAIN_INPUT UINT16_C(2)
#define ART_DOMAIN_IO UINT16_C(3)
#define ART_DOMAIN_UI UINT16_C(4)
#define ART_DOMAIN_MEDIA UINT16_C(5)
#define ART_DOMAIN_RENDER UINT16_C(6)
#define ART_DOMAIN_DIAGNOSTICS UINT16_C(7)

#define ART_RUNTIME_SESSION_CHANGED UINT32_C(1)
#define ART_RUNTIME_PROJECT_READY UINT32_C(2)
#define ART_RUNTIME_EXIT_REQUESTED UINT32_C(3)
#define ART_RUNTIME_CLOSED_EVENT UINT32_C(4)
#define ART_RUNTIME_PERSISTENCE_RESULT UINT32_C(5)
#define ART_UI_CAPTION UINT32_C(1)
#define ART_UI_DIALOG UINT32_C(2)
#define ART_UI_WINDOW_ACTION UINT32_C(3)
#define ART_UI_AVOID UINT32_C(4)
#define ART_UI_HTTP_REQUEST UINT32_C(5)
#define ART_UI_HTTP_CANCEL UINT32_C(6)
#define ART_UI_TRANSLATE UINT32_C(7)
#define ART_UI_OPEN_BROWSER UINT32_C(8)
#define ART_IO_STAT UINT32_C(1)
#define ART_IO_READ UINT32_C(2)
#define ART_IO_WRITE_ATOMIC UINT32_C(4)
#define ART_IO_DELETE UINT32_C(5)
#define ART_IO_WRITE_ABORT UINT32_C(6)
#define ART_RUNTIME_SHUTDOWN UINT32_C(16)
#define ART_RUNTIME_SET_DEFAULT_FONT UINT32_C(17)
#define ART_INPUT_KEY UINT32_C(1)
#define ART_INPUT_POINTER UINT32_C(2)
#define ART_INPUT_TOUCH UINT32_C(3)
#define ART_INPUT_FOCUS_LOST UINT32_C(4)
#define ART_INPUT_WINDOW_BUTTON UINT32_C(5)
#define ART_INPUT_WINDOW_STATE UINT32_C(6)
#define ART_MEDIA_AUDIO_COMMAND UINT32_C(1)
#define ART_MEDIA_VIDEO_COMMAND UINT32_C(2)
#define ART_MEDIA_PLAYBACK_STATUS UINT32_C(16)
#define ART_MEDIA_VIDEO_FRAME UINT32_C(17)
#define ART_RENDER_CAPTURE UINT32_C(1)
#define ART_RENDER_SAVE_CAPTURE UINT32_C(2)
#define ART_DIAGNOSTIC_SHADER_UNAVAILABLE UINT32_C(1)
#define ART_DIAGNOSTIC_SCRIPT_PRINT UINT32_C(2)

/* Draft ARFP packet; see HOST_ABI_V2.md for the little-endian format. */
#define ART_FRAME_SCHEMA_VERSION UINT16_C(1)
#define ART_FRAME_FORMAT_RGBA8_STRAIGHT_TOP UINT16_C(1)
#define ART_FRAME_OP_SPRITE UINT16_C(1)
#define ART_FRAME_OP_TRANSITION UINT16_C(2)
#define ART_FRAME_OP_GROUP UINT16_C(3)
#define ART_FRAME_OP_MESH UINT16_C(4)
#define ART_FRAME_OP_STENCIL UINT16_C(5)
#define ART_FRAME_OP_SHADER UINT16_C(6)
#define ART_FRAME_OP_SHADER_EFFECT UINT16_C(7)
#define ART_FRAME_NO_TEXTURE UINT32_MAX

typedef struct ArtBytes {
    const uint8_t *data;
    uint64_t size;
} ArtBytes;

typedef struct ArtApiHeader {
    uint64_t magic;
    uint32_t struct_size;
    uint32_t interface_id; /* 0 for root. */
    uint32_t abi_major;
    uint32_t abi_minor;
} ArtApiHeader;

typedef struct ArtCreateInfo {
    uint32_t struct_size;
    uint32_t flags;
    uint64_t host_service_caps;
    uint64_t renderer_caps;
    uint64_t random_seed;
} ArtCreateInfo;

typedef struct ArtProjectInfo {
    uint32_t struct_size;
    uint32_t flags;
    ArtBytes ini_bytes; /* Original bytes; charset remains engine semantics. */
    ArtBytes platform_utf8; /* INI section, e.g. WINDOWS; no trailing NUL. */
    ArtBytes reported_os_utf8;
} ArtProjectInfo;

typedef struct ArtStepInfo {
    uint32_t struct_size;
    uint32_t flags;
    uint64_t host_frame_id;
    uint64_t monotonic_ns;
    int64_t utc_unix_ms;
    int32_t utc_offset_minutes;
    uint32_t reserved;
} ArtStepInfo;

/* A fixed-stride array of ArtMessage; each struct_size must equal sizeof(ArtMessage).
 * Input memory is copied before return. Input, output, and borrowed views must not overlap.
 */
typedef struct ArtMessage {
    uint32_t struct_size;
    uint16_t domain;
    uint16_t schema_version;
    uint32_t kind;
    uint32_t flags;
    uint64_t session_epoch;
    uint64_t request_id;
    ArtBytes metadata_utf8;
    ArtBytes blob;
} ArtMessage;

typedef struct ArtRuntimeState {
    uint32_t struct_size;
    uint32_t state;
    uint64_t session_epoch;
    uint64_t host_frame_id;
    uint32_t stage_width;
    uint32_t stage_height;
    uint32_t wait_flags;
    uint32_t exit_requested;
    uint64_t pending_requests;
    uint64_t control_queue_bytes;
    uint64_t dropped_diagnostic_records;
} ArtRuntimeState;

typedef struct ArtStepResult {
    uint32_t struct_size;
    uint32_t flags;
    uint64_t host_frame_id;
    uint64_t latest_render_frame_id;
    uint64_t pending_requests;
} ArtStepResult;

typedef struct ArtPollResult {
    uint32_t struct_size;
    uint32_t record_count;
    uint64_t written_bytes;
    uint64_t required_next_bytes;
} ArtPollResult;

/* Packet is immutable and valid until release(rt, token), including across step.
 * A token pins all referenced CPU resource revisions, never platform objects.
 */
typedef struct ArtFrameView {
    uint32_t struct_size;
    uint32_t schema_version;
    uint64_t session_epoch;
    uint64_t render_frame_id;
    ArtFrameToken token;
    ArtBytes packet;
} ArtFrameView;

typedef struct ArtRuntimeApiV2 {
    ArtApiHeader header;
    ArtStatus (*create)(const ArtCreateInfo *, ArtRuntimeHandle *out_runtime);
    ArtStatus (*destroy)(ArtRuntimeHandle);
    /* Success means accepted; Loading completes through step + events/state. */
    ArtStatus (*open_project)(ArtRuntimeHandle, const ArtProjectInfo *);
    ArtStatus (*step)(ArtRuntimeHandle, const ArtStepInfo *, ArtStepResult *out);
    /* The batch is accepted atomically, or no messages are accepted. */
    ArtStatus (*submit)(ArtRuntimeHandle, const ArtMessage *, uint32_t count);
    ArtStatus (*poll_events)(ArtRuntimeHandle, uint8_t *output,
                             uint64_t capacity, ArtPollResult *out);
    ArtStatus (*get_state)(ArtRuntimeHandle, ArtRuntimeState *out);
} ArtRuntimeApiV2;

typedef struct ArtFrameApiV2 {
    ArtApiHeader header;
    ArtStatus (*acquire_latest)(ArtRuntimeHandle, uint64_t after_render_frame_id,
                                ArtFrameView *out);
    ArtStatus (*release)(ArtRuntimeHandle, ArtFrameToken);
    /* Frame-local texture index. The returned bytes expire with the token. */
    ArtStatus (*texture_rgba)(ArtRuntimeHandle, ArtFrameToken, uint32_t index,
                              ArtBytes *out_pixels);
} ArtFrameApiV2;

/* Optional information table. Its masks list the bits accepted by create. */
typedef struct ArtCapabilitiesV2 {
    ArtApiHeader header;
    uint64_t host_service_caps;
    uint64_t renderer_caps;
} ArtCapabilitiesV2;

typedef struct ArtRootApiV2 {
    ArtApiHeader header;
    ArtStatus (*query_interface)(uint32_t interface_id, uint32_t abi_major,
                                 uint32_t minimum_size, const void **out_table);
    /* UTF-8, no NUL; on E_BUFFER writes required size and consumes nothing.
     * Error is thread-local and remains readable after create/query failure.
     */
    ArtStatus (*copy_last_error)(uint8_t *output, uint64_t capacity,
                                 uint64_t *out_required);
} ArtRootApiV2;

/* Sole dynamic query symbol in the standalone v2 preview. */
ArtStatus art3m1s_get_api_v2(uint32_t abi_major, uint32_t minimum_root_size,
                            const ArtRootApiV2 **out_api);

#ifdef __cplusplus
}
#endif
#endif
