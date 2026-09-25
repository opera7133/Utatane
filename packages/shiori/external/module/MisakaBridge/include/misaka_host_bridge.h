#ifndef MISAKA_HOST_BRIDGE_H
#define MISAKA_HOST_BRIDGE_H
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif

/* Private connection between Utatane and its independent MISAKA implementation.
 * Not required by SHIORI libraries. All strings are length-delimited UTF-8, no NUL.
 * Borrowed pointers must remain valid for the duration of the call.
 * Zero-initialize output buffers; release module outputs with um_release only.
 */
#define UM_ABI_VERSION 1u
#define UM_MAX_BYTES 8388608u
enum { UM_OK = 0, UM_INVALID = 1, UM_VERSION = 2, UM_NOT_FOUND = 3,
       UM_BUSY = 4, UM_ENGINE = 5, UM_HOST = 6, UM_ALLOCATION = 7 };
enum { UM_SAORI_LOAD = 1, UM_SAORI_UNLOAD = 2, UM_SAORI_CALL = 3 };
typedef struct { const uint8_t *data; uint32_t length; } UMBytes;
typedef struct { uint8_t *data; uint32_t length; } UMBuffer;
typedef struct {
    uint32_t abi_version;
    uint32_t struct_size;
    UMBytes master_path;
    UMBytes state_path;
} UMConfig;
/* SAORI callback result is a UTF-8 value, with U+0001-separated fields when
 * needed. This is a host service, not a SAORI protocol message. Host owns the
 * returned buffer; module calls release once for every non-null result.data,
 * including error results. Callbacks are synchronous on the calling thread.
 */
typedef int32_t (*UMSaori)(void *, uint32_t, UMBytes, const UMBytes *, uint32_t, UMBuffer *);
typedef void (*UMHostRelease)(void *, UMBuffer *);
typedef struct {
    uint32_t abi_version;
    uint32_t struct_size;
    void *context;
    UMSaori saori;
    UMHostRelease release;
} UMHostV1;

uint32_t um_api_version(void);
int32_t um_create(const UMConfig *, const UMHostV1 *, uint64_t *session, UMBuffer *error);
int32_t um_request(uint64_t session, const uint8_t *request, uint32_t length, UMBuffer *response);
int32_t um_destroy(uint64_t session, UMBuffer *error);
/* End a session without saving, after a failed destroy cannot be retried. */
int32_t um_discard(uint64_t session);
void um_release(UMBuffer *);

#ifdef __cplusplus
}
#endif
#endif
