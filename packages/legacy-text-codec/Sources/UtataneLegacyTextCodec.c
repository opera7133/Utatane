#include "UtataneLegacyTextCodec.h"

#include <iconv.h>
#include <stdint.h>

size_t utatane_transcode(
    const char *source_encoding,
    const char *destination_encoding,
    const uint8_t *input,
    size_t input_length,
    uint8_t *output,
    size_t output_capacity
) {
    iconv_t converter = iconv_open(destination_encoding, source_encoding);
    if (converter == (iconv_t)-1) {
        return SIZE_MAX;
    }

    char *input_cursor = (char *)input;
    char *output_cursor = (char *)output;
    size_t input_remaining = input_length;
    size_t output_remaining = output_capacity;
    size_t result = iconv(
        converter,
        &input_cursor,
        &input_remaining,
        &output_cursor,
        &output_remaining
    );
    iconv_close(converter);
    if (result == (size_t)-1 || input_remaining != 0) {
        return SIZE_MAX;
    }
    return output_capacity - output_remaining;
}
