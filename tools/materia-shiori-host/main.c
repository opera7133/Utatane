#define WIN32_LEAN_AND_MEAN
#include <windows.h>

#include <stdint.h>
#include <stdio.h>
#include <string.h>

typedef BOOL(__cdecl *shiori_load_fn)(HGLOBAL, long);
typedef HGLOBAL(__cdecl *shiori_request_fn)(HGLOBAL, long *);
typedef BOOL(__cdecl *shiori_unload_fn)(void);

static HANDLE log_file = INVALID_HANDLE_VALUE;
static BOOL serve_mode = FALSE;

static void log_bytes(const void *bytes, DWORD length) {
    DWORD written = 0;
    if (log_file != INVALID_HANDLE_VALUE) {
        WriteFile(log_file, bytes, length, &written, NULL);
        FlushFileBuffers(log_file);
    }
    if (!serve_mode) {
        WriteFile(GetStdHandle(STD_OUTPUT_HANDLE), bytes, length, &written, NULL);
    }
}

static void log_line(const char *line) {
    log_bytes(line, (DWORD)strlen(line));
    log_bytes("\r\n", 2);
}

static void log_win32_error(const char *operation) {
    char message[256];
    wsprintfA(message, "ERROR: %s failed (Win32 error %lu)", operation, GetLastError());
    log_line(message);
}

static BOOL parent_directory(char *path) {
    char *separator = strrchr(path, '\\');
    if (separator == NULL) {
        separator = strrchr(path, '/');
    }
    if (separator == NULL) {
        return FALSE;
    }
    *separator = '\0';
    return TRUE;
}

static BOOL join_path(char *output, DWORD capacity, const char *directory, const char *relative) {
    int count = _snprintf(output, capacity, "%s\\%s", directory, relative);
    if (count < 0 || (DWORD)count >= capacity) {
        SetLastError(ERROR_BUFFER_OVERFLOW);
        return FALSE;
    }
    return TRUE;
}

static BOOL extract_dll_resource(HMODULE materia, WORD resource_id, const char *destination) {
    HRSRC resource = FindResourceA(materia, MAKEINTRESOURCEA(resource_id), "DLL");
    if (resource == NULL) {
        log_win32_error("FindResourceA");
        return FALSE;
    }
    HGLOBAL loaded = LoadResource(materia, resource);
    if (loaded == NULL) {
        log_win32_error("LoadResource");
        return FALSE;
    }
    void *bytes = LockResource(loaded);
    DWORD size = SizeofResource(materia, resource);
    if (bytes == NULL || size == 0) {
        log_win32_error("LockResource/SizeofResource");
        return FALSE;
    }

    HANDLE output = CreateFileA(
        destination,
        GENERIC_WRITE,
        0,
        NULL,
        CREATE_ALWAYS,
        FILE_ATTRIBUTE_NORMAL,
        NULL
    );
    if (output == INVALID_HANDLE_VALUE) {
        log_win32_error("CreateFileA(resource output)");
        return FALSE;
    }
    DWORD written = 0;
    BOOL ok = WriteFile(output, bytes, size, &written, NULL) && written == size;
    CloseHandle(output);
    if (!ok) {
        log_win32_error("WriteFile(resource output)");
    }
    return ok;
}

static HGLOBAL global_copy(const void *bytes, long length) {
    HGLOBAL memory = GlobalAlloc(GMEM_FIXED | GMEM_ZEROINIT, (SIZE_T)length + 1);
    if (memory != NULL) {
        memcpy((void *)memory, bytes, (size_t)length);
    }
    return memory;
}

static BOOL read_exact(HANDLE input, void *buffer, DWORD length) {
    BYTE *cursor = buffer;
    DWORD remaining = length;
    while (remaining > 0) {
        DWORD count = 0;
        if (!ReadFile(input, cursor, remaining, &count, NULL) || count == 0) {
            return FALSE;
        }
        cursor += count;
        remaining -= count;
    }
    return TRUE;
}

static BOOL write_exact(HANDLE output, const void *buffer, DWORD length) {
    const BYTE *cursor = buffer;
    DWORD remaining = length;
    while (remaining > 0) {
        DWORD count = 0;
        if (!WriteFile(output, cursor, remaining, &count, NULL) || count == 0) {
            return FALSE;
        }
        cursor += count;
        remaining -= count;
    }
    return TRUE;
}

