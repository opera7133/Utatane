#!/usr/bin/env python3
"""Compare actual AppKit terminateLater behavior in isolated, windowless processes."""
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
PROBE = '''import AppKit
@MainActor final class Delegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        FileHandle.standardOutput.write(Data("shutdown requested\\n".utf8))
        Task { @MainActor in
            FileHandle.standardOutput.write(Data("async cleanup completed\\n".utf8))
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
@main struct Main {
    @MainActor static func main() {
        let application = NSApplication.shared
        application.setActivationPolicy(.prohibited)
        let delegate = Delegate()
        application.delegate = delegate
        Task { @MainActor in
            if CommandLine.arguments.contains("direct") { application.terminate(nil) }
            else { ApplicationTermination.request() }
        }
        withExtendedLifetime(delegate) { application.run() }
    }
}
'''


def main():
    with tempfile.TemporaryDirectory(prefix="Utatane termination 日本語 ") as temporary:
        directory = Path(temporary)
        source = directory / "Probe.swift"
        source.write_text(PROBE)
        executable = directory / "probe"
        subprocess.run(["xcrun", "swiftc", "-parse-as-library", "-swift-version", "6",
                        str(ROOT / "packages/platform-macos/Sources/ApplicationTermination.swift"),
                        str(source), "-o", str(executable)], check=True, timeout=90)
        # This intentionally stuck child is ours, not the running Utatane app.
        try:
            result = subprocess.run([str(executable), "direct"], capture_output=True, timeout=5)
        except subprocess.TimeoutExpired as error:
            assert b"shutdown requested" in (error.stdout or b""), "Probe did not reach AppKit termination"
            assert b"async cleanup completed" not in (error.stdout or b"")
        else:
            raise AssertionError(f"Original deadlock was not reproduced: {result.returncode}")
        result = subprocess.run([str(executable), "deferred"], capture_output=True, timeout=20)
        assert result.returncode == 0, result.stderr.decode(errors="replace")
        assert b"async cleanup completed" in result.stdout
    print("PASS: direct termination stalls; deferred termination completes async cleanup and exits")


if __name__ == "__main__":
    main()
