#ifndef UTATANE_LZMA_H
#define UTATANE_LZMA_H
#include <stddef.h>
#include <stdint.h>

typedef int (*utatane_lzma_consumer)(const uint8_t *, size_t, void *);
/* ZIP method 14 payload; returns zero only after size, end marker, and CRC match.
 * A consumer may return zero to cancel (e.g. output or time limit exceeded). */
int utatane_lzma_decode(const uint8_t *input, size_t length, uint64_t expected_size,
                       uint32_t expected_crc, int requires_end_marker,
                       utatane_lzma_consumer consumer, void *context);
#endif
