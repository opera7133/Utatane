#!/usr/bin/env python3
"""Sign an assembled Utatane.app from the inside out with Developer ID."""

import argparse
from pathlib import Path
import plistlib
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
MACHO = {bytes.fromhex(value) for value in (
    "cffaedfe", "feedfacf", "cefaedfe", "feedface",
    "cafebabe", "bebafeca", "cafebabf", "bfbafeca",
)}
SPECIAL = {
    "Contents/Helpers/utatane-shiori-host": ("dev.utatane.shiori-host", "SHIORIHost.entitlements"),
    "Contents/Helpers/utatane-mcp": ("dev.utatane.mcp", None),
    "Contents/Frameworks/libnicxlive.dylib": ("dev.utatane.nicxlive", None),
    "Contents/Frameworks/Sparkle.framework/Versions/B/Autoupdate": ("org.sparkle-project.Sparkle.Autoupdate", None),
}


def bundle_info(path):
    for relative in ("Contents/Info.plist", "Resources/Info.plist", "Info.plist"):
        candidate = path / relative
        if candidate.is_file():
            return plistlib.loads(candidate.read_bytes())
    return None


def signing_plan(app):
    info = bundle_info(app)
    if not info or info.get("CFBundleIdentifier") != "dev.utatane.app":
        raise ValueError("Expected an assembled Utatane.app")
    bundles = {app: info}
    binaries = []
    for path in app.rglob("*"):
        if path.is_symlink():
            continue
        if path.is_dir() and path.suffix in (".app", ".xpc", ".framework", ".bundle"):
            nested = bundle_info(path)
            if nested and nested.get("CFBundleExecutable"):
                bundles[path] = nested
        elif path.is_file():
            with path.open("rb") as stream:
                if stream.read(4) in MACHO:
                    binaries.append(path)
    if not (app / "Contents/Helpers/utatane-shiori-host").is_file():
        raise ValueError("Missing native SHIORI host")
    plan = []
    for path in set(binaries) | set(bundles):
        if not path.resolve().is_relative_to(app):
            raise ValueError(f"Code escapes app bundle: {path}")
        relative = path.relative_to(app).as_posix()
        entitlement = None
        if path == app:
            identifier, entitlement = "dev.utatane.app", "Utatane.entitlements"
        elif path in bundles:
            identifier = bundles[path]["CFBundleIdentifier"]
            if identifier == "org.sparkle-project.DownloaderService":
                entitlement = "SparkleDownloader.entitlements"
        elif relative in SPECIAL:
            identifier, entitlement = SPECIAL[relative]
        else:
            owner = next((parent for parent in path.parents if parent in bundles), None)
            if owner is None or path.name != bundles[owner]["CFBundleExecutable"]:
                raise ValueError(f"Unknown embedded code; add an explicit signing rule: {relative}")
            identifier = bundles[owner]["CFBundleIdentifier"]
        plan.append((path, identifier, entitlement))
    return sorted(plan, key=lambda item: (-len(item[0].parts), str(item[0])))


def existing_entitlements(path):
    result = subprocess.run(["codesign", "-d", "--entitlements", "-", "--xml", str(path)], capture_output=True, check=True)
    data = result.stdout
    if not data.strip():
        return {}
    return plistlib.loads(data)


def developer_id_identity(value):
    output = subprocess.check_output(["security", "find-identity", "-v", "-p", "codesigning"], text=True)
    for digest, name in re.findall(r'([0-9A-F]{40}) "(Developer ID Application: [^\"]+)"', output):
        if value.upper() == digest or value == name:
            return digest
    raise ValueError("No matching valid Developer ID Application identity in the keychain")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", type=Path)
    parser.add_argument("--identity", required=True, help="Developer ID Application name or SHA-1 fingerprint")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()
    app = args.app.resolve()
    plan = signing_plan(app)
    identity = args.identity if args.dry_run else developer_id_identity(args.identity)
    with tempfile.TemporaryDirectory(prefix="utatane-sign-") as temporary:
        for index, (path, identifier, entitlement) in enumerate(plan):
            print(f"Sign {path.relative_to(app)} as {identifier}" + (f" ({entitlement})" if entitlement else ""), flush=True)
            if args.dry_run:
                continue
            values = existing_entitlements(path)
            had_entitlements = bool(values)
            values.pop("com.apple.security.get-task-allow", None)
            if entitlement:
                values.update(plistlib.loads((ROOT / "Scripts/Signing" / entitlement).read_bytes()))
            command = ["codesign", "--force", "--sign", identity, "--timestamp", "--options", "runtime", "--identifier", identifier]
            if values or had_entitlements:
                entitlements = Path(temporary) / f"{index}.plist"
                entitlements.write_bytes(plistlib.dumps(values))
                command.extend(["--entitlements", str(entitlements), "--generate-entitlement-der"])
            command.append(str(path))
            subprocess.run(command, check=True)
    if not args.dry_run:
        subprocess.run(["codesign", "--verify", "--deep", "--strict", "--verbose=2", str(app)], check=True)


if __name__ == "__main__":
    main()
