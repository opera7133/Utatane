#include "CSatoriNative.h"

#include <cstdlib>
#include <cstring>
#include <mutex>

extern "C" int satori_load(char *data, long length);
extern "C" int satori_unload(int id);
extern "C" char *satori_request(int id, char *data, long *length);

namespace {
std::mutex satori_mutex;
utatane_satori_saori_request_callback saori_request_callback = nullptr;
}

void utatane_satori_set_saori_request_callback(utatane_satori_saori_request_callback callback) {
    saori_request_callback = callback;
}

char *utatane_satori_native_saori_request(const char *path, const char *request, long *length) {
    if (saori_request_callback == nullptr) return nullptr;
    return saori_request_callback(path, request, length);
}

long utatane_satori_create(const char *master_path) {
    const std::lock_guard<std::mutex> lock(satori_mutex);
    if (master_path == nullptr) return 0;
    const auto length = static_cast<long>(std::strlen(master_path));
    auto *owned = static_cast<char *>(std::malloc(length + 1));
    if (owned == nullptr) return 0;
    std::memcpy(owned, master_path, length + 1);
    return satori_load(owned, length);
}

int utatane_satori_destroy(long instance_id) {
    const std::lock_guard<std::mutex> lock(satori_mutex);
    return satori_unload(static_cast<int>(instance_id));
}

char *utatane_satori_request(long instance_id, const char *request, long *response_length) {
    const std::lock_guard<std::mutex> lock(satori_mutex);
    if (request == nullptr || response_length == nullptr) return nullptr;
    const auto length = static_cast<long>(std::strlen(request));
    auto *owned = static_cast<char *>(std::malloc(length + 1));
    if (owned == nullptr) return nullptr;
    std::memcpy(owned, request, length + 1);
    *response_length = length;
    return satori_request(static_cast<int>(instance_id), owned, response_length);
}

void utatane_satori_free(void *buffer) {
    std::free(buffer);
}
