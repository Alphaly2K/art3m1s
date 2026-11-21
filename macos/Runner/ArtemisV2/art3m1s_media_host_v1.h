#ifndef ART3M1S_MEDIA_HOST_V1_H
#define ART3M1S_MEDIA_HOST_V1_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct ArtMediaVideo ArtMediaVideo;
typedef struct ArtMediaAudio ArtMediaAudio;

typedef struct ArtMediaFrame {
    const uint8_t *rgba;
    uint64_t bytes;
    uint64_t pts_us; /* Relative to the common container start. */
    uint64_t duration_us;
    uint32_t width;
    uint32_t height;
} ArtMediaFrame;

typedef struct ArtMediaPcm {
    const int16_t *stereo_i16;
    uint64_t pts_us; /* Same clock as video. Gaps between blocks are silence. */
    uint32_t frames;
} ArtMediaPcm;

typedef struct ArtMediaHostApiV1 {
    uint32_t abi_version;
    uint32_t size;
    /* Open a Host-provided local ASF or Ogg video. NULL means open failed. */
    ArtMediaVideo *(*open_video)(const char *path);
    /* 1 = frame, 0 = end, negative = error. Bytes expire at next call or close.
       At end, pts_us can carry the end time of an implicit image hold. */
    int32_t (*next_video)(ArtMediaVideo *video, ArtMediaFrame *output);
    void (*close_video)(ArtMediaVideo *video);
    /* 1 = opened, 0 = absent audio track, negative = error. */
    int32_t (*open_audio)(const char *path, ArtMediaAudio **audio);
    /* Interleaved 48 kHz stereo PCM. Buffer expires at next call or close. */
    int32_t (*next_audio)(ArtMediaAudio *audio, ArtMediaPcm *output);
    void (*close_audio)(ArtMediaAudio *audio);
} ArtMediaHostApiV1;

/* The API table is immutable. Separate decoders can run concurrently. For each
 * handle, serialize next, close, and reads of the borrowed buffer. Copy its
 * contents before handing them off if the decoder can advance or close. */
const ArtMediaHostApiV1 *art3m1s_artemis_media_get_api_v1(void);

#ifdef __cplusplus
}
#endif

#endif
