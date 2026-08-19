#ifndef UTATANE_C_YAYA_NATIVE_H
#define UTATANE_C_YAYA_NATIVE_H

#ifdef __cplusplus
extern "C" {
#endif

long utatane_yaya_create_utf8(const char *master_path);
int utatane_yaya_destroy(long instance_id);
char *utatane_yaya_request(long instance_id, const char *request, long *response_length);
void utatane_yaya_free(void *buffer);

#ifdef __cplusplus
}
#endif

#endif
