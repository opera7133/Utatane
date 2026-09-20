#ifndef UTATANE_C_YAYA_NATIVE_H
#define UTATANE_C_YAYA_NATIVE_H

#ifdef __cplusplus
extern "C" {
#endif

long utatane_yaya_create_utf8(const char *master_path);
typedef char *(*utatane_yaya_saori_request_callback)(const char *path, const char *request, long *length);
void utatane_yaya_set_saori_request_callback(utatane_yaya_saori_request_callback callback);
int utatane_yaya_native_saori_load(const char *path);
int utatane_yaya_native_saori_unload(const char *path);
char *utatane_yaya_native_saori_request(const char *path, char *request, long *length);
int utatane_yaya_destroy(long instance_id);
char *utatane_yaya_request(long instance_id, const char *request, long *response_length);
void utatane_yaya_free(void *buffer);

#ifdef __cplusplus
}
#endif

#endif
