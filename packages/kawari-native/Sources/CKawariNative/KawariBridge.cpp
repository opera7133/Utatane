#include "CKawariNative.h"

#include "shiori/kawari_shiori.h"
#include "saori/saori_module.h"

#include <algorithm>
#include <cctype>
#include <cstdlib>
#include <cstring>
#include <mutex>
#include <string>

namespace {
std::mutex kawariMutex;
utatane_kawari_saori_request_callback saoriRequestCallback = nullptr;

class UtataneSaoriModule final : public saori::TModule {
public:
    UtataneSaoriModule(saori::IModuleFactory &factory, const std::string &path)
        : TModule(factory, path, 0) {}

    bool Initialize() override { return true; }
    bool Load() override { return true; }
    bool Unload() override { return true; }

    std::string Request(const std::string &request) override {
        if (saoriRequestCallback == nullptr) return "";
        int64_t length = static_cast<int64_t>(request.size());
        char *response = saoriRequestCallback(request.data(), &length);
        if (response == nullptr || length < 0) return "";
        const std::string result(response, static_cast<std::size_t>(length));
        std::free(response);
        return result;
    }
};

class UtataneSaoriFactory final : public saori::IModuleFactory {
public:
    explicit UtataneSaoriFactory(TKawariLogger &logger) : IModuleFactory(logger) {}

    saori::TModule *CreateModule(const std::string &path) override {
        std::string filename = path;
        std::replace(filename.begin(), filename.end(), '\\', '/');
        const std::size_t slash = filename.find_last_of('/');
        if (slash != std::string::npos) filename.erase(0, slash + 1);
        std::transform(filename.begin(), filename.end(), filename.begin(), [](unsigned char character) {
            return static_cast<char>(std::tolower(character));
        });
        if (filename != "textcopy2.dll") return nullptr;
        return new UtataneSaoriModule(*this, path);
    }

    void DeleteModule(saori::TModule *module) override { delete module; }
};
}

saori::IModuleFactory *utatane_create_builtin_saori_factory(TKawariLogger &logger) {
    return new UtataneSaoriFactory(logger);
}

void utatane_kawari_set_saori_request_callback(utatane_kawari_saori_request_callback callback) {
    std::lock_guard<std::mutex> lock(kawariMutex);
    saoriRequestCallback = callback;
}

uint32_t utatane_kawari_create(const char *path, int64_t length) {
    if (path == nullptr || length < 0) {
        return 0;
    }
    try {
        std::lock_guard<std::mutex> lock(kawariMutex);
        return TKawariShioriFactory::GetFactory().CreateInstance(
            std::string(path, static_cast<std::size_t>(length))
        );
    } catch (...) {
        return 0;
    }
}

int32_t utatane_kawari_dispose(uint32_t handle) {
    if (handle == 0) {
        return 0;
    }
    try {
        std::lock_guard<std::mutex> lock(kawariMutex);
        return TKawariShioriFactory::GetFactory().DisposeInstance(handle) ? 1 : 0;
    } catch (...) {
        return 0;
    }
}

char *utatane_kawari_request(uint32_t handle, const char *request, int64_t *length) {
    if (handle == 0 || request == nullptr || length == nullptr || *length < 0) {
        return nullptr;
    }
    try {
        std::lock_guard<std::mutex> lock(kawariMutex);
        const std::string response = TKawariShioriFactory::GetFactory().RequestInstance(
            handle,
            std::string(request, static_cast<std::size_t>(*length))
        );
        *length = static_cast<int64_t>(response.size());
        const std::size_t allocationSize = response.empty() ? 1 : response.size();
        char *result = static_cast<char *>(std::malloc(allocationSize));
        if (result == nullptr) {
            *length = 0;
            return nullptr;
        }
        if (!response.empty()) {
            std::memcpy(result, response.data(), response.size());
        }
        return result;
    } catch (...) {
        *length = 0;
        return nullptr;
    }
}

void utatane_kawari_free(char *pointer) {
    std::free(pointer);
}
