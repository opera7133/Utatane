#!/usr/bin/env python3
"""Exercise AppKit termination and Launch Services with an isolated fixture app.

Requires a logged-in macOS GUI session. Never opens Utatane or its content roots.
"""

import os
import plistlib
from pathlib import Path
import subprocess
import tempfile
import time
import uuid


ROOT = Path(__file__).resolve().parent.parent


def main() -> None:
    identifier = f"dev.utatane.relaunch-smoke.{uuid.uuid4().hex}"
    with tempfile.TemporaryDirectory(prefix="utatane-relaunch-") as temporary:
        directory = Path(temporary)
        bundle = directory / "Relaunch 日本語.app"
        contents = bundle / "Contents"
        executable = contents / "MacOS" / "RelaunchSmoke"
        executable.parent.mkdir(parents=True)
        with (contents / "Info.plist").open("wb") as stream:
            plistlib.dump({
                "CFBundleIdentifier": identifier,
                "CFBundleExecutable": executable.name,
                "CFBundlePackageType": "APPL",
                "CFBundleName": "RelaunchSmoke",
                "CFBundleVersion": "1",
                "CFBundleDevelopmentRegion": "ja",
                "LSUIElement": True,
            }, stream)
        for language, label in (("ja", "日本語"), ("en", "English")):
            resource = contents / "Resources" / f"{language}.lproj" / "Localizable.strings"
            resource.parent.mkdir(parents=True)
            resource.write_text(f'"greeting" = "{label}";\n', encoding="utf-8")
        subprocess.run([
            "xcrun", "swiftc", "-parse-as-library", "-module-cache-path", str(directory / "cache"),
            str(ROOT / "packages/platform-macos/Sources/ApplicationRelauncher.swift"),
            str(ROOT / "Scripts/Fixtures/ApplicationRelaunchSmoke.swift"),
            "-o", str(executable),
        ], check=True)
        process = subprocess.Popen(
            [str(executable), "-AppleLanguages", "(ja)"],
            env={**os.environ, "UTATANE_CONTENT_ROOT": str(directory)},
        )
        log = directory / "events.log"
        try:
            process.wait(timeout=15)
            deadline = time.monotonic() + 15
            while time.monotonic() < deadline:
                lines = log.read_text(encoding="utf-8").splitlines() if log.exists() else []
                if len(lines) >= 6:
                    break
                time.sleep(0.1)
            assert process.returncode == 0, f"First process failed: {process.returncode}"
            assert len(lines) == 6, lines
            assert "localized=日本語" in lines[0], lines
            assert "shutdown-start" in lines[1], lines
            assert "shutdown-saved" in lines[2], lines
            assert "will-terminate" in lines[3], lines
            assert "localized=English" in lines[4], lines
            assert "will-terminate" in lines[5], lines
            assert lines[0].split()[1] != lines[4].split()[1], lines
            assert str(bundle) in lines[0] and str(bundle) in lines[4], lines
            print("PASS: main-queue restart -> asynchronous save -> exit -> same bundle, new PID, English")
        finally:
            if process.poll() is None:
                process.terminate()
                process.wait(timeout=5)
                # Let the already-started helper finish after a failed shutdown.
                time.sleep(1)
            subprocess.run(["defaults", "delete", identifier], capture_output=True, check=False)


if __name__ == "__main__":
    main()