static int serve_requests(shiori_request_fn request) {
    HANDLE input = GetStdHandle(STD_INPUT_HANDLE);
    HANDLE output = GetStdHandle(STD_OUTPUT_HANDLE);
    DWORD ready = 0;
    if (!write_exact(output, &ready, sizeof(ready))) {
        log_win32_error("WriteFile(ready frame)");
        return 8;
    }
    log_line("IPC host ready.");

    for (;;) {
        DWORD frame_length = 0;
        if (!read_exact(input, &frame_length, sizeof(frame_length))) {
            log_line("IPC input closed.");
            return 0;
        }
        if (frame_length == 0 || frame_length > 16 * 1024 * 1024) {
            log_line("ERROR: Invalid IPC request length.");
            return 8;
        }
        BYTE *frame = HeapAlloc(GetProcessHeap(), 0, frame_length);
        if (frame == NULL || !read_exact(input, frame, frame_length)) {
            if (frame != NULL) {
                HeapFree(GetProcessHeap(), 0, frame);
            }
            log_line("ERROR: Could not read IPC request.");
            return 8;
        }
        long response_length = (long)frame_length;
        HGLOBAL request_memory = global_copy(frame, response_length);
        HeapFree(GetProcessHeap(), 0, frame);
        if (request_memory == NULL) {
            log_win32_error("GlobalAlloc(IPC request)");
            return 8;
        }
        HGLOBAL response_memory = request(request_memory, &response_length);
        if (response_memory == NULL || response_length < 0 || response_length > 16 * 1024 * 1024) {
            log_line("ERROR: first.dll returned an invalid IPC response.");
            return 8;
        }
        DWORD output_length = (DWORD)response_length;
        BOOL wrote = write_exact(output, &output_length, sizeof(output_length)) &&
            write_exact(output, (const void *)response_memory, output_length);
        GlobalFree(response_memory);
        if (!wrote) {
            log_win32_error("WriteFile(IPC response)");
            return 8;
        }
    }
}

static void log_cp932_as_utf8(const char *bytes, int length) {
    int wide_length = MultiByteToWideChar(932, 0, bytes, length, NULL, 0);
    if (wide_length <= 0) {
        log_bytes(bytes, (DWORD)length);
        return;
    }
    WCHAR *wide = HeapAlloc(GetProcessHeap(), 0, (SIZE_T)wide_length * sizeof(WCHAR));
    if (wide == NULL) {
        log_bytes(bytes, (DWORD)length);
        return;
    }
    MultiByteToWideChar(932, 0, bytes, length, wide, wide_length);
    int utf8_length = WideCharToMultiByte(CP_UTF8, 0, wide, wide_length, NULL, 0, NULL, NULL);
    char *utf8 = HeapAlloc(GetProcessHeap(), 0, (SIZE_T)utf8_length);
    if (utf8 != NULL) {
        WideCharToMultiByte(CP_UTF8, 0, wide, wide_length, utf8, utf8_length, NULL, NULL);
        log_bytes(utf8, (DWORD)utf8_length);
        HeapFree(GetProcessHeap(), 0, utf8);
    }
    HeapFree(GetProcessHeap(), 0, wide);
}

