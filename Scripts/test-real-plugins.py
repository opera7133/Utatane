#!/usr/bin/env python3
"""Check pinned real plugin dictionaries using disposable copies and native YAYA."""
import argparse
import hashlib
import json
import os
import platform
from pathlib import Path, PurePosixPath
import re
import stat
import subprocess
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parents[1]
BALLOON_REVISION = "04ac6c086a03f1394c572d0748e4bdd190046c77"
DIARY_URL = "https://github.com/ambergon/UkagakaPlugin_DBdiary/releases/download/1.0.1/UkagakaPlugin_DBdiary.nar"
AKARI_URL = "https://codeload.github.com/nikolat/sudohaikuyu/zip/998d8f65c86cc541a34c6fbec2e721fcb0ba0ba2"
AKARI_SHA256 = "e482e97e8cc798986963cfe390199271e995d4e32d4161f3437be2470407d25c"
DIARY_SHA256 = "afd10bc9eda37b408b21b5facbc3e74f269824e72ce91d89728e502b87f51489"


def sha256(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def tree_hash(root):
    """Exclude checkout metadata; dictionaries and original saves must stay intact."""
    files = {}
    for path in root.rglob("*"):
        relative = path.relative_to(root)
        if ".git" in relative.parts:
            continue
        if path.is_symlink():
            raise ValueError(f"Source contains a symlink: {relative}")
        if path.is_file():
            files[relative.as_posix()] = sha256(path)
    return hashlib.sha256(json.dumps(files, sort_keys=True).encode()).hexdigest()


def extract(archive, destination):
    """Extract bounded regular ZIP entries, omitting accidental Git metadata."""
    with zipfile.ZipFile(archive) as source:
        entries = source.infolist()
        if len(entries) > 5000 or sum(item.file_size for item in entries) > 100 * 1024 * 1024:
            raise ValueError("Plugin archive exceeds the corpus limits")
        keys = set()
        for entry in entries:
            name = entry.filename.replace("\\", "/")
            path = PurePosixPath(name)
            mode = entry.external_attr >> 16
            if path.is_absolute() or ".." in path.parts or ":" in name or stat.S_ISLNK(mode):
                raise ValueError(f"Unsafe archive entry: {name}")
            if stat.S_IFMT(mode) not in (0, stat.S_IFREG, stat.S_IFDIR):
                raise ValueError(f"Unsupported archive entry: {name}")
            key = path.as_posix().rstrip("/").casefold()
            if not key or key in keys:
                raise ValueError(f"Duplicate archive entry: {name}")
            keys.add(key)
            if ".git" in path.parts:
                continue
            output = destination.joinpath(*path.parts)
            if entry.is_dir():
                output.mkdir(parents=True, exist_ok=True)
            else:
                output.parent.mkdir(parents=True, exist_ok=True)
                output.write_bytes(source.read(entry))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--modules", type=Path, required=True, help="Utatane Modules checkout containing the audited port tool")
    parser.add_argument("--balloonselector-source", type=Path, required=True, help=f"Clean nikolat/balloonselector checkout at {BALLOON_REVISION}")
    parser.add_argument("--dbdiary-nar", type=Path, required=True, help=f"Original 1.0.1 NAR from {DIARY_URL}")
    parser.add_argument("--yaya-module", type=Path, required=True)
    parser.add_argument("--host", type=Path, required=True)
    parser.add_argument("--kagari-module", type=Path, help="Also exercise instance ABI, separate state, and reload with a synthetic Lua dictionary")
    parser.add_argument("--akari-plugin-archive", type=Path, help=f"Optional fixed AKARI image-menu source: {AKARI_URL}")
    parser.add_argument("--akari-module", type=Path, help="AKARI 2.003-r5 or later")
    parser.add_argument("--architecture", choices=("arm64", "x86_64"), default=platform.machine())
    parser.add_argument("--report", type=Path, required=True, help="JSON report; a sibling .log contains test output")
    args = parser.parse_args()
    if bool(args.akari_plugin_archive) != bool(args.akari_module):
        parser.error("Specify both --akari-plugin-archive and --akari-module")
    if args.akari_plugin_archive and sha256(args.akari_plugin_archive) != AKARI_SHA256:
        raise ValueError("AKARI image-menu source differs from the audited revision")
    report_path = args.report.resolve()
    report_path.parent.mkdir(parents=True, exist_ok=True)
    source = args.balloonselector_source.resolve()
    diary = args.dbdiary_nar.resolve()
    revision = subprocess.check_output(["git", "-C", str(source), "rev-parse", "HEAD"], text=True).strip()
    if revision != BALLOON_REVISION or subprocess.check_output(["git", "-C", str(source), "status", "--porcelain", "--untracked-files=no"], text=True).strip():
        raise ValueError("BalloonSelector must be the clean audited revision")
    if sha256(diary) != DIARY_SHA256:
        raise ValueError("DBdiary archive differs from the audited release")
    port = args.modules.resolve() / "scripts/port_balloonselector.py"
    inputs = {"balloonselector": {"url": "https://github.com/nikolat/balloonselector", "revision": BALLOON_REVISION,
                                  "treeSHA256": tree_hash(source), "portToolSHA256": sha256(port)},
              "dbdiary": {"url": DIARY_URL, "sha256": sha256(diary)},
              "yaya": {"path": str(args.yaya_module.resolve()), "sha256": sha256(args.yaya_module)},
              "host": {"path": str(args.host.resolve()), "sha256": sha256(args.host)}}
    if args.kagari_module:
        inputs["kagari"] = {"path": str(args.kagari_module.resolve()), "sha256": sha256(args.kagari_module)}
    if args.akari_module:
        inputs["akari"] = {"url": AKARI_URL, "archiveSHA256": AKARI_SHA256, "moduleSHA256": sha256(args.akari_module)}
    report = {"architecture": args.architecture, "sources": inputs, "passed": False, "temporaryCopiesRemoved": False,
              "manualUIVerified": False, "utataneRevision": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(),
              "utataneDirty": bool(subprocess.check_output(["git", "status", "--porcelain"], cwd=ROOT, text=True).strip())}
    try:
        with tempfile.TemporaryDirectory(prefix="utatane-plugin-corpus-") as temporary:
            root = Path(temporary)
            report["temporaryDirectory"] = str(root)
            # Force the helper to the requested CPU, rather than relying on universal
            # subprocess selection when tests run under Rosetta.
            host = root / "utatane-shiori-host"
            architectures = subprocess.check_output(["xcrun", "lipo", "-archs", str(args.host.resolve())], text=True).split()
            if args.architecture not in architectures:
                raise ValueError("The native helper does not contain the requested architecture")
            if len(architectures) == 1:
                import shutil
                shutil.copyfile(args.host, host)
            else:
                subprocess.run(["xcrun", "lipo", str(args.host.resolve()), "-thin", args.architecture, "-output", str(host)], check=True)
            host.chmod(0o755)
            subprocess.run(["codesign", "--force", "--sign", "-", str(host)], check=True)
            report["executedHostSHA256"] = sha256(host)
            balloon_nar = root / "balloon.nar"
            subprocess.run(["python3", str(port), "--source", str(source), "--output", str(balloon_nar)], check=True, timeout=60)
            balloon = root / "balloon"
            diary_root = root / "diary"
            extract(balloon_nar, balloon)
            extract(diary, diary_root)
            descriptors = list(diary_root.rglob("descript.txt"))
            if len(descriptors) != 1:
                raise ValueError("Expected exactly one DBdiary descriptor")
            environment = dict(os.environ)
            environment.update(UTATANE_BALLOONSELECTOR_PLUGIN=str(balloon), UTATANE_DBDIARY_PLUGIN=str(descriptors[0].parent),
                               UTATANE_YAYA_MODULE=str(args.yaya_module.resolve()), UTATANE_NATIVE_SHIORI_HOST=str(host))
            suites = ["BalloonSelectorIntegrationTests", "DBdiaryIntegrationTests"]
            if args.kagari_module:
                environment["UTATANE_KAGARI_MODULE"] = str(args.kagari_module.resolve())
                suites.append("KagariPluginNativeTests")
            if args.akari_module:
                akari = root / "akari"
                extract(args.akari_plugin_archive, akari)
                descriptors = list(akari.rglob("descript.txt"))
                if len(descriptors) != 1:
                    raise ValueError("Expected one AKARI plugin descriptor")
                environment.update(UTATANE_AKARI_PLUGIN=str(descriptors[0].parent), UTATANE_AKARI_MODULE=str(args.akari_module.resolve()))
                suites.append("AkariPluginImageIntegrationTests")
            result = subprocess.run(["/usr/bin/arch", "-" + args.architecture, "swift", "test", "--arch", args.architecture, "--package-path", str(ROOT / "packages"), "--filter", "|".join(suites)],
                                    cwd=ROOT, env=environment, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=900)
            report_path.with_suffix(".log").write_text(result.stdout)
            print(result.stdout, end="", flush=True)
            result.check_returncode()
            if not re.search(r"Test run with [1-9][0-9]* tests?.*passed", result.stdout) or any(f"Suite {suite} passed" not in result.stdout for suite in suites):
                raise ValueError("The requested real plugin suites did not run successfully")
            if tree_hash(source) != inputs["balloonselector"]["treeSHA256"] or sha256(diary) != DIARY_SHA256:
                raise ValueError("Original plugin data changed during validation")
            report["passed"] = True
            report["suites"] = suites
    except Exception as error:
        report["error"] = str(error)
        raise
    finally:
        report["temporaryCopiesRemoved"] = "temporaryDirectory" in report and not Path(report["temporaryDirectory"]).exists()
        report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
        print(f"Report: {report_path}")


if __name__ == "__main__":
    main()
