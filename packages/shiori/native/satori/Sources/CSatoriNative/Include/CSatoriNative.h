#ifndef UTATANE_C_SATORI_NATIVE_H
#define UTATANE_C_SATORI_NATIVE_H

#ifdef __cplusplus
extern "C" {
#endif

long utatane_satori_create(const char *master_path);
typedef char *(*utatane_satori_saori_request_callback)(const char *path, const char *request, long *length);
void utatane_satori_set_saori_request_callback(utatane_satori_saori_request_callback callback);
char *utatane_satori_native_saori_request(const char *path, const char *request, long *length);
int utatane_satori_destroy(long instance_id);
char *utatane_satori_request(long instance_id, const char *request, long *response_length);
void utatane_satori_free(void *buffer);

#ifdef __cplusplus
}
#endif

#endif
