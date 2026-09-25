// Private transport for conventional UTF-8 SHIORI libraries. One library per process.
#include <dlfcn.h>
#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <signal.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#define MAX_BYTES (8u * 1024u * 1024u)
typedef int32_t (*Load)(void *, int32_t);
typedef void *(*Request)(void *, int32_t *);
typedef int32_t (*Unload)(void);
typedef int32_t (*WindowCallback)(int32_t, int32_t, int32_t, int32_t, int32_t *);
typedef int32_t (*SetWindowCallback)(WindowCallback);
static int window_channel = -1;

static void put32(uint8_t *bytes, int32_t value) {
    uint32_t bits = (uint32_t)value;
    for (int i = 0; i < 4; i++) bytes[i] = (uint8_t)(bits >> (i * 8));
}

static int32_t get32(const uint8_t *bytes) {
    uint32_t bits = 0;
    for (int i = 0; i < 4; i++) bits |= (uint32_t)bytes[i] << (i * 8);
    return (int32_t)bits;
}

static int transfer(int fd, void *buffer, size_t size, int writing) {
    char *p = buffer;
    while (size) {
        ssize_t n = writing ? write(fd, p, size) : read(fd, p, size);
        if (n < 0 && errno == EINTR) continue;
        if (n <= 0) return 0;
        p += n; size -= (size_t)n;
    }
    return 1;
}

static int reply(int fd, uint8_t status, const void *data, uint32_t size) {
    if (size > MAX_BYTES) return 0;
    uint32_t n = size + 1;
    uint8_t header[] = {(uint8_t)n, (uint8_t)(n >> 8), (uint8_t)(n >> 16), (uint8_t)(n >> 24), status};
    return transfer(fd, header, sizeof(header), 1) && transfer(fd, (void *)data, size, 1);
}

static int error_reply(int fd, uint8_t status, const char *message) {
    return reply(fd, status, message, (uint32_t)strlen(message));
}

static int32_t window_callback(int32_t operation, int32_t scope, int32_t x, int32_t speed, int32_t *output) {
    uint8_t request[16];
    put32(request, operation); put32(request + 4, scope);
    put32(request + 8, x); put32(request + 12, speed);
    if (!reply(window_channel, 6, request, sizeof(request))) return 0;
    uint8_t frame[25];
    if (!transfer(STDIN_FILENO, frame, sizeof(frame), 0) || get32(frame) != 21 || frame[4] != 3) return 0;
    if (output) for (int i = 0; i < 4; i++) output[i] = get32(frame + 9 + 4 * i);
    return get32(frame + 5);
}

int main(int argc, char **argv) {
    if (argc != 3) return 64;
    signal(SIGPIPE, SIG_IGN);
    // Libraries may print to stdout. Keep those diagnostics outside the framed channel.
    int channel = dup(STDOUT_FILENO);
    if (channel < 0 || dup2(STDERR_FILENO, STDOUT_FILENO) < 0) return 70;
    if (fcntl(channel, F_SETFD, FD_CLOEXEC) < 0) return 70;
    if (chdir(argv[2]) != 0) {
        error_reply(channel, 3, "Cannot open ghost directory"); return 1;
    }
    void *image = dlopen(argv[1], RTLD_NOW | RTLD_LOCAL);
    if (!image) {
        const char *message = dlerror();
        error_reply(channel, 1, message ? message : "Cannot open library"); return 1;
    }
    Load load = (Load)dlsym(image, "loadu");
    if (!load) load = (Load)dlsym(image, "load");
    Request request = (Request)dlsym(image, "request");
    Unload unload = (Unload)dlsym(image, "unload");
    if (!load || !request || !unload) {
        error_reply(channel, 2, "Missing load/loadu, request or unload"); return 1;
    }
    SetWindowCallback set_window_callback = (SetWindowCallback)dlsym(image, "utatane_wmove_set_window_callback");
    if (set_window_callback) {
        window_channel = channel;
        if (!set_window_callback(window_callback)) {
            error_reply(channel, 3, "Cannot connect SAORI windows"); return 1;
        }
    }
    size_t length = strlen(argv[2]);
    if (length >= MAX_BYTES - 1) return 1;
    char *directory = malloc(length + 2);
    if (!directory) return 1;
    memcpy(directory, argv[2], length);
    if (!length || directory[length - 1] != '/') directory[length++] = '/';
    directory[length] = 0;
    if (!load(directory, (int32_t)length)) {
        error_reply(channel, 3, "SHIORI initialization failed"); return 1;
    }
    if (!reply(channel, 0, NULL, 0)) return 1;
    for (;;) {
        uint8_t header[4];
        if (!transfer(STDIN_FILENO, header, sizeof(header), 0)) break;
        uint32_t size = (uint32_t)header[0] | ((uint32_t)header[1] << 8) |
                        ((uint32_t)header[2] << 16) | ((uint32_t)header[3] << 24);
        if (size < 1 || size > MAX_BYTES + 1) break;
        uint8_t command;
        if (!transfer(STDIN_FILENO, &command, 1, 0)) break;
        size--;
        if (command == 2 && size == 0) {
            if (!unload()) {
                if (!error_reply(channel, 5, "SHIORI unload/save failed")) break;
                continue; // Keep the state alive so the caller can retry saving.
            }
            reply(channel, 0, NULL, 0);
            close(channel);
            dlclose(image);
            return 0;
        }
        if (command != 1) break;
        void *input = malloc(size ? size : 1);
        if (!input) break;
        if (!transfer(STDIN_FILENO, input, size, 0)) { free(input); break; }
        int32_t output_size = (int32_t)size;
        void *output = request(input, &output_size);
        if (!output || output_size < 0 || output_size > (int32_t)MAX_BYTES) {
            free(output);
            if (!error_reply(channel, 4, "Invalid SHIORI response")) break;
            continue;
        }
        int sent = reply(channel, 0, output, (uint32_t)output_size);
        free(output);
        if (!sent) break;
    }
    // EOF is a best-effort shutdown. The parent bounds this process's lifetime.
    unload();
    close(channel);
    dlclose(image);
    return 1;
}
