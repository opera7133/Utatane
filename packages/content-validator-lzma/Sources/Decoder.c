#include "include/UtataneLZMA.h"
#include "Vendor/LzmaDec.h"
#include <stdlib.h>
#include <zlib.h>

static void *allocate(ISzAllocPtr ignored, size_t size) { (void)ignored; return malloc(size); }
static void release(ISzAllocPtr ignored, void *pointer) { (void)ignored; free(pointer); }
static const ISzAlloc allocator = { allocate, release };

int utatane_lzma_decode(const uint8_t *input, size_t length, uint64_t expected_size,
                       uint32_t expected_crc, int requires_end_marker,
                       utatane_lzma_consumer consumer, void *context) {
    if (!input || !consumer || length < 9 || input[2] != 5 || input[3] != 0) return 1;
    CLzmaProps properties;
    if (LzmaProps_Decode(&properties, input + 4, 5) != SZ_OK || properties.dicSize > 64 * 1024 * 1024) return 2;
    CLzmaDec decoder;
    LzmaDec_Construct(&decoder);
    if (LzmaDec_Allocate(&decoder, input + 4, 5, &allocator) != SZ_OK) return 2;
    LzmaDec_Init(&decoder);
    size_t position = 9;
    uint64_t produced = 0;
    uLong crc = crc32(0L, Z_NULL, 0);
    int result = 1;
    uint8_t buffer[65536];
    for (;;) {
        SizeT available = length - position;
        SizeT output = expected_size - produced > sizeof(buffer) ? sizeof(buffer) : (SizeT)(expected_size - produced);
        ELzmaStatus status;
        SRes code = LzmaDec_DecodeToBuf(&decoder, buffer, &output, input + position, &available,
                                      produced + output == expected_size ? LZMA_FINISH_END : LZMA_FINISH_ANY, &status);
        if (code != SZ_OK || produced + output > expected_size) break;
        position += available;
        produced += output;
        crc = crc32(crc, buffer, (uInt)output);
        // Also call the consumer for an empty stream, so the deadline is checked.
        if (!consumer(buffer, output, context)) { result = 3; break; }
        if (produced == expected_size) {
            int ended = status == LZMA_STATUS_FINISHED_WITH_MARK ||
                (!requires_end_marker && status == LZMA_STATUS_MAYBE_FINISHED_WITHOUT_MARK);
            if (ended && position == length && (uint32_t)crc == expected_crc) result = 0;
            break;
        }
        if (status == LZMA_STATUS_FINISHED_WITH_MARK || (available == 0 && output == 0)) break;
    }
    LzmaDec_Free(&decoder, &allocator);
    return result;
}
