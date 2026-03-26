#include <stdint.h>
#include <stdlib.h>
#include <string.h>

typedef struct StringDescriptor {
    void *data;
    int64_t length;
    int64_t capacity;
    int32_t refcount;
    uint8_t encoding;
    uint8_t dirty;
    uint8_t _padding[2];
    uint8_t *utf8_cache;
} StringDescriptor;

void timer_tick_frame(void) {
    // MacScheme currently does not use the FasterBASIC message timer system.
}

const char *string_to_utf8(const void *desc_ptr) {
    if (!desc_ptr) return "";
    const StringDescriptor *desc = (const StringDescriptor *)desc_ptr;
    if (desc->utf8_cache) return (const char *)desc->utf8_cache;
    if (!desc->data || desc->length <= 0) return "";

    size_t len = (size_t)desc->length;
    char *buf = (char *)malloc(len + 1);
    if (!buf) return "";
    memcpy(buf, desc->data, len);
    buf[len] = '\0';
    ((StringDescriptor *)desc)->utf8_cache = (uint8_t *)buf;
    return buf;
}

void *string_new_utf8(const char *cstr) {
    if (!cstr) cstr = "";
    size_t len = strlen(cstr);

    StringDescriptor *desc = (StringDescriptor *)calloc(1, sizeof(StringDescriptor));
    if (!desc) return NULL;

    char *data = (char *)malloc(len + 1);
    if (!data) {
        free(desc);
        return NULL;
    }
    memcpy(data, cstr, len + 1);

    desc->data = data;
    desc->length = (int64_t)len;
    desc->capacity = (int64_t)len + 1;
    desc->refcount = 1;
    desc->encoding = 1;
    desc->dirty = 0;
    desc->utf8_cache = (uint8_t *)data;
    return desc;
}

void string_release(void *desc_ptr) {
    if (!desc_ptr) return;

    StringDescriptor *desc = (StringDescriptor *)desc_ptr;
    if (desc->refcount > 1) {
        desc->refcount -= 1;
        return;
    }

    if (desc->data) {
        free(desc->data);
    }
    if (desc->utf8_cache && desc->utf8_cache != (uint8_t *)desc->data) {
        free(desc->utf8_cache);
    }
    free(desc);
}
