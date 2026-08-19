#include "CYayaNative.h"

#include <cstdlib>
#include <cstring>
#include <mutex>

extern "C" long multi_loadu(char *path, long length);
extern "C" int multi_unload(long instance_id);
extern "C" char *multi_request(long instance_id, char *request, long *length);

namespace {
std::mutex yaya_mutex;
}

long utatane_yaya_create_utf8(const char *master_path) {
    const std::lock_guard<std::mutex> lock(yaya_mutex);
    if (master_path == nullptr) {
        return 0;
    }

    const auto length = static_cast<long>(std::strlen(master_path));
    auto *owned_path = static_cast<char *>(std::malloc(length + 1));
    if (owned_path == nullptr) {
        return 0;
    }
    std::memcpy(owned_path, master_path, length + 1);
    return multi_loadu(owned_path, length);
}

int utatane_yaya_destroy(long instance_id) {
    const std::lock_guard<std::mutex> lock(yaya_mutex);
    return multi_unload(instance_id);
}

char *utatane_yaya_request(long instance_id, const char *request, long *response_length) {
    const std::lock_guard<std::mutex> lock(yaya_mutex);
    if (request == nullptr || response_length == nullptr) {
        return nullptr;
    }

    const auto length = static_cast<long>(std::strlen(request));
    auto *owned_request = static_cast<char *>(std::malloc(length + 1));
    if (owned_request == nullptr) {
        *response_length = 0;
        return nullptr;
    }
    std::memcpy(owned_request, request, length + 1);
    *response_length = length;
    return multi_request(instance_id, owned_request, response_length);
}

void utatane_yaya_free(void *buffer) {
    std::free(buffer);
}
