#!/usr/bin/env python3
"""Compare complete ShellLoader.load calls in Release using synthetic directories."""
import argparse
import json
from pathlib import Path
import shutil
import subprocess
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--baseline-loader", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--trials", type=int, default=5)
    args = parser.parse_args()
    if args.trials < 1:
        parser.error("--trials must be positive")
    root = Path(__file__).resolve().parent.parent
    rows = []
    with tempfile.TemporaryDirectory(prefix="utatane-shell-benchmark-") as directory:
        scratch = Path(directory)
        targets = []
        for version, module in [("before", "Before"), ("after", "After")]:
            shell = scratch / "Sources" / (module + "Shell")
            shutil.copytree(root / "packages/shell/Sources", shell)
            if version == "before":
                shutil.copyfile(args.baseline_loader, shell / "ShellLoader.swift")
            benchmark = scratch / "Sources" / (module + "Benchmark")
            benchmark.mkdir(parents=True)
            shutil.copyfile(root / "Scripts/BenchmarkShellLoad.swift", benchmark / "Benchmark.swift")
            settings = '.define("BASELINE")' if version == "before" else ""
            loader_path = shell / "ShellLoader.swift"
            source = loader_path.read_text()
            old_call = "fileManager.contentsOfDirectory(" if version == "before" else "FileManager.default.contentsOfDirectory("
            if source.count(old_call) != (2 if version == "before" else 1):
                raise RuntimeError("directory listing call sites changed; audit the benchmark instrumentation")
            loader_path.write_text(source.replace(old_call, "ShellDirectoryBenchmarkMetrics.contentsOfDirectory("))
            (shell / "BenchmarkMetrics.swift").write_text(METRICS)
            targets += [f'.target(name: "{module}Shell", dependencies: [.product(name: "UtataneCore", package: "UtataneKit")])',
                        f'.executableTarget(name: "{module}Benchmark", dependencies: ["{module}Shell"], swiftSettings: [{settings}])']
        # Swift package manifests use JSON-compatible quoted strings for this path.
        package = root / "packages"
        manifest = ('// swift-tools-version: 6.2\nimport PackageDescription\n'
                    'let package = Package(name: "ShellLoadBenchmark", platforms: [.macOS(.v14)], '
                    f'dependencies: [.package(name: "UtataneKit", path: {json.dumps(str(package))})], '
                    f'targets: [{", ".join(targets)}], swiftLanguageModes: [.v6])\n')
        (scratch / "Package.swift").write_text(manifest)
        lock = package / "Package.resolved"
        if lock.exists():
            shutil.copyfile(lock, scratch / "Package.resolved")
        subprocess.run(["swift", "build", "--package-path", str(scratch), "-c", "release", "--skip-update"], check=True)
        binary_path = Path(subprocess.check_output(["swift", "build", "--package-path", str(scratch), "-c", "release", "--show-bin-path"], text=True).strip())
        fixtures = []
        for count in [64, 5000]:
            for kind in ["images", "mixed"]:
                fixture = scratch / f"fixture-{count}-{kind}"
                fixture.mkdir()
                for index in range(count):
                    (fixture / f"surface{index}.png").touch()
                if kind == "mixed":
                    (fixture / "surfaces.txt").write_text(f"surface.append0-{count - 1} {{\nname,base\n}}\n")
                    (fixture / "surfaces10.txt").write_text("surface0 {\nname,ten\n}\n")
                    (fixture / "surfaces2.txt").write_text("surface0 {\nname,two\n}\n")
                    (fixture / "surface0s.txt").write_text("collision0,0,0,10,10,Head\n")
                    (fixture / "surface0a.txt").write_text("0interval,never\n0pattern0,1,10,overlay,0,0\n")
                    (fixture / "descript.txt").write_text("seriko.use_self_alpha,1\n")
                    (fixture / "alias.txt").write_text("sakura.surface.alias {\nnormal,[0]\n}\n")
                fixtures.append((count, kind, fixture))
        for trial in range(args.trials):
            for count, kind, fixture in fixtures:
                versions = ["Before", "After"] if trial % 2 == 0 else ["After", "Before"]
                checksums = []
                for module in versions:
                    row = json.loads(subprocess.check_output([str(binary_path / (module + "Benchmark")), str(fixture)], text=True))
                    checksums.append(row["checksum"])
                    row.update(version=module.lower(), trial=trial, imageCount=count, kind=kind)
                    rows.append(row)
                    print(json.dumps(row), flush=True)
                if len(set(checksums)) != 1:
                    raise RuntimeError("before/after shell counts differ")
    args.output.write_text(json.dumps(rows, indent=2) + "\n")

METRICS = r'''
import Foundation
private final class EnumerationCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    func increment() { lock.withLock { value += 1 } }
    func read() -> Int { lock.withLock { value } }
}
public enum ShellDirectoryBenchmarkMetrics {
    private static let counter = EnumerationCounter()
    public static var enumerationCount: Int { counter.read() }
    static func contentsOfDirectory(at url: URL, includingPropertiesForKeys keys: [URLResourceKey]?, options: FileManager.DirectoryEnumerationOptions) throws -> [URL] {
        counter.increment()
        return try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: keys, options: options)
    }
    static func contentsOfDirectory(atPath path: String) throws -> [String] {
        counter.increment()
        return try FileManager.default.contentsOfDirectory(atPath: path)
    }
}
'''

if __name__ == "__main__":
    main()
