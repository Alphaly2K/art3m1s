#include "katze_system2.h"

#include <stdlib.h>
#include <string.h>

#if defined(_WIN32)
#define EXPORT __declspec(dllexport)
#else
#define EXPORT __attribute__((visibility("default")))
#endif

#define BYTES(s) { (const uint8_t *)(s), sizeof(s) - 1 }

typedef struct Fixture {
    KatzeHost host;
    KatzeCreateInfo create;
    KatzeBytes script;
    KatzeBytes ogg;
    KatzeTriangle triangles[2];
    size_t count;
    size_t open_sources;
} Fixture;

static Fixture *fixture_of(uint64_t context) {
    return (Fixture *)(uintptr_t)context;
}

static int matches(KatzeBytes name, const char *text) {
    return name.len == strlen(text) && memcmp(name.data, text, name.len) == 0;
}

static KatzeStatus open_resource(uint64_t context, const KatzeOpenRequest *request,
                                 KatzeSource *out) {
    Fixture *fixture = fixture_of(context);
    if (request->kind != KATZE_OPEN_RESOURCE || request->name.encoding != KATZE_NAME_BYTES)
        return KATZE_ABSENT;
    if (matches(request->name.bytes, "host.kcs")) {
        *out = (KatzeSource){1, fixture->script.len};
    } else if (matches(request->name.bytes, "tone.ogg")) {
        *out = (KatzeSource){2, fixture->ogg.len};
    } else {
        return KATZE_ABSENT;
    }
    ++fixture->open_sources;
    return KATZE_OK;
}

static KatzeStatus read_resource(uint64_t context, uint64_t token, uint64_t offset,
                                 uint8_t *out, size_t capacity, size_t *count) {
    Fixture *fixture = fixture_of(context);
    KatzeBytes bytes = token == 1 ? fixture->script : fixture->ogg;
    if ((token != 1 && token != 2) || offset > bytes.len) return KATZE_E_INVALID;
    const size_t remaining = bytes.len - (size_t)offset;
    *count = remaining < capacity ? remaining : capacity;
    if (*count) memcpy(out, bytes.data + (size_t)offset, *count);
    return KATZE_OK;
}

static void close_resource(uint64_t context, uint64_t token) {
    (void)token;
    --fixture_of(context)->open_sources;
}

static KatzeStatus present(uint64_t context, uint32_t purpose, const KatzeFrame *frame,
                           uint8_t *out, size_t capacity) {
    Fixture *fixture = fixture_of(context);
    if (purpose != KATZE_RENDER_PRESENT || out || capacity || frame->texture_count ||
        frame->triangle_count > 2) return KATZE_E_INVALID;
    for (size_t i = 0; i < frame->triangle_count; ++i) {
        const KatzeTriangle *triangle = &frame->triangles[i];
        if (triangle->texture_index != KATZE_NO_TEXTURE || triangle->clipped ||
            triangle->blend_mode != KATZE_BLEND_NORMAL) return KATZE_E_INVALID;
        fixture->triangles[i] = *triangle;
    }
    fixture->count = frame->triangle_count;
    return KATZE_OK;
}

EXPORT const KatzeCreateInfo *katze_fixture_new(const uint8_t *script, size_t script_size,
                                               const uint8_t *ogg, size_t ogg_size) {
    Fixture *fixture = calloc(1, sizeof(*fixture));
    if (!fixture) return NULL;
    fixture->script = (KatzeBytes){script, script_size};
    fixture->ogg = (KatzeBytes){ogg, ogg_size};
    fixture->host = (KatzeHost){
        .struct_size = sizeof(fixture->host), .context = (uint64_t)(uintptr_t)fixture,
        .open = open_resource, .read_at = read_resource, .close = close_resource,
        .render = present,
    };
    fixture->create = (KatzeCreateInfo){
        .struct_size = sizeof(fixture->create), .flags = KATZE_CREATE_DETACHED_AUDIO,
        .host = &fixture->host, .entry = BYTES("host"),
        .startup_xml = BYTES("<?xml version=\"1.0\" encoding=\"UTF-8\"?>"
                             "<document><SCREEN><width>64</width><height>48</height></SCREEN>"
                             "<INT><int00><name>kcs</name><ext>kcs</ext></int00>"
                             "<int01><name>sound</name><ext>ogg</ext></int01>"
                             "<int02><name>tag</name><ext>tag</ext></int02></INT></document>"),
    };
    return &fixture->create;
}

EXPORT size_t katze_fixture_vertices(const KatzeCreateInfo *info, float *xy, uint32_t *argb) {
    const Fixture *fixture = fixture_of(info->host->context);
    size_t count = 0;
    for (size_t i = 0; i < fixture->count; ++i) {
        for (size_t j = 0; j < 3; ++j) {
            const KatzeVertex *vertex = &fixture->triangles[i].vertices[j];
            xy[count * 2] = vertex->position[0];
            xy[count * 2 + 1] = vertex->position[1];
            argb[count++] = vertex->argb;
        }
    }
    return count;
}

EXPORT size_t katze_fixture_free(const KatzeCreateInfo *info) {
    Fixture *fixture = fixture_of(info->host->context);
    const size_t remaining = fixture->open_sources;
    free(fixture);
    return remaining;
}
