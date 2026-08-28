import Foundation
import Testing
@testable import UtatanePOSIXShiori

struct ShiolinkTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["UTATANE_MIYOJS_DIRECTORY"] != nil))
    func `installed miyo CLI`() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let module = try #require(ProcessInfo.processInfo.environment["UTATANE_MIYOJS_DIRECTORY"])
        let node = try #require(ProcessInfo.processInfo.environment["UTATANE_NODE_EXECUTABLE"])
        let dictionaries = directory.appending(path: "dic")
        try FileManager.default.createDirectory(at: dictionaries, withIntermediateDirectories: true)
        try "OnTest: 'こんにちは、SHIOLINK。'\n".write(to: dictionaries.appending(path: "test.yaml"), atomically: true, encoding: .utf8)
        let config = try ShiolinkConfiguration(directory: directory, text: """
        [SHIOLINK]
        commandline = "\(node)" "\(module)/bin/miyo-shiolink.js" ./dic
        charmode = UTF-8
        """)
        let session = ShiolinkSession(configuration: config)
        for _ in 0 ..< 10 {
            let response = try await session.request(request("test"))
            #expect(response.contains("Value: こんにちは、SHIOLINK。"))
        }
        await session.close()
    }

    @Test func `configuration and arguments`() throws {
        let config = try ShiolinkConfiguration(directory: URL(filePath: "/tmp"), text: """
        [SHIOLINK]
        commandline = "/a path/node" "./a script.js" "" '$HOME' ;echo
        charmode = UTF-8
        """)
        #expect(config.executable.path == "/a path/node")
        #expect(config.arguments == ["./a script.js", "", "$HOME", ";echo"])
        #expect(config.charset == "UTF-8")
        for setting in ["", "\ncharmode=ANSI"] {
            let ansi = try ShiolinkConfiguration(directory: URL(filePath: "/tmp"), text: "[SHIOLINK]\ncommandline=/bin/test" + setting)
            #expect(ansi.encoding == .shiftJIS)
        }
        #expect(throws: ShiolinkError.self) {
            try ShiolinkConfiguration(directory: URL(filePath: "/tmp"), text: "[SHIOLINK]\ncommandline=node test.js\ncharmode=UTF-8")
        }
        #expect(throws: ShiolinkError.self) { try ShiolinkConfiguration.splitCommand("/bin/foo \"bad") }
        #expect(ShiolinkPersonalityEngine.supports(shioriFilename: "SHIOLINK.dll"))
        #expect(!ShiolinkPersonalityEngine.supports(shioriFilename: "yaya.dll"))
    }

    @Test func `configuration override`() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let original = directory.appending(path: "SHIOLINK.INI")
        let override = directory.appending(path: "SHIOLINK.utatane.ini")
        try Data().write(to: original)
        #expect(ShiolinkConfiguration.configurationURL(in: directory)?.resolvingSymlinksInPath() == original.resolvingSymlinksInPath())
        try Data().write(to: override)
        #expect(ShiolinkConfiguration.configurationURL(in: directory)?.resolvingSymlinksInPath() == override.resolvingSymlinksInPath())
    }

    @Test(arguments: ["UTF-8", "Shift_JIS"])
    func `round trip and graceful unload`(charset: String) async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let session = try fixture(directory: directory, charset: charset)
        let response = try await session.request(request("日本語").replacingOccurrences(of: "UTF-8", with: charset))
        #expect(response.contains("Value: 日本語"))
        #expect(response.contains("Reference0: preserved"))
        #expect(try String(contentsOf: directory.appending(path: "loaded"), encoding: .utf8) == directory.path + "/")
        await session.close()
        #expect(FileManager.default.fileExists(atPath: directory.appending(path: "unloaded").path))
        await #expect(throws: ShiolinkError.self) { try await session.request(request("closed")) }
    }

    @Test func `concurrent requests are serialized`() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let session = try fixture(directory: directory)
        try await withThrowingTaskGroup(of: Void.self) { group in
            for index in 0 ..< 12 {
                group.addTask {
                    let response = try await session.request(request("talk\(index)"))
                    #expect(response.contains("Value: talk\(index)\r\n"))
                }
            }
            try await group.waitForAll()
        }
        await session.close()
    }

    @Test(arguments: ["wrong", "eof", "hang", "partial", "oversize"])
    func `broken child does not block or reuse connection`(mode: String) async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let session = try fixture(directory: directory, mode: mode, timeout: 0.5)
        await #expect(throws: ShiolinkError.self) { try await session.request(request("test")) }
        await #expect(throws: ShiolinkError.self) { try await session.request(request("again")) }
        await session.close()
    }

    @Test func `missing executable fails`() async throws {
        let config = try ShiolinkConfiguration(directory: URL(filePath: "/tmp"), text: "[SHIOLINK]\ncommandline=/nonexistent/utatane-node\ncharmode=UTF-8")
        let session = ShiolinkSession(configuration: config)
        await #expect(throws: ShiolinkError.self) { try await session.request(request("test")) }
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "utatane-shiolink-\(UUID())")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func request(_ value: String) -> String {
        "GET SHIORI/3.0\r\nCharset: UTF-8\r\nID: OnTest\r\nReference0: \(value)\r\n\r\n"
    }

    private func fixture(directory: URL, mode: String = "normal", timeout: TimeInterval = 3, charset: String = "UTF-8") throws -> ShiolinkSession {
        // A tiny protocol peer, not a mock of Foundation.Process. Splits every response into bytes.
        let script = #"""
        $|=1;
        my $mode=shift; my $charset=shift;
        my $id=""; my $value="";
        while (my $line=<STDIN>) {
          $line =~ s/\r?\n$//;
          if ($line =~ /^\*L:(.*)$/) { open(my $f, ">", "loaded"); print $f $1; close $f; }
          elsif ($line =~ /^\*U:/) { open(my $f, ">", "unloaded"); close $f; exit; }
          elsif ($line =~ /^\*S:(.*)$/) {
            $id=$1;
            $id="wrong" if $mode eq "wrong";
            print "*S:$id\r\n";
          }
          elsif ($line =~ /^Reference0: (.*)$/) { $value=$1; }
          elsif ($line eq "") {
            exit if $mode eq "eof";
            sleep 10 if $mode eq "hang";
            $id="wrong" if $mode eq "wrong";
            if ($mode eq "partial") { print "*S:$id\r\nSHIORI/3.0"; sleep 10; }
            if ($mode eq "oversize") { print "x" x (8*1024*1024+8192); sleep 10; }
            my $out="SHIORI/3.0 200 OK\r\nCharset: $charset\r\nValue: $value\r\nReference0: preserved\r\n\r\n";
            for (split //, $out) { print $_; }
          }
        }
        """#
        let scriptURL = directory.appending(path: "peer.pl")
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        let config = try ShiolinkConfiguration(directory: directory, text: """
        [SHIOLINK]
        commandline = /usr/bin/perl "\(scriptURL.path)" \(mode) \(charset)
        charmode = \(charset)
        """, timeout: timeout)
        return ShiolinkSession(configuration: config)
    }
}
