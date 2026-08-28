#!/usr/bin/env python3
"""Offline regression checks for dependency verification and source extraction."""

import importlib.util
import io
from pathlib import Path
import tarfile
import tempfile
import unittest
import sys

sys.dont_write_bytecode = True
SPEC = importlib.util.spec_from_file_location("bundle_kagari", Path(__file__).with_name("bundle-kagari.py"))
BUILDER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(BUILDER)


class DependencyTests(unittest.TestCase):
    def test_cached_download_must_match_pinned_hash(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            archive = directory / "source.tar.gz"
            archive.write_bytes(b"original")
            dependency = {"archive": archive.name, "sha256": BUILDER.digest(archive)}
            self.assertEqual(BUILDER.verified_archive(dependency, directory), archive)
            archive.write_bytes(b"modified")
            with self.assertRaisesRegex(ValueError, "SHA-256 mismatch"):
                BUILDER.verified_archive(dependency, directory)

    def test_extraction_rejects_traversal_and_links(self):
        for name, kind in (("../escape", tarfile.REGTYPE), ("/absolute", tarfile.REGTYPE),
                           ("link", tarfile.SYMTYPE), ("link", tarfile.LNKTYPE)):
            with self.subTest(name=name, kind=kind), tempfile.TemporaryDirectory() as temporary:
                directory = Path(temporary)
                archive = directory / "source.tar.gz"
                with tarfile.open(archive, "w:gz") as target:
                    entry = tarfile.TarInfo(name)
                    entry.type = kind
                    entry.linkname = "outside"
                    target.addfile(entry)
                with self.assertRaisesRegex(ValueError, "Unsafe source archive"):
                    BUILDER.extract_sources(archive, directory / "extracted")

    def test_extraction_keeps_source_and_license_bytes(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            archive = directory / "source.tar.gz"
            data = b"Copyright\r\nPermission is hereby granted\r\n"
            with tarfile.open(archive, "w:gz") as target:
                entry = tarfile.TarInfo("package/LICENSE")
                entry.size = len(data)
                target.addfile(entry, io.BytesIO(data))
            BUILDER.extract_sources(archive, directory / "extracted")
            self.assertEqual((directory / "extracted/package/LICENSE").read_bytes(), data)


if __name__ == "__main__":
    unittest.main()
