import Foundation
import Testing
import UtataneCore
import UtataneModuleHost
import UtataneNativeSaori

private struct NativeProcessFixture {
    let root: URL
    let host: URL
    let module: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "SHIORI process \(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        host = root.appending(path: "host")
        module = root.appending(path: "test.dylib")
        let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appending(path: "../../../../..").standardizedFileURL
        let source = root.appending(path: "test.c")
        try #"""
        #include <dlfcn.h>
        #include <stdint.h>
        #include <stdio.h>
        #include <stdlib.h>
        #include <string.h>
        #include <unistd.h>
        static int count;
        static void metadata(int32_t phase) {
            typedef void (*Reporter)(int32_t,int32_t,uint64_t,uint64_t,const char *);
            Reporter reporter = (Reporter)dlsym(RTLD_DEFAULT, "utatane_host_saori_diagnostic");
            if (reporter) reporter(phase, phase == 2 ? 200 : 1, 42, 123, "/fixture/libecho.dylib");
        }
        int32_t loadu(void *p, int32_t n) {
            free(p); (void)n;
            FILE *f = fopen("count.txt", "r");
            if (f) { fscanf(f, "%d", &count); fclose(f); }
            metadata(1);
            puts("diagnostic on stdout"); fflush(stdout);
            return 1;
        }
        int32_t unload(void) {
            metadata(3);
            if (access("reject-save", F_OK) == 0) return 0;
            FILE *f = fopen("count.txt", "w");
            if (!f) return 0;
            fprintf(f, "%d", count); fclose(f); return 1;
        }
        void *request(void *p, int32_t *n) {
            metadata(2);
            char *text = malloc((size_t)*n + 1); memcpy(text, p, *n); text[*n] = 0; free(p);
            if (strstr(text, "CRASH")) _exit(77);
            if (strstr(text, "WAIT")) sleep(60);
            if (strstr(text, "BAD_UTF8")) { free(text); *n = 1; char *r = malloc(1); r[0] = (char)0xff; return r; }
            free(text); char output[100];
            *n = snprintf(output, sizeof(output), "SHIORI/3.0 200 OK\r\nValue: %d\r\n\r\n", ++count);
            void *r = malloc(*n); memcpy(r, output, *n); return r;
        }
        """#.write(to: source, atomically: true, encoding: .utf8)
        for arguments in [
            ["clang", "-O0", repository.appending(path: "tools/native-shiori-host/main.c").path, "-o", host.path],
            ["clang", "-dynamiclib", source.path, "-o", module.path]
        ] {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
            process.arguments = arguments
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { throw NativeShioriProcessError.invalidFrame }
        }
    }

    func directory(_ name: String) throws -> URL {
        let url = root.appending(path: name)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}

struct NativeShioriProcessTests {
    @Test func `worker callbacks fail without consuming or corrupting the synchronous pipe`() throws {
        let fixture = try NativeProcessFixture()
        defer { fixture.remove() }
        let source = fixture.root.appending(path: "worker.c")
        let module = fixture.root.appending(path: "worker.dylib")
        try #"""
        #include <dlfcn.h>
        #include <pthread.h>
        #include <stdint.h>
        #include <stdlib.h>
        #include <string.h>
        typedef void *(*Internal)(const void *, int32_t, int32_t *);
        typedef int32_t (*Window)(int32_t, int32_t, int32_t, int32_t, int32_t *);
        static Internal internal;
        static Window window;
        int32_t utatane_internal_saori_set_callback(Internal value) { internal = value; return 1; }
        int32_t utatane_wmove_set_window_callback(Window value) { window = value; return 1; }
        int32_t loadu(void *p, int32_t n) { free(p); return n > 0 && internal && window; }
        int32_t unload(void) { return 1; }
        static void *worker(void *ignored) {
            (void)ignored;
            int32_t size = 123;
            const char *wire = "EXECUTE SAORI/1.0\r\nModule: internal_system\r\nCharset: UTF-8\r\nArgument0: ListModules\r\n\r\n";
            void *result = internal(wire, (int32_t)strlen(wire), &size);
            int rejected = !result && size == 0 && window(1, 0, 0, 0, NULL) == 0;
            free(result);
            typedef void (*Reporter)(int32_t,int32_t,uint64_t,uint64_t,const char *);
            Reporter reporter = (Reporter)dlsym(RTLD_DEFAULT, "utatane_host_saori_diagnostic");
            if (reporter) reporter(2, 200, 0, 0, "/fixture/worker.dylib");
            return (void *)(intptr_t)rejected;
        }
        void *request(void *input, int32_t *size) {
            free(input);
            pthread_t thread;
            if (pthread_create(&thread, NULL, worker, NULL)) return NULL;
            void *result = NULL;
            pthread_join(thread, &result);
            const char *answer = result ? "worker-rejected" : "worker-failed";
            *size = (int32_t)strlen(answer);
            void *output = malloc(*size); memcpy(output, answer, *size); return output;
        }
        """#.write(to: source, atomically: true, encoding: .utf8)
        let compiler = Process()
        compiler.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        compiler.arguments = ["clang", "-dynamiclib", source.path, "-o", module.path]
        try compiler.run()
        compiler.waitUntilExit()
        #expect(compiler.terminationStatus == 0)
        let store = AppLogStore(), diagnostics = SaoriDiagnostics(store: store)
        diagnostics.isEnabled = true
        let session = try NativeShioriProcessSession(directoryURL: fixture.root, moduleURL: module, diagnostics: diagnostics, hostURL: fixture.host)
        defer { try? session.close() }
        #expect(try session.request("WORKER") == "worker-rejected")
        #expect(try session.request("WORKER again") == "worker-rejected")
        #expect(store.snapshot().isEmpty)
    }

    @Test func `failed module initialization returns its bounded diagnostic`() throws {
        let fixture = try NativeProcessFixture()
        defer { fixture.remove() }
        let source = fixture.root.appending(path: "error.c")
        let module = fixture.root.appending(path: "error.dylib")
        try #"""
        #include <stdint.h>
        #include <stdlib.h>
        #include <string.h>
        int32_t loadu(void *p, int32_t n) { free(p); (void)n; return 0; }
        int32_t unload(void) { return 1; }
        void *request(void *p, int32_t *n) { free(p); *n = 0; return NULL; }
        void *utatane_shiori_last_error(int32_t *n) {
            const char *error = "DNProxy [compile]: fixture failure";
            *n = (int32_t)strlen(error);
            void *result = malloc(*n); memcpy(result, error, *n); return result;
        }
        """#.write(to: source, atomically: true, encoding: .utf8)
        let compiler = Process()
        compiler.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        compiler.arguments = ["clang", "-dynamiclib", source.path, "-o", module.path]
        try compiler.run()
        compiler.waitUntilExit()
        #expect(compiler.terminationStatus == 0)
        do {
            _ = try NativeShioriProcessSession(directoryURL: fixture.root, moduleURL: module, hostURL: fixture.host)
            Issue.record("load must fail")
        } catch let error as NativeShioriProcessError {
            guard case let .hostFailure(status, reason) = error else { throw error }
            #expect(status == 3)
            #expect(reason == "DNProxy [compile]: fixture failure")
            #expect(!error.canRecoverByLoadingAnotherModule)
        }
    }

    @Test func `SAORI window calls return to the owning ghost`() throws {
        let fixture = try NativeProcessFixture()
        defer { fixture.remove() }
        let source = fixture.root.appending(path: "windows.c")
        let module = fixture.root.appending(path: "wmove.dylib")
        try #"""
        #include <stdint.h>
        #include <stdlib.h>
        #include <stdio.h>
        #include <string.h>
        typedef int32_t (*Callback)(int32_t, int32_t, int32_t, int32_t, int32_t *);
        static Callback callback;
        int32_t utatane_wmove_set_window_callback(Callback value) { callback = value; return 1; }
        int32_t loadu(void *p, int32_t n) { free(p); (void)n; return callback != NULL; }
        int32_t unload(void) { return 1; }
        void *request(void *p, int32_t *n) {
            free(p);
            int32_t frame[4] = {0};
            int32_t desktop[4] = {0};
            int32_t success = callback(1, 1, 0, 0, frame);
            success += callback(2, 0, 0, 0, desktop);
            success += callback(3, 1, 20, 5, NULL);
            char text[100];
            *n = snprintf(text, sizeof(text), "%d,%d,%d,%d", success, frame[0], frame[1], desktop[0]);
            void *result = malloc(*n); memcpy(result, text, *n); return result;
        }
        """#.write(to: source, atomically: true, encoding: .utf8)
        let compiler = Process()
        compiler.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        compiler.arguments = ["clang", "-dynamiclib", source.path, "-o", module.path]
        try compiler.run()
        compiler.waitUntilExit()
        #expect(compiler.terminationStatus == 0)
        let windows = ProcessWindowController()
        let session = try NativeShioriProcessSession(directoryURL: fixture.root, moduleURL: module,
                                                     hostURL: fixture.host, windowController: windows)
        #expect(try session.request("EXECUTE SAORI/1.0\r\n\r\n") == "3,100,200,1440")
        #expect(windows.moves == ["1,20,5"])
        try session.close()
    }

    @Test func `globals cwd and persistence are isolated while stdout stays outside the protocol`() throws {
        let fixture = try NativeProcessFixture()
        defer { fixture.remove() }
        let a = try fixture.directory("A 日本語")
        let b = try fixture.directory("B")
        let first = try NativeShioriProcessSession(directoryURL: a, moduleURL: fixture.module, hostURL: fixture.host)
        let second = try NativeShioriProcessSession(directoryURL: b, moduleURL: fixture.module, hostURL: fixture.host)
        #expect(try first.request("COUNT").contains("Value: 1"))
        #expect(try first.request("COUNT").contains("Value: 2"))
        #expect(try second.request("COUNT").contains("Value: 1"))
        try first.close()
        try first.close()
        #expect(throws: NativeShioriProcessError.self) { try first.request("COUNT") }
        #expect(try second.request("COUNT").contains("Value: 2"))
        try second.close()
        let reloaded = try NativeShioriProcessSession(directoryURL: a, moduleURL: fixture.module, hostURL: fixture.host)
        #expect(try reloaded.request("COUNT").contains("Value: 3"))
        try reloaded.close()
        #expect(try String(contentsOf: b.appending(path: "count.txt"), encoding: .utf8) == "2")
    }

    @Test(arguments: ["CRASH", "WAIT", "BAD_UTF8"])
    func `failed child cannot affect another session or replay its request`(command: String) throws {
        let fixture = try NativeProcessFixture()
        defer { fixture.remove() }
        let failed = try NativeShioriProcessSession(directoryURL: fixture.directory("bad"), moduleURL: fixture.module,
                                                    hostURL: fixture.host, timeout: command == "WAIT" ? 2 : 5)
        let healthy = try NativeShioriProcessSession(directoryURL: fixture.directory("good"), moduleURL: fixture.module,
                                                     hostURL: fixture.host)
        #expect(throws: NativeShioriProcessError.self) { try failed.request(command) }
        #expect(throws: NativeShioriProcessError.self) { try failed.request("COUNT") }
        #expect(try healthy.request("COUNT").contains("Value: 1"))
        try healthy.close()
    }

    @Test func `abandoned session attempts to save off the caller thread`() async throws {
        let fixture = try NativeProcessFixture()
        defer { fixture.remove() }
        let directory = try fixture.directory("abandoned")
        var session: NativeShioriProcessSession? = try NativeShioriProcessSession(directoryURL: directory, moduleURL: fixture.module, hostURL: fixture.host)
        _ = try session?.request("COUNT")
        session = nil
        let saved = directory.appending(path: "count.txt")
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while (try? String(contentsOf: saved, encoding: .utf8)) != "1", ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(try String(contentsOf: saved, encoding: .utf8) == "1")
    }

    @Test func `failed save remains retryable`() throws {
        let fixture = try NativeProcessFixture()
        defer { fixture.remove() }
        let directory = try fixture.directory("save")
        let marker = directory.appending(path: "reject-save")
        try Data().write(to: marker)
        let session = try NativeShioriProcessSession(directoryURL: directory, moduleURL: fixture.module, hostURL: fixture.host)
        _ = try session.request("COUNT")
        #expect(throws: NativeShioriProcessError.self) { try session.close() }
        try FileManager.default.removeItem(at: marker)
        try session.close()
        #expect(try String(contentsOf: directory.appending(path: "count.txt"), encoding: .utf8) == "1")
    }

    @Test func `missing library is an eligible initialization failure`() throws {
        let fixture = try NativeProcessFixture()
        defer { fixture.remove() }
        do {
            _ = try NativeShioriProcessSession(directoryURL: fixture.root, moduleURL: fixture.root.appending(path: "missing.dylib"),
                                               hostURL: fixture.host)
            Issue.record("Expected a load failure")
        } catch let error as NativeShioriProcessError {
            #expect(error.canRecoverByLoadingAnotherModule)
        }
    }
}

private final class ProcessWindowController: NativeSaoriWindowControlling, @unchecked Sendable {
    var moves: [String] = []

    func frame(scope: Int) -> NativeSaoriWindowFrame? {
        scope == 1 ? .init(x: 100, y: 200, width: 50, height: 80) : nil
    }

    func desktopSize() -> (width: Int, height: Int) {
        (1440, 900)
    }

    func move(scope: Int, x: Int, speed: Int) {
        moves.append("\(scope),\(x),\(speed)")
    }
}

@Test func `SAORI metadata toggles on a live helper without changing responses`() throws {
    let fixture = try NativeProcessFixture()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let store = AppLogStore(), diagnostics = SaoriDiagnostics(store: store)
    let session = try NativeShioriProcessSession(directoryURL: fixture.root, moduleURL: fixture.module, diagnostics: diagnostics, hostURL: fixture.host)
    defer { try? session.close() }
    #expect(try session.request("GET SHIORI/3.0\r\n\r\n").contains("Value: 1"))
    #expect(store.snapshot().isEmpty)
    diagnostics.isEnabled = true
    #expect(try session.request("GET SHIORI/3.0\r\n\r\n").contains("Value: 2"))
    #expect(store.snapshot().count == 1)
    #expect(store.snapshot().first?.message.contains("phase=call backend=dylib status=200") == true)
    diagnostics.isEnabled = false
    _ = try session.request("GET SHIORI/3.0\r\n\r\n")
    #expect(store.snapshot().count == 1)
    diagnostics.isEnabled = true
    try session.close()
    #expect(store.snapshot().last?.message.contains("phase=unload") == true)
}

@Test func `generic filename preserves YAYA backup and same-engine recovery`() throws {
    let fixture = try NativeProcessFixture()
    defer { fixture.remove() }
    let master = try fixture.directory("ghost 日本語")
    let selected = master.appending(path: "shiori.dylib")
    try Data("broken native library".utf8).write(to: selected)
    try Data("original save".utf8).write(to: master.appending(path: "yaya_variable.cfg"))
    let support = fixture.root.appending(path: "NativeShiori")
    let shared = support.appending(path: "yaya-6/lib/libyaya-6.dylib")
    try FileManager.default.createDirectory(at: shared.deletingLastPathComponent(), withIntermediateDirectories: true)
    try FileManager.default.copyItem(at: fixture.module, to: shared)
    let resolver = UtataneModuleResolver(applicationSupportURL: support, bundledResourcesURL: nil, environment: [:])
    let session = try NativeShioriSession(directoryURL: master, moduleURL: selected, selectedKind: .yaya6, moduleResolver: resolver, hostURL: fixture.host)
    defer { try? session.close() }
    #expect(try session.request("GET SHIORI/3.0\r\nID: OnBoot\r\n\r\n").contains("Value: 1"))
    #expect(try String(contentsOf: master.appending(path: "Utatane-YAYA-backup/yaya_variable.cfg"), encoding: .utf8) == "original save")
    // An explicit unknown module has no inferred engine and must not recover to YAYA.
    #expect(throws: NativeShioriProcessError.self) {
        try NativeShioriSession(directoryURL: master, moduleURL: selected, moduleResolver: resolver, hostURL: fixture.host)
    }
}

@Test func `explicit selected native module loads and failed selection remains an error`() throws {
    let fixture = try NativeProcessFixture()
    defer { fixture.remove() }
    let selection = GhostShioriSelection(modulePath: fixture.module.path)
    let session = try NativeShioriSession(directoryURL: fixture.root, selectedModule: selection, hostURL: fixture.host)
    #expect(try session.request("GET SHIORI/3.0\r\nID: OnTest\r\n\r\n").contains("200"))
    let invalid = fixture.root.appending(path: "broken.dylib")
    try Data("invalid native image".utf8).write(to: invalid)
    #expect(throws: (any Error).self) {
        try NativeShioriSession(directoryURL: fixture.root,
                                selectedModule: GhostShioriSelection(modulePath: invalid.path, kindID: "yaya-6"),
                                hostURL: fixture.host)
    }
}
