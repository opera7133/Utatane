import Foundation
import Testing
@testable import UtatanePOSIXShiori

struct RishuTests {
    @Test
    func `proxy runs Perl SHIORI and preserves its response`() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "utatane-rishu-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try fixture.write(to: directory.appending(path: "rishu_remote.pl"), atomically: true, encoding: .utf8)
        let session = try RishuSession(masterDirectoryURL: directory, timeout: 3)

        let response = try await session.request("GET SHIORI/3.0\r\nCharset: Shift_JIS\r\nID: OnBoot\r\n\r\n")
        #expect(response == "SHIORI/3.0 200 OK\r\nCharset: Shift_JIS\r\nValue: \\hRishu\\e\r\n\r\n")
        #expect(try String(contentsOf: directory.appending(path: "loaded"), encoding: .utf8) == directory.path + "/")
        await session.close()
        #expect(FileManager.default.fileExists(atPath: directory.appending(path: "unloaded").path))
    }

    @Test
    func `detects only proxy installations with their remote script`() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "utatane-rishu-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        #expect(!RishuPersonalityEngine.supports(masterDirectoryURL: directory, shioriFilename: "rishu_proxy.dll"))
        try Data().write(to: directory.appending(path: "RISHU_REMOTE.PL"))
        #expect(RishuPersonalityEngine.supports(masterDirectoryURL: directory, shioriFilename: "RISHU_PROXY.DLL"))
        #expect(!RishuPersonalityEngine.supports(masterDirectoryURL: directory, shioriFilename: "rishu.dll"))
    }

    private var fixture: String {
        #"""
        $|=1;
        sub frame { my $first=<STDIN>; my $body=""; while (my $line=<STDIN>) { $body.=$line; last if $line eq "\r\n"; } return ($first,$body); }
        my ($load,$load_body)=frame();
        if ($load_body =~ /Directory: (.*)\r\n/) { open(my $f, ">", "loaded"); print $f $1; close $f; }
        print "RISHU/1.1 200 OK\r\nContent-Length: 3\r\n\r\nabc";
        while (1) {
          my ($line,$body)=frame(); last unless defined $line;
          if ($line =~ /REQUEST/) {
            print "RISHU/1.1 200 OK\r\nOriginal-Response: SHIORI/3.0 200 OK\r\nCharset: Shift_JIS\r\nValue: \\hRishu\\e\r\n\r\n";
          } elsif ($line =~ /UNLOAD/) {
            open(my $f, ">", "unloaded"); close $f;
            print "RISHU/1.1 200 OK\r\n\r\n"; last;
          }
        }
        """#
    }
}
