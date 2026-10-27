#!/usr/bin/env python3
"""Exercise actual DMG packaging with an isolated signed macOS app fixture."""
import importlib.util
import json
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile
import unittest

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("build_dmg", ROOT / "Scripts/build-dmg.py")
M = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(M)


class DiskImageTests(unittest.TestCase):
    def test_packaging_preserves_signature_layout_background_and_link(self):
        with tempfile.TemporaryDirectory(prefix="utatane-dmg-test-") as temporary:
            root = Path(temporary)
            app = root / "Utatane.app"
            executable = app / "Contents/MacOS/Utatane"
            executable.parent.mkdir(parents=True)
            (app / "Contents/Info.plist").write_bytes(plistlib.dumps({
                "CFBundleIdentifier": "dev.utatane.dmg-test", "CFBundleExecutable": "Utatane",
                "CFBundlePackageType": "APPL", "CFBundleShortVersionString": "0.0.1", "CFBundleVersion": "1",
            }))
            subprocess.run(["xcrun", "clang", "-x", "c", "-o", str(executable), "-"], input=b"int main(void) { return 0; }", check=True)
            subprocess.run(["codesign", "--sign", "-", str(app)], check=True)
            assets = root / "assets"
            subprocess.run([sys.executable, str(ROOT / "Scripts/export-dmg-assets.py"), "--output", str(assets)], check=True)
            image = root / "Utatane.dmg"
            subprocess.run([sys.executable, str(ROOT / "Scripts/build-dmg.py"), "--app", str(app),
                            "--assets", str(assets), "--output", str(image)], check=True)
            report = M.inspect(image, assets, app)
            self.assertEqual(report["version"], "0.0.1")
            self.assertEqual(report["iconPositions"], {"Utatane.app": (208, 256), "Applications": (560, 256)})
            self.assertEqual(report["windowSize"], {"width": 768, "height": 512})
            tiff = subprocess.check_output(["tiffutil", "-info", str(assets / "background.tiff")], stderr=subprocess.STDOUT, text=True)
            self.assertEqual(tiff.count("Directory at "), 2)
            self.assertIn("Image Width: 768 Image Length: 512", tiff)
            self.assertIn("Image Width: 1536 Image Length: 1024", tiff)
            self.assertIn("Resolution: 144, 144", tiff)
            layout = json.loads((assets / "layout.json").read_text())
            layout["iconSizeInPoints"] = 128
            (assets / "layout.json").write_text(json.dumps(layout))
            with self.assertRaises(ValueError):
                M.assets_at(assets)


if __name__ == "__main__":
    unittest.main()
