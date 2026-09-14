#ifndef ART3M1S_AUDIO_DECODE_SHIM_H
#define ART3M1S_AUDIO_DECODE_SHIM_H

#ifdef __cplusplus
extern "C" {
#endif

int ad_decode_vorbis(
    const unsigned char *bytes,
    int len,
    int *channels,
    int *rate,
    int *samples_per_channel,
    short **out);

int ad_decode_mp3(
    const unsigned char *bytes,
    int len,
    int *channels,
    int *rate,
    int *total_samples_per_channel,
    short **out);

int ad_info_vorbis(
    const unsigned char *bytes,
    int len,
    int *channels,
    int *rate,
    int *samples_per_channel);

int ad_info_mp3(
    const unsigned char *bytes,
    int len,
    int *channels,
    int *rate,
    int *total_samples_per_channel);

void ad_free(short *samples);

#ifdef __cplusplus
}
#endif

#endif
