#!/usr/bin/env python3
"""Measure synthetic frame drift/CPU against the pre-R08 SuspensionClock source."""
import argparse
import json
from pathlib import Path
import subprocess
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--baseline-clock", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--trials", type=int, default=5)
    args = parser.parse_args()
    if args.trials < 1:
        parser.error("--trials must be positive")
    root = Path(__file__).resolve().parent.parent
    clock = root / "packages/core/Sources/SuspensionClock.swift"
    timeline = root / "packages/core/Sources/PlaybackTimeline.swift"
    harness = root / "Scripts/BenchmarkPlaybackTiming.swift"
    rows = []
    with tempfile.TemporaryDirectory(prefix="utatane-timing-") as directory:
        scratch = Path(directory)
        binaries = []
        for version, source in [("before", args.baseline_clock.resolve()), ("after", clock)]:
            binary = scratch / version
            subprocess.run(["xcrun", "swiftc", "-O", "-parse-as-library", "-module-cache-path",
                            str(scratch / "module-cache"), *(["-D", "BASELINE"] if version == "before" else []),
                            str(source), str(timeline), str(harness), "-o", str(binary)], check=True)
            binaries.append((version, binary))
        for trial in range(args.trials):
            for streams in [1, 4]:
                for interval in [20, 40]:
                    for version, binary in (binaries if trial % 2 == 0 else binaries[::-1]):
                        row = json.loads(subprocess.check_output([str(binary), str(streams), str(interval)], text=True))
                        row.update(version=version, trial=trial)
                        rows.append(row)
                        print(json.dumps(row), flush=True)
    args.output.write_text(json.dumps(rows, indent=2) + "\n")


if __name__ == "__main__":
    main()
