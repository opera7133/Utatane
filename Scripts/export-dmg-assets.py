#!/usr/bin/env python3
"""Export the editable DMG SVG to 1x/2x PNG and a multi-resolution TIFF."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import struct
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
DESIGN = ROOT / "Design/DMG"


def run(*command):
    subprocess.run([str(value) for value in command], check=True, stdout=subprocess.DEVNULL)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=ROOT / "build/dmg-assets")
    args = parser.parse_args()
    if sys.platform != "darwin":
        parser.error("The TIFF export uses macOS sips and tiffutil.")
    renderer = shutil.which("rsvg-convert")
    if renderer is None:
        parser.error("rsvg-convert is required. Install it with: brew install librsvg")
    layout = json.loads((DESIGN / "layout.json").read_text())
    if layout.get("schemaVersion") != 1:
        parser.error("Unsupported layout schema version.")
    filename = layout["backgroundFilename"]
    if Path(filename).name != filename or Path(filename).suffix != ".tiff":
        parser.error("Background filename must be a TIFF basename.")
    source = DESIGN / layout["backgroundSource"]
    width = layout["windowContentSizeInPoints"]["width"]
    height = layout["windowContentSizeInPoints"]["height"]
    if not all(type(value) is int and 1 <= value <= 4096 for value in (width, height)):
        parser.error("Window dimensions must be integer points between 1 and 4096.")
    svg = ET.parse(source).getroot()
    if svg.tag != "{http://www.w3.org/2000/svg}svg" or svg.get("viewBox") != f"0 0 {width} {height}":
        parser.error("SVG viewBox must match layout.json window dimensions.")
    destination = args.output.resolve()
    destination.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="utatane-dmg-assets-") as temporary:
        stage = Path(temporary)
        representations = stage / "representations"
        representations.mkdir()
        tiffs = []
        for scale, suffix in [(1, ""), (2, "@2x")]:
            png = stage / f"background{suffix}.png"
            run(renderer, "--format", "png", "--width", width * scale, "--height", height * scale,
                "--output", png, source)
            # NSImage uses 72 points/inch. Both pixel representations must have
            # the same logical size, rather than making Retina artwork twice as large.
            run("/usr/bin/sips", "-s", "dpiWidth", 72 * scale, "-s", "dpiHeight", 72 * scale, png)
            with png.open("rb") as stream:
                header = stream.read(24)
            if header[:8] != b"\x89PNG\r\n\x1a\n" or struct.unpack(">II", header[16:24]) != (width * scale, height * scale):
                raise ValueError("Rendered PNG dimensions differ from the layout")
            tiff = representations / f"background{suffix}.tiff"
            run("/usr/bin/sips", "-s", "format", "tiff", png, "--out", tiff)
            tiffs.append(tiff)
        run("/usr/bin/tiffutil", "-cathidpicheck", *tiffs, "-out", stage / layout["backgroundFilename"])
        outputs = ["background.png", "background@2x.png", layout["backgroundFilename"]]
        manifest = {
            "schemaVersion": 1,
            "source": str(source.relative_to(ROOT)),
            "sourceSHA256": hashlib.sha256(source.read_bytes()).hexdigest(),
            "renderer": subprocess.check_output([renderer, "--version"], text=True).splitlines()[0],
            "layout": layout,
            "files": {name: hashlib.sha256((stage / name).read_bytes()).hexdigest() for name in outputs},
        }
        for name in outputs:
            shutil.copyfile(stage / name, destination / name)
        (destination / "layout.json").write_text(json.dumps(layout, ensure_ascii=False, indent=2) + "\n")
        (destination / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n")
    print(f"Exported {width}x{height} / {width * 2}x{height * 2} PNGs and Retina TIFF to {destination}")


if __name__ == "__main__":
    main()
