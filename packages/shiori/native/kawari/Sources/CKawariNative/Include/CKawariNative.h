#ifndef C_KAWARI_NATIVE_H
#define C_KAWARI_NATIVE_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

uint32_t utatane_kawari_create(const char *path, int64_t length);
int32_t utatane_kawari_dispose(uint32_t handle);
char *utatane_kawari_request(uint32_t handle, const char *request, int64_t *length);
void utatane_kawari_free(char *pointer);

typedef char *(*utatane_kawari_saori_request_callback)(const char *path, const char *request, int64_t *length);
void utatane_kawari_set_saori_request_callback(utatane_kawari_saori_request_callback callback);

#ifdef __cplusplus
}
#endif

#endif
