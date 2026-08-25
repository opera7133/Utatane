#define WIN32_LEAN_AND_MEAN
#include <windows.h>

typedef BOOL(__cdecl *module_load_fn)(HGLOBAL, long);
typedef HGLOBAL(__cdecl *module_request_fn)(HGLOBAL, long *);
typedef BOOL(__cdecl *module_unload_fn)(void);

static HGLOBAL global_copy(const void *bytes, long length) {
    HGLOBAL memory = GlobalAlloc(GMEM_FIXED | GMEM_ZEROINIT, (SIZE_T)length + 1);
    if (memory != NULL) {
        BYTE *destination = (BYTE *)memory;
        const BYTE *source = (const BYTE *)bytes;
        for (long index = 0; index < length; ++index) destination[index] = source[index];
    }
    return memory;
}

static BOOL read_exact(HANDLE input, void *buffer, DWORD length) {
    BYTE *cursor = (BYTE *)buffer;
    while (length > 0) {
        DWORD count = 0;
        if (!ReadFile(input, cursor, length, &count, NULL) || count == 0) return FALSE;
        cursor += count;
        length -= count;
    }
    return TRUE;
}

static BOOL write_exact(HANDLE output, const void *buffer, DWORD length) {
    const BYTE *cursor = (const BYTE *)buffer;
    while (length > 0) {
        DWORD count = 0;
        if (!WriteFile(output, cursor, length, &count, NULL) || count == 0) return FALSE;
        cursor += count;
        length -= count;
    }
    return TRUE;
}

static char *read_argument(char *cursor, char *output, DWORD capacity) {
    while (*cursor == ' ' || *cursor == '\t') ++cursor;
    BOOL quoted = *cursor == '"';
    if (quoted) ++cursor;

    DWORD length = 0;
    while (*cursor != '\0' && (quoted ? *cursor != '"' : (*cursor != ' ' && *cursor != '\t'))) {
        if (length + 1 < capacity) output[length++] = *cursor;
        ++cursor;
    }
    output[length] = '\0';
    if (quoted && *cursor == '"') ++cursor;
    return cursor;
}

static BOOL parent_directory(char *path, long *length) {
    long separator = -1;
    for (long index = 0; path[index] != '\0'; ++index) {
        if (path[index] == '\\' || path[index] == '/') separator = index;
    }
    if (separator < 0) return FALSE;
    path[separator + 1] = '\0';
    *length = separator + 1;
    return TRUE;
}

static DWORD run_host(void) {
    char ignored[MAX_PATH];
    char module_path[MAX_PATH];
    char module_directory[MAX_PATH];
    char *cursor = read_argument(GetCommandLineA(), ignored, MAX_PATH);
    read_argument(cursor, module_path, MAX_PATH);
    if (module_path[0] == '\0') return 2;

    long module_path_length = 0;
    while (module_path[module_path_length] != '\0' && module_path_length < MAX_PATH - 1) {
        module_directory[module_path_length] = module_path[module_path_length];
        ++module_path_length;
    }
    module_directory[module_path_length] = '\0';

    long directory_length = 0;
    if (!parent_directory(module_directory, &directory_length)) return 2;

    HMODULE module = LoadLibraryA(module_path);
    if (module == NULL) return 3;
    module_load_fn loadu = (module_load_fn)GetProcAddress(module, "loadu");
    module_load_fn load = (module_load_fn)GetProcAddress(module, "load");
    module_request_fn request = (module_request_fn)GetProcAddress(module, "request");
    module_unload_fn unload = (module_unload_fn)GetProcAddress(module, "unload");
    if ((loadu == NULL && load == NULL) || request == NULL || unload == NULL) {
        FreeLibrary(module);
        return 4;
    }

    HGLOBAL load_memory = global_copy(module_directory, directory_length);
    if (load_memory == NULL ||
        !(load != NULL ? load(load_memory, directory_length) : loadu(load_memory, directory_length))) {
        FreeLibrary(module);
        return 5;
    }

    HANDLE input = GetStdHandle(STD_INPUT_HANDLE);
    HANDLE output = GetStdHandle(STD_OUTPUT_HANDLE);
    DWORD ready = 0;
    if (!write_exact(output, &ready, sizeof(ready))) return 6;

    DWORD result = 0;
    for (;;) {
        DWORD frame_length = 0;
        if (!read_exact(input, &frame_length, sizeof(frame_length))) break;
        if (frame_length == 0 || frame_length > 16 * 1024 * 1024) {
            result = 7;
            break;
        }
        BYTE *frame = (BYTE *)HeapAlloc(GetProcessHeap(), 0, frame_length);
        if (frame == NULL || !read_exact(input, frame, frame_length)) {
            if (frame != NULL) HeapFree(GetProcessHeap(), 0, frame);
            result = 7;
            break;
        }
        long response_length = (long)frame_length;
        HGLOBAL request_memory = global_copy(frame, response_length);
        HeapFree(GetProcessHeap(), 0, frame);
        if (request_memory == NULL) {
            result = 7;
            break;
        }
        HGLOBAL response_memory = request(request_memory, &response_length);
        if (response_memory == NULL || response_length < 0 || response_length > 16 * 1024 * 1024) {
            result = 7;
            break;
        }
        DWORD output_length = (DWORD)response_length;
        BOOL wrote = write_exact(output, &output_length, sizeof(output_length)) &&
            write_exact(output, (const void *)response_memory, output_length);
        GlobalFree(response_memory);
        if (!wrote) {
            result = 7;
            break;
        }
    }

    unload();
    FreeLibrary(module);
    return result;
}

void mainCRTStartup(void) {
    ExitProcess(run_host());
}
