#!/usr/bin/env python3
"""Compare an old analyzer source with the working tree on macOS (synthetic audio)."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--baseline-source", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--trials", type=int, default=5)
    args = parser.parse_args()
    if args.trials < 1:
        parser.error("--trials must be positive")
    root = Path(__file__).resolve().parent.parent
    current = root / "packages/platform-macos/Sources/SoundSpectrumAnalyzer.swift"
    harness = root / "Scripts/BenchmarkSoundSpectrum.swift"
    probe = root / "Scripts/BenchmarkSoundSpectrumAllocations.c"
    rows = []
    with tempfile.TemporaryDirectory(prefix="utatane-spectrum-") as directory:
        scratch = Path(directory)
        dylib = scratch / "allocations.dylib"
        subprocess.run(["xcrun", "clang", "-O2", "-dynamiclib", str(probe), "-o", str(dylib)], check=True)
        binaries = []
        for version, source in [("before", args.baseline_source.resolve()), ("after", current)]:
            binary = scratch / version
            subprocess.run(["xcrun", "swiftc", "-O", "-parse-as-library", "-module-cache-path",
                            str(scratch / "module-cache"), str(source),
                            str(root / "packages/platform-macos/Sources/SoundSpectrumSampleStore.swift"), str(harness), "-o", str(binary)], check=True)
            binaries.append((version, binary))
        for mode in ["throughput", "allocations", "cadence"]:
            for trial in range(1 if mode == "allocations" else args.trials):
                for streams in [1, 4]:
                    for bands in ([31] if mode == "cadence" else [0, 31]):
                        # Alternate order to reduce a consistent warm/thermal ordering bias.
                        for version, binary in (binaries if trial % 2 == 0 else binaries[::-1]):
                            command = [str(binary), str(streams), str(bands)]
                            env = os.environ.copy()
                            if mode == "allocations":
                                env["DYLD_INSERT_LIBRARIES"] = str(dylib)
                            if mode == "cadence":
                                command += ["--cadence"] + (["--worker"] if version == "after" else [])
                            row = json.loads(subprocess.check_output(command, env=env, text=True))
                            if mode == "allocations" and row.get("observedAllocationCalls", 0) == 0:
                                raise RuntimeError("allocation probe was not loaded")
                            row.update(mode=mode, version=version, trial=trial)
                            rows.append(row)
                            print(json.dumps(row), flush=True)
    args.output.write_text(json.dumps(rows, indent=2) + "\n")


if __name__ == "__main__":
    main()
