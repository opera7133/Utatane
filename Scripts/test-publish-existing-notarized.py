#!/usr/bin/env python3
"""Regression checks for a manually notarized addition to an existing release."""

import copy
import importlib.util
from pathlib import Path
import sys
import tempfile
import unittest

sys.dont_write_bytecode = True
SPEC = importlib.util.spec_from_file_location("existing_notary", Path(__file__).with_name("publish-existing-notarized.py"))
M = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(M)


class ExistingNotarizationTests(unittest.TestCase):
    def setUp(self):
        self.submission = "c3759bcd-31b9-4070-a108-1a9138c8efc4"
        self.info = {"CFBundleShortVersionString": "0.2.18"}
        self.log = {"jobId": self.submission, "status": "Accepted", "issues": None,
                    "ticketContents": [{"path": "submission.zip/Utatane.app", "arch": arch, "cdhash": arch + "digest"} for arch in ("arm64", "x86_64")]}
        self.signatures = {arch: f"CDHash={arch}digest\nTeamIdentifier=TESTTEAM00\nflags=0x10000(runtime)\n" for arch in ("arm64", "x86_64")}

    def validate(self, log=None, info=None, signatures=None):
        M.validate_ticket(self.log if log is None else log, self.submission, "v0.2.18", "TESTTEAM00",
                          self.info if info is None else info, self.signatures if signatures is None else signatures)

    def test_explicit_inputs_are_required_before_credentials(self):
        M.validate_inputs("v0.2.18", "a" * 64, self.submission)
        for tag, sha, submission in (("main", "a" * 64, self.submission), ("v0.2.18", "a" * 63, self.submission),
                                     ("v0.2.18; echo x", "a" * 64, self.submission), ("v0.2.18", "a" * 64, "other")):
            with self.assertRaises(ValueError):
                M.validate_inputs(tag, sha, submission)

    def test_both_cpu_slices_match_the_accepted_ticket(self):
        self.validate()
        log = copy.deepcopy(self.log)
        log["ticketContents"][1]["cdhash"] = "another-app"
        with self.assertRaises(ValueError):
            self.validate(log=log)

    def test_pending_rejected_or_unrelated_submission_cannot_publish(self):
        for changes in ({"status": "In Progress"}, {"status": "Invalid"}, {"jobId": "different"},
                        {"issues": [{"severity": "error"}]}):
            with self.assertRaises(ValueError):
                self.validate(log=self.log | changes)

    def test_wrong_team_missing_hardened_runtime_or_version_cannot_publish(self):
        for text in (self.signatures["arm64"].replace("TESTTEAM00", "WRONGTEAM0"),
                     self.signatures["arm64"].replace("runtime", "other")):
            with self.assertRaises(ValueError):
                self.validate(signatures=self.signatures | {"arm64": text})
        with self.assertRaises(ValueError):
            self.validate(info={"CFBundleShortVersionString": "0.2.19"})

    def test_file_changes_after_verification_cannot_be_announced(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / M.ARCHIVE).write_bytes(b"verified zip")
            (root / M.FEED).write_bytes(b"signed feed")
            M.M.write(root / "verification.json", {"archiveSHA256": M.M.digest(root / M.ARCHIVE), "feedSHA256": M.M.digest(root / M.FEED)})
            M.verified_files(root)
            (root / M.FEED).write_bytes(b"different feed")
            with self.assertRaises(ValueError):
                M.verified_files(root)

    def test_note_retry_preserves_maintainer_edits_and_replaces_only_scan(self):
        original = "Maintainer edits\n\n### 描画\nUser wording\n\n### 🛡️ VirusTotal Scan\nold checksum\n\n### Extra\nKeep this too\n"
        result = M.release_notes(original, "v0.2.18", "owner/repo", "Flagged (2 / 67)", "a" * 64, "https://example.com/report")
        self.assertIn("Maintainer edits", result)
        self.assertIn("User wording", result)
        self.assertIn("### Extra\nKeep this too", result)
        self.assertNotIn("old checksum", result)
        self.assertIn(M.ARCHIVE, result)
        self.assertEqual(M.release_notes(result, "v0.2.18", "owner/repo", "Flagged (2 / 67)", "a" * 64, "https://example.com/report"), result)


if __name__ == "__main__":
    unittest.main()
