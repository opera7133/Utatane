#ifndef UTATANE_LEGACY_TEXT_CODEC_H
#define UTATANE_LEGACY_TEXT_CODEC_H

#include <stddef.h>
#include <stdint.h>

size_t utatane_transcode(
    const char *source_encoding,
    const char *destination_encoding,
    const uint8_t *input,
    size_t input_length,
    uint8_t *output,
    size_t output_capacity
);

#endif