int main(int argc, char **argv) {
    char executable[MAX_PATH];
    char host_directory[MAX_PATH];
    char materia_path[MAX_PATH];
    char shiori_path[MAX_PATH];
    char master_directory[MAX_PATH];
    char log_path[MAX_PATH];
    char mai_path[MAX_PATH];
    char sayuri_path[MAX_PATH];

    if (GetModuleFileNameA(NULL, executable, MAX_PATH) == 0) {
        return 2;
    }
    lstrcpynA(host_directory, executable, MAX_PATH);
    if (!parent_directory(host_directory)) {
        return 2;
    }
    serve_mode = argc >= 2 &&
        (lstrcmpiA(argv[1], "serve") == 0 || lstrcmpiA(argv[1], "--serve") == 0);
    if (!join_path(log_path, MAX_PATH, host_directory, serve_mode ? "host.log" : "probe.log")) {
        return 2;
    }
    log_file = CreateFileA(log_path, GENERIC_WRITE, FILE_SHARE_READ, NULL, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
    log_line(serve_mode ? "Utatane Materia SHIORI host" : "Utatane Materia SHIORI probe");

    const char *executable_name = strrchr(executable, '\\');
    executable_name = executable_name == NULL ? executable : executable_name + 1;
    if (lstrcmpiA(executable_name, "materia.exe") != 0) {
        log_line("ERROR: This probe must be named materia.exe because first.dll checks the process name.");
        return 3;
    }

    if (serve_mode && argc >= 4) {
        lstrcpynA(materia_path, argv[2], MAX_PATH);
        lstrcpynA(shiori_path, argv[3], MAX_PATH);
    } else if (!serve_mode && argc >= 3) {
        lstrcpynA(materia_path, argv[1], MAX_PATH);
        lstrcpynA(shiori_path, argv[2], MAX_PATH);
    } else {
        if (!join_path(materia_path, MAX_PATH, host_directory, "..\\materia.exe") ||
            !join_path(shiori_path, MAX_PATH, host_directory, "..\\Ghosts\\first\\ghost\\master\\first.dll")) {
            log_win32_error("join_path");
            return 3;
        }
    }

    lstrcpynA(master_directory, shiori_path, MAX_PATH);
    if (!parent_directory(master_directory)) {
        log_line("ERROR: Could not determine the ghost/master directory.");
        return 3;
    }
    size_t master_length = strlen(master_directory);
    if (master_length + 1 >= MAX_PATH) {
        log_line("ERROR: The ghost/master path is too long.");
        return 3;
    }
    master_directory[master_length] = '\\';
    master_directory[master_length + 1] = '\0';

    HMODULE materia = LoadLibraryExA(materia_path, NULL, LOAD_LIBRARY_AS_DATAFILE);
    if (materia == NULL) {
        log_win32_error("LoadLibraryExA(original materia.exe)");
        return 4;
    }
    join_path(mai_path, MAX_PATH, host_directory, "mai.dll");
    join_path(sayuri_path, MAX_PATH, host_directory, "sayuri.dll");
    if (!extract_dll_resource(materia, 102, mai_path) ||
        !extract_dll_resource(materia, 104, sayuri_path)) {
        FreeLibrary(materia);
        return 4;
    }
    FreeLibrary(materia);
    log_line("Extracted mai.dll and sayuri.dll.");

    HMODULE shiori = LoadLibraryA(shiori_path);
    if (shiori == NULL) {
        log_win32_error("LoadLibraryA(first.dll)");
        return 5;
    }
    shiori_load_fn load = (shiori_load_fn)GetProcAddress(shiori, "load");
    shiori_request_fn request = (shiori_request_fn)GetProcAddress(shiori, "request");
    shiori_unload_fn unload = (shiori_unload_fn)GetProcAddress(shiori, "unload");
    if (load == NULL || request == NULL || unload == NULL) {
        log_line("ERROR: first.dll does not export load/request/unload.");
        FreeLibrary(shiori);
        return 5;
    }

    long path_length = (long)strlen(master_directory);
    HGLOBAL path_memory = global_copy(master_directory, path_length);
    if (path_memory == NULL) {
        log_win32_error("GlobalAlloc(load path)");
        FreeLibrary(shiori);
        return 6;
    }
    log_line("Calling first.dll load...");
    if (!load(path_memory, path_length)) {
        log_line("ERROR: first.dll load returned FALSE.");
        FreeLibrary(shiori);
        return 6;
    }
    log_line("first.dll load returned TRUE.");

    if (serve_mode) {
        int result = serve_requests(request);
        unload();
        FreeLibrary(shiori);
        log_line("IPC host stopped.");
        CloseHandle(log_file);
        return result;
    }

    static const char request_text[] =
        "GET SHIORI/3.0\r\n"
        "Charset: Shift_JIS\r\n"
        "Sender: materia\r\n"
        "SecurityLevel: local\r\n"
        "ID: OnBoot\r\n"
        "Reference0: master\r\n"
        "\r\n";
    long request_length = (long)(sizeof(request_text) - 1);
    HGLOBAL request_memory = global_copy(request_text, request_length);
    if (request_memory == NULL) {
        log_win32_error("GlobalAlloc(request)");
        unload();
        FreeLibrary(shiori);
        return 7;
    }

    log_line("Calling OnBoot...");
    HGLOBAL response_memory = request(request_memory, &request_length);
    if (response_memory == NULL) {
        log_line("ERROR: first.dll request returned NULL.");
        unload();
        FreeLibrary(shiori);
        return 7;
    }
    log_line("--- SHIORI response (UTF-8) ---");
    log_cp932_as_utf8((const char *)response_memory, request_length);
    log_line("");
    log_line("--- end response ---");
    GlobalFree(response_memory);

    unload();
    FreeLibrary(shiori);
    log_line("Probe completed successfully.");
    CloseHandle(log_file);
    return 0;
}
