import Foundation
import Testing
@testable import UtataneModuleHost
import UtataneNativeSaori
import UtataneShiori

struct UtataneModuleResolverTests {
    @Test func `priority and explicit errors`() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let support = root.appending(path: "support")
        let bundle = root.appending(path: "resources")
        let resolver = UtataneModuleResolver(applicationSupportURL: support, bundledResourcesURL: bundle, environment: [:])
        #expect(try resolver.misakaModuleURL() == nil)
        let bundled = bundle.appending(path: "NativeShiori/misaka-native/lib/libUtataneMisaka.dylib")
        let installed = support.appending(path: "misaka-native/lib/libUtataneMisaka.dylib")
        for file in [bundled, installed] {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data().write(to: file)
            #expect(try resolver.misakaModuleURL() == file)
        }
        let explicit = root.appending(path: "missing.dylib")
        #expect(try UtataneModuleResolver(applicationSupportURL: support, bundledResourcesURL: bundle,
                                          environment: ["UTATANE_MISAKA_MODULE": explicit.path]).misakaModuleURL() == explicit)
        #expect(throws: UtataneModuleError.self) {
            try UtataneModuleResolver(environment: ["UTATANE_MISAKA_MODULE": "relative.dylib"]).misakaModuleURL()
        }
    }
}

private struct EmptySaori: NativeSaoriCalling {
    func load(_: String) {}
    func unload(_: String) {}
    func call(_: String, arguments _: [String]) -> String {
        ""
    }
}

struct UtataneModuleLoaderTests {
    private func withLibrary(_ source: String, _ body: (URL, URL) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let code = root.appending(path: "module.c")
        let library = root.appending(path: "module.dylib")
        try source.write(to: code, atomically: true, encoding: .utf8)
        let include = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().appending(path: "module-sdk/include")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = ["clang", "-dynamiclib", "-I", include.path, code.path, "-o", library.path]
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
        try body(library, root)
    }

    @Test func `rejects unknown version and missing symbols`() throws {
        try withLibrary("unsigned um_api_version(void) { return 99; }") { library, root in
            #expect(throws: UtataneModuleError.unsupportedVersion(99)) {
                try UtataneModuleSession(moduleURL: library, masterDirectoryURL: root,
                                         variableStoreURL: root.appending(path: "state"), saoriCaller: EmptySaori())
            }
        }
        try withLibrary("unsigned um_api_version(void) { return 1; }") { library, root in
            #expect(throws: UtataneModuleError.missingSymbol("um_create")) {
                try UtataneModuleSession(moduleURL: library, masterDirectoryURL: root,
                                         variableStoreURL: root.appending(path: "state"), saoriCaller: EmptySaori())
            }
        }
    }

    @Test(arguments: ["invalid-utf8", "oversize", "error"])
    func `releases module owned outputs on failure`(mode: String) throws {
        let invalid = switch mode {
        case "invalid-utf8": "out->data[0] = 0xff; out->length = 1; return UM_OK;"
        case "oversize": "out->length = UM_MAX_BYTES + 1; return UM_OK;"
        default: "memcpy(out->data, \"error\", 5); out->length = 5; return UM_ENGINE;"
        }
        let source = """
        #include "utatane_module.h"
        #include <stdlib.h>
        #include <string.h>
        static int allocations = 0;
        uint32_t um_api_version(void) { return 1; }
        int32_t um_create(const UMConfig *c, const UMHostV1 *h, uint64_t *id, UMBuffer *e) { *id = 1; return 0; }
        int32_t um_destroy(uint64_t id, UMBuffer *e) { return allocations ? UM_ENGINE : UM_OK; }
        int32_t um_discard(uint64_t id) { return UM_OK; }
        void um_release(UMBuffer *b) { if (b->data) { allocations--; free(b->data); } *b = (UMBuffer){0}; }
        int32_t um_request(uint64_t id, const uint8_t *p, uint32_t n, UMBuffer *out) {
            out->data = malloc(16); allocations++; \(invalid)
        }
        """
        try withLibrary(source) { library, root in
            let session = try UtataneModuleSession(moduleURL: library, masterDirectoryURL: root,
                                                   variableStoreURL: root.appending(path: "state"), saoriCaller: EmptySaori())
            #expect(throws: UtataneModuleError.self) { try session.request(ShioriRequest(method: "GET")) }
            // The fixture refuses to close if the failed response was not released exactly once.
            try session.close()
            #expect(throws: UtataneModuleError.closed) { try session.request(ShioriRequest(method: "GET")) }
        }
    }
}
