#!/usr/bin/env python3
"""Build and inspect a Finder-independent, Retina-ready drag-install disk image.

Run with: uv run --project Scripts/dmg --locked python Scripts/build-dmg.py ...
"""
import argparse
from contextlib import contextmanager
import hashlib
import json
import os
from pathlib import Path
import plistlib
import subprocess
import tempfile

from dmgbuild import build_dmg
from ds_store import DSStore
from mac_alias import Alias


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def assets_at(root):
    manifest = json.loads((root / "manifest.json").read_text())
    layout = json.loads((root / "layout.json").read_text())
    if manifest["schemaVersion"] != 1 or layout != manifest["layout"] or layout["coordinateOrigin"] != "top-left":
        raise ValueError("Unsupported or altered DMG layout")
    for name, checksum in manifest["files"].items():
        if Path(name).name != name or digest(root / name) != checksum:
            raise ValueError("DMG asset differs from its export manifest")
    if layout["backgroundFilename"] not in manifest["files"]:
        raise ValueError("Background is missing from the asset manifest")
    return layout


@contextmanager
def mounted(image):
    with tempfile.TemporaryDirectory(prefix="utatane-image-") as temporary:
        mount = Path(temporary) / "volume"
        subprocess.run(["hdiutil", "attach", "-readonly", "-nobrowse", "-noautoopen", "-mountpoint", str(mount), str(image)],
                       check=True, stdout=subprocess.DEVNULL)
        try:
            yield mount
        finally:
            subprocess.run(["hdiutil", "detach", str(mount)], check=True, stdout=subprocess.DEVNULL)


def inspect(image, assets, app=None, require_ticket=False):
    layout = assets_at(assets)
    subprocess.run(["hdiutil", "verify", str(image)], check=True, stdout=subprocess.DEVNULL)
    with mounted(image) as volume:
        visible = {p.name for p in volume.iterdir() if not p.name.startswith(".")}
        if visible != {"Utatane.app", "Applications"} or os.readlink(volume / "Applications") != "/Applications":
            raise ValueError("Unexpected installer contents or Applications shortcut")
        background = volume / ".background.tiff"
        if digest(background) != digest(assets / layout["backgroundFilename"]):
            raise ValueError("Installed background differs from exported TIFF")
        with DSStore.open(str(volume / ".DS_Store"), "r") as store:
            if store["."]["icvl"] != (b"type", b"icnv"):
                raise ValueError("Finder must open the installer in icon view")
            window = store["."]["bwsp"]
            icons = store["."]["icvp"]
            size = layout["windowContentSizeInPoints"]
            expected_bounds = "{{100, 100}, {%d, %d}}" % (size["width"], size["height"])
            if window["WindowBounds"] != expected_bounds or any(window[key] for key in
                    ("ShowToolbar", "ShowSidebar", "ShowStatusBar", "ShowPathbar", "ShowTabView")):
                raise ValueError("Finder window settings differ from the layout")
            if icons["iconSize"] != layout["iconSizeInPoints"] or icons["arrangeBy"] != "none" or icons["backgroundType"] != 2:
                raise ValueError("Unexpected Finder icon/background settings")
            if Alias.from_bytes(icons["backgroundImageAlias"]).target.filename != ".background.tiff":
                raise ValueError("Finder background alias does not point inside the image")
            positions = {}
            for name, key in (("Utatane.app", "application"), ("Applications", "applicationsShortcut")):
                center = layout["iconCentersInPoints"][key]
                positions[name] = store[name]["Iloc"]
                if tuple(positions[name]) != (center["x"], center["y"]):
                    raise ValueError("Finder icon positions differ from the layout")
        embedded = volume / "Utatane.app"
        subprocess.run(["codesign", "--verify", "--deep", "--strict", str(embedded)], check=True)
        info = plistlib.loads((embedded / "Contents/Info.plist").read_bytes())
        if app is not None:
            original = plistlib.loads((app / "Contents/Info.plist").read_bytes())
            if original != info:
                raise ValueError("App metadata changed while packaging")
            # Tickets live outside the sealed resources; verify their preservation separately.
            for relative in ("Contents/CodeResources", "Contents/_CodeSignature/CodeResources"):
                before, after = app / relative, embedded / relative
                if before.is_file() and (not after.is_file() or digest(before) != digest(after)):
                    raise ValueError("App signature or stapled ticket changed while packaging")
        if require_ticket:
            subprocess.run(["xcrun", "stapler", "validate", str(embedded)], check=True)
        return {"version": info["CFBundleShortVersionString"], "buildNumber": info["CFBundleVersion"],
                "windowSize": size, "iconPositions": positions, "backgroundSHA256": digest(background)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", type=Path)
    parser.add_argument("--assets", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--verify-only", action="store_true")
    parser.add_argument("--require-app-ticket", action="store_true")
    args = parser.parse_args()
    if not args.verify_only:
        if not args.app or args.app.name != "Utatane.app" or not args.app.is_dir():
            parser.error("--app must point to Utatane.app")
        if args.output.exists():
            parser.error("Refusing to replace an existing disk image")
        layout = assets_at(args.assets)
        size = layout["windowContentSizeInPoints"]
        centers = layout["iconCentersInPoints"]
        args.output.parent.mkdir(parents=True, exist_ok=True)
        build_dmg(str(args.output.resolve()), "Utatane", settings={
            "format": "UDZO", "filesystem": "HFS+", "files": [str(args.app.resolve())],
            "symlinks": {"Applications": "/Applications"},
            "background": str((args.assets / layout["backgroundFilename"]).resolve()),
            "window_rect": ((100, 100), (size["width"], size["height"])),
            "icon_locations": {name: (centers[key]["x"], centers[key]["y"]) for name, key in
                               (("Utatane.app", "application"), ("Applications", "applicationsShortcut"))},
            "icon_size": layout["iconSizeInPoints"], "text_size": 14, "arrange_by": None,
            "show_status_bar": False, "show_tab_view": False, "show_toolbar": False,
            "show_pathbar": False, "show_sidebar": False, "default_view": "icon-view",
            "include_icon_view_settings": True, "include_list_view_settings": False,
        }, lookForHiDPI=False)
    report = inspect(args.output, args.assets, args.app, args.require_app_ticket)
    print(json.dumps(report, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
