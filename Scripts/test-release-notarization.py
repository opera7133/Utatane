#!/usr/bin/env python3
"""Regression checks for persisted, delayed, and retried notarized releases."""

import argparse
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
import uuid

sys.dont_write_bytecode = True
SPEC = importlib.util.spec_from_file_location("notary_release", Path(__file__).with_name("release-notarization.py"))
M = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(M)


class NotarizationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.candidate = self.root / "candidate"
        self.candidate.mkdir()
        (self.candidate / "Utatane-submission.zip").write_bytes(b"signed original bytes")
        self.data = {"schemaVersion": 1, "tag": "v0.2.19", "commit": "a" * 40, "runId": 123,
                     "buildNumber": 201, "teamId": "TESTTEAM00", "sparklePublicKey": "test",
                     "archiveSHA256": M.digest(self.candidate / "Utatane-submission.zip")}
        M.seal(self.candidate, "candidate.json", self.data)
        self.source = {"id": 123, "head_sha": "a" * 40, "head_branch": "v0.2.19", "run_number": 201,
                       "event": "push", "status": "completed", "conclusion": "success",
                       "head_repository": {"full_name": "owner/repo"}, "path": ".github/workflows/build.yml"}
        self.receipt = self.root / "receipt"
        self.request = {key: self.data[key] for key in ("tag", "commit", "runId", "archiveSHA256")} | {"submissionId": str(uuid.uuid4())}
        M.write(self.receipt / "request.json", self.request)
        self.args = argparse.Namespace(directory=self.candidate, receipt=self.receipt, final=self.root / "final", profile="test", run_id=123)
        self.env = patch.dict(os.environ, {"GITHUB_REPOSITORY": "owner/repo", "GITHUB_RUN_ID": "123"})
        self.env.start()
        self.addCleanup(self.env.stop)

    def status(self, value):
        return {"id": self.request["submissionId"], "status": value, "createdDate": "2026-10-24T12:00:00Z"}

    def final(self):
        self.args.final.mkdir()
        (self.args.final / "Utatane-macOS.zip").write_bytes(b"stapled final bytes")
        (self.args.final / "update-feed").mkdir()
        (self.args.final / "update-feed/appcast.xml").write_text("feed")
        (self.args.final / "release-notes.md").write_text("maintainer notes")
        M.seal(self.args.final, "finalized.json", self.data | {"submissionId": self.request["submissionId"]})
        patcher = patch.dict(os.environ, {"VT_SHA256": M.digest(self.args.final / "Utatane-macOS.zip")})
        patcher.start()
        self.addCleanup(patcher.stop)

    def test_modified_signed_candidate_is_rejected(self):
        (self.candidate / "Utatane-submission.zip").write_bytes(b"rebuilt different bytes")
        with self.assertRaises(ValueError):
            M.verify(self.candidate, "candidate.json")

    def test_additional_manifest_named_file_cannot_escape_checksums(self):
        (self.candidate / "sub").mkdir()
        (self.candidate / "sub/candidate.json").write_text("unexpected")
        with self.assertRaises(ValueError):
            M.verify(self.candidate, "candidate.json")

    def test_receipt_for_different_bytes_is_rejected(self):
        with self.assertRaises(ValueError):
            M.bind(self.source, self.data, self.request | {"archiveSHA256": "f" * 64})

    def test_pull_request_source_cannot_use_publication_credentials(self):
        with patch.object(M.GitHub, "api", return_value=self.source | {"event": "pull_request"}) as api:
            with self.assertRaises(ValueError):
                M.GitHub().source(123)
        self.assertEqual(api.call_count, 1)

    def test_moved_tag_is_rejected(self):
        with patch.object(M.GitHub, "api", side_effect=[self.source, {"object": {"type": "commit", "sha": "b" * 40}}]):
            with self.assertRaises(ValueError):
                M.GitHub().source(123)

    def test_fork_source_is_rejected(self):
        source = self.source | {"head_repository": {"full_name": "attacker/repo"}}
        with patch.object(M.GitHub, "api", return_value=source):
            with self.assertRaises(ValueError):
                M.GitHub().source(123)

    def test_ordinary_build_completion_is_a_noop(self):
        with patch.dict(os.environ, {"SOURCE_RUN_ID": "123", "GITHUB_EVENT_NAME": "workflow_run"}), \
             patch.object(M.GitHub, "api", return_value=self.source | {"head_branch": "main"}), \
             patch.object(M, "output") as out, patch.object(M.GitHub, "source") as source:
            M.discover(self.args)
        out.assert_called_once_with("runs", "[]")
        source.assert_not_called()

    def test_pending_for_two_days_then_accepted_never_resubmits(self):
        statuses = iter(["In Progress", "In Progress", "Accepted"])
        with patch.object(M.GitHub, "source", return_value=self.source), patch.object(M, "output") as out:
            for _ in range(3):
                status = next(statuses)
                def execute(*command):
                    self.assertEqual(command[2], "info")
                    return json.dumps(self.status(status)).encode()
                def log(command, **kwargs):
                    self.assertEqual(command[2], "log")
                    M.write(Path(command[-1]), {"status": "Accepted", "issues": None})
                with patch.object(M, "run", side_effect=execute), patch.object(M.subprocess, "run", side_effect=log):
                    M.check(self.args)
        self.assertEqual([item.args for item in out.call_args_list], [("status", "pending"), ("status", "pending"), ("status", "accepted")])
        self.assertEqual((self.candidate / "Utatane-submission.zip").read_bytes(), b"signed original bytes")

    def test_pending_and_invalid_cannot_be_finalized(self):
        for value in ("In Progress", "Invalid"):
            with self.subTest(value=value):
                M.write(self.receipt / "status.json", self.status(value))
                with patch.object(M.GitHub, "source", return_value=self.source), patch.object(M.subprocess, "run") as command:
                    with self.assertRaises(ValueError):
                        M.finalize(self.args)
                command.assert_not_called()

    def test_existing_apple_submission_is_recovered_without_another_upload(self):
        # Models a runner dying after Apple accepted the upload but before receipt upload.
        name = f"Utatane-v0.2.19-run123-{self.data['archiveSHA256'][:16]}.zip"
        with patch.object(M.GitHub, "api", return_value={"artifacts": []}), \
             patch.object(M, "run", return_value=json.dumps({"history": [{"id": self.request["submissionId"], "name": name}]}).encode()) as command:
            M.submit(self.args)
        self.assertEqual(command.call_count, 1)
        self.assertEqual(command.call_args.args[2], "history")
        self.assertEqual(M.read(self.receipt / "request.json")["submissionId"], self.request["submissionId"])

    def test_only_terminal_apple_results_can_stop_scheduled_checks(self):
        M.write(self.receipt / "status.json", self.status("In Progress"))
        with self.assertRaises(ValueError):
            M.terminal(self.args)

    def test_reuses_stapled_zip_and_feed_after_interrupted_publication(self):
        self.final()
        cached = self.args.final.rename(self.root / "cached-final")
        M.write(self.receipt / "status.json", self.status("Accepted"))
        def download(artifact, destination):
            M.shutil.copytree(cached, destination)
        with patch.object(M.GitHub, "source", return_value=self.source), \
             patch.object(M.GitHub, "continuation_artifact", return_value={"id": 456}), \
             patch.object(M.GitHub, "download", side_effect=download), patch.object(M, "verify_feed"), \
             patch.object(M.subprocess, "run") as command, patch.object(M, "output") as out:
            M.finalize(self.args)
        command.assert_not_called()
        out.assert_called_once_with("reused", "true")
        self.assertEqual((self.args.final / "Utatane-macOS.zip").read_bytes(), b"stapled final bytes")

    def test_expired_original_receipt_cannot_trigger_implicit_resubmission(self):
        with patch.object(M.GitHub, "api", return_value={"artifacts": [{"name": M.REQUEST, "expired": True}]}):
            with self.assertRaises(ValueError):
                M.GitHub().source_artifact(123, M.REQUEST)

    def test_one_expired_candidate_does_not_block_other_pending_releases(self):
        newer = self.source | {"id": 124, "run_number": 202}
        def artifact(run_id, name):
            if run_id == 123 and name == M.CANDIDATE:
                raise ValueError("Candidate expired")
            return {"id": run_id}
        stamp = M.datetime.now(M.timezone.utc).isoformat()
        with patch.dict(os.environ, {"SOURCE_RUN_ID": "", "GITHUB_EVENT_NAME": "schedule"}), \
             patch.object(M.GitHub, "api", return_value={"workflow_runs": [self.source | {"created_at": stamp}, newer | {"created_at": stamp}]}), \
             patch.object(M.GitHub, "source", return_value=self.source), patch.object(M.GitHub, "source_artifact", side_effect=artifact), \
             patch.object(M.GitHub, "continuation_artifact", return_value=None), patch.object(M, "output") as out:
            M.discover(self.args)
        out.assert_called_once_with("runs", "[124]")

    def test_finalized_bytes_must_match_virus_total_report(self):
        self.final()
        with patch.dict(os.environ, {"VT_SHA256": "incorrect"}), patch.object(M.GitHub, "source", return_value=self.source), \
             patch.object(M, "verify_feed"), patch.object(M.subprocess, "run") as command:
            with self.assertRaises(ValueError):
                M.publish(self.args)
        command.assert_not_called()

    def test_older_release_does_not_promote_latest_or_update_feed(self):
        self.final()
        feed = f'<rss xmlns:sparkle="{M.SPARKLE[1:-1]}"><channel><item><sparkle:version>202</sparkle:version></item></channel></rss>'.encode()
        calls = []
        def command(args, **kwargs):
            calls.append(args)
            return subprocess.CompletedProcess(args, 0, json.dumps({"assets": [], "isDraft": False}), "")
        with patch.object(M.GitHub, "source", return_value=self.source), patch.object(M, "verify_feed"), \
             patch.object(M, "production_feed", return_value=feed), patch.object(M.subprocess, "run", side_effect=command), patch.object(M, "output") as out:
            M.publish(self.args)
        out.assert_called_once_with("promote", "false")
        self.assertFalse(any("edit" in item for item in calls))

    def test_existing_published_bytes_are_never_clobbered(self):
        self.final()
        feed = f'<rss xmlns:sparkle="{M.SPARKLE[1:-1]}"><channel><item><sparkle:version>200</sparkle:version></item></channel></rss>'.encode()
        def command(args, **kwargs):
            if "view" in args:
                return subprocess.CompletedProcess(args, 0, json.dumps({"assets": [{"name": "Utatane-macOS.zip"}], "isDraft": False}), "")
            if "download" in args:
                Path(args[-1], "Utatane-macOS.zip").write_bytes(b"different published content")
                return subprocess.CompletedProcess(args, 0)
            self.fail("Must not upload or replace an asset when its bytes differ")
        with patch.object(M.GitHub, "source", return_value=self.source), patch.object(M, "verify_feed"), \
             patch.object(M, "production_feed", return_value=feed), patch.object(M.subprocess, "run", side_effect=command):
            with self.assertRaises(ValueError):
                M.publish(self.args)

    def test_invalid_production_feed_fails_closed(self):
        for contents in (b"not XML", b"<rss><channel/></rss>"):
            with self.assertRaises((ValueError, M.ET.ParseError)):
                M.feed_build(contents)

    def image(self):
        self.data["releaseArchive"] = "Utatane-macOS.dmg"
        M.seal(self.candidate, "candidate.json", self.data)
        M.write(self.receipt / "status.json", self.status("Accepted"))
        self.args.image = self.root / "image"
        self.args.image_receipt = self.root / "image-receipt"
        self.args.image.mkdir()
        (self.args.image / "Utatane-macOS.dmg").write_bytes(b"signed image with stapled app")
        self.image_data = self.data | {"appSubmissionId": self.request["submissionId"],
            "imageSHA256": M.digest(self.args.image / "Utatane-macOS.dmg")}
        M.seal(self.args.image, "image.json", self.image_data)
        self.image_request = {key: self.image_data[key] for key in ("tag", "commit", "runId", "imageSHA256")} | {"submissionId": str(uuid.uuid4())}
        M.write(self.args.image_receipt / "request.json", self.image_request)

    def test_legacy_zip_candidate_skips_second_notarization(self):
        M.write(self.receipt / "status.json", self.status("Accepted"))
        with patch.object(M.GitHub, "source", return_value=self.source), patch.object(M, "output") as out, \
             patch.object(M.subprocess, "run") as command:
            M.package_image(self.args)
        out.assert_called_once_with("enabled", "false")
        command.assert_not_called()

    def test_image_cannot_belong_to_another_app_submission(self):
        self.image()
        M.seal(self.args.image, "image.json", self.image_data | {"appSubmissionId": str(uuid.uuid4())})
        with self.assertRaises(ValueError):
            M.load_image(self.args, self.data, self.request)

    def test_modified_signed_image_is_rejected(self):
        self.image()
        (self.args.image / "Utatane-macOS.dmg").write_bytes(b"replacement image")
        with self.assertRaises(ValueError):
            M.load_image(self.args, self.data, self.request)

    def test_image_receipt_is_bound_to_exact_image_bytes(self):
        self.image()
        M.write(self.args.image_receipt / "request.json", self.image_request | {"imageSHA256": "f" * 64})
        with self.assertRaises(ValueError):
            M.load_image(self.args, self.data, self.request)

    def test_pending_or_rejected_image_cannot_publish_even_when_app_is_accepted(self):
        self.image()
        for status in ("In Progress", "Rejected"):
            M.write(self.args.image_receipt / "status.json", {"id": self.image_request["submissionId"], "status": status})
            with patch.object(M.GitHub, "source", return_value=self.source), patch.object(M.subprocess, "run") as command:
                with self.assertRaises(ValueError):
                    M.finalize(self.args)
            command.assert_not_called()

    def test_signed_image_is_recovered_without_repackaging_or_resigning(self):
        self.image()
        cached = self.args.image.rename(self.root / "cached-image")
        def download(artifact, destination):
            M.shutil.copytree(cached, destination)
        with patch.object(M.GitHub, "source", return_value=self.source), \
             patch.object(M.GitHub, "continuation_artifact", return_value={"id": 456}), \
             patch.object(M.GitHub, "download", side_effect=download), patch.object(M.subprocess, "run") as command:
            M.package_image(self.args)
        command.assert_not_called()
        self.assertEqual((self.args.image / "Utatane-macOS.dmg").read_bytes(), b"signed image with stapled app")

    def test_missing_submitted_image_cannot_be_rebuilt(self):
        self.image()
        with patch.object(M.GitHub, "source", return_value=self.source), \
             patch.object(M.GitHub, "continuation_artifact", side_effect=[None, {"id": 456}]), \
             patch.object(M.subprocess, "run") as command:
            with self.assertRaises(ValueError):
                M.package_image(self.args)
        command.assert_not_called()

    def test_image_pending_for_days_never_uploads_or_resigns_again(self):
        self.image()
        cached = self.args.image_receipt.rename(self.root / "cached-image-receipt")
        def download(artifact, destination):
            M.shutil.copytree(cached, destination)
        with patch.object(M.GitHub, "source", return_value=self.source), \
             patch.object(M.GitHub, "continuation_artifact", return_value={"id": 456}), \
             patch.object(M.GitHub, "download", side_effect=download), patch.object(M, "output") as out:
            for status in ("In Progress", "In Progress", "Accepted"):
                if self.args.image_receipt.exists():
                    M.shutil.rmtree(self.args.image_receipt)
                def command(*args):
                    self.assertEqual(args[2], "info")
                    return json.dumps({"id": self.image_request["submissionId"], "status": status}).encode()
                def log(command, **kwargs):
                    self.assertEqual(command[2], "log")
                    M.write(Path(command[-1]), {"status": status, "issues": None})
                with patch.object(M, "run", side_effect=command), patch.object(M.subprocess, "run", side_effect=log):
                    M.notarize_image(self.args)
        self.assertEqual([item.args[1] for item in out.call_args_list if item.args[0] == "status"], ["pending", "pending", "accepted"])

    def test_image_upload_crash_recovers_from_apple_history(self):
        self.image()
        name = f"Utatane-v0.2.19-run123-{self.image_data['imageSHA256'][:16]}.dmg"
        def command(*args):
            if args[2] == "history":
                return json.dumps({"history": [{"name": name, "id": self.image_request["submissionId"]}]}).encode()
            self.assertEqual(args[2], "info")
            return json.dumps({"id": self.image_request["submissionId"], "status": "In Progress"}).encode()
        with patch.object(M.GitHub, "source", return_value=self.source), \
             patch.object(M.GitHub, "continuation_artifact", return_value=None), patch.object(M, "run", side_effect=command):
            M.notarize_image(self.args)
        self.assertEqual(M.read(self.args.image_receipt / "request.json"), self.image_request)

    def test_finalized_dmg_is_recovered_without_restapling(self):
        self.image()
        M.write(self.args.image_receipt / "status.json", {"id": self.image_request["submissionId"], "status": "Accepted"})
        self.args.final.mkdir()
        (self.args.final / "Utatane-macOS.dmg").write_bytes(b"final stapled image")
        M.seal(self.args.final, "finalized.json", self.data | {"submissionId": self.request["submissionId"], "imageSubmissionId": self.image_request["submissionId"], "imageSHA256": self.image_request["imageSHA256"]})
        cached = self.args.final.rename(self.root / "cached-final-image")
        def download(artifact, destination):
            M.shutil.copytree(cached, destination)
        with patch.object(M.GitHub, "source", return_value=self.source), \
             patch.object(M.GitHub, "continuation_artifact", return_value={"id": 456}), \
             patch.object(M.GitHub, "download", side_effect=download), patch.object(M, "verify_feed"), patch.object(M.subprocess, "run") as command:
            M.finalize(self.args)
        command.assert_not_called()
        self.assertEqual((self.args.final / "Utatane-macOS.dmg").read_bytes(), b"final stapled image")

    def test_dmg_finalization_staples_same_image_and_signs_dmg_feed(self):
        self.image()
        M.write(self.args.image_receipt / "status.json", {"id": self.image_request["submissionId"], "status": "Accepted"})
        M.write(self.args.image_receipt / "notary-log.json", {"status": "Accepted"})
        M.write(self.receipt / "notary-log.json", {"status": "Accepted"})
        (self.candidate / "content").mkdir()
        (self.candidate / "release-notes.md").write_text("notes")
        (self.candidate / "generate_appcast").write_text("generator fixture")
        M.seal(self.candidate, "candidate.json", self.data)
        item = M.ET.fromstring(f'<item xmlns:sparkle="{M.SPARKLE[1:-1]}"><sparkle:version>201</sparkle:version><enclosure url="https://github.com/owner/repo/releases/download/v0.2.19/Utatane-macOS.dmg"/></item>')
        calls = []
        def command(args, **kwargs):
            calls.append(args)
            if "--ed-key-file" in args:
                (self.args.final / "update-feed/appcast.xml").write_text("signed feed")
        with patch.object(M.GitHub, "source", return_value=self.source), \
             patch.object(M.GitHub, "continuation_artifact", return_value=None), \
             patch.dict(os.environ, {"SPARKLE_PRIVATE_KEY": "isolated-test-key"}), \
             patch.object(M.subprocess, "run", side_effect=command), patch.object(M, "verify_feed", return_value=item):
            M.finalize(self.args)
        saved = M.verify(self.args.final, "finalized.json")
        self.assertEqual(saved["imageSubmissionId"], self.image_request["submissionId"])
        self.assertEqual(M.release_name(saved), "Utatane-macOS.dmg")
        self.assertEqual((self.args.final / "Utatane-macOS.dmg").read_bytes(), b"signed image with stapled app")
        self.assertFalse(any(args[0] in ("ditto", "uv") or "--sign" in args for args in calls))
        self.assertTrue(any(args[:3] == ["xcrun", "stapler", "staple"] for args in calls))

    def test_dmg_upload_receipt_survives_info_failure(self):
        self.image()
        def command(*args):
            if args[2] == "history":
                return b'{"history": []}'
            if args[2] == "submit":
                return json.dumps({"id": self.image_request["submissionId"]}).encode()
            raise subprocess.CalledProcessError(1, args)
        with patch.object(M.GitHub, "source", return_value=self.source), \
             patch.object(M.GitHub, "continuation_artifact", return_value=None), \
             patch.object(M, "run", side_effect=command), patch.object(M, "output") as out:
            with self.assertRaises(subprocess.CalledProcessError):
                M.notarize_image(self.args)
        self.assertEqual(M.read(self.args.image_receipt / "request.json"), self.image_request)
        out.assert_called_once_with("reused", "false")

    def test_pending_image_cannot_mark_accepted_app_terminal(self):
        self.image()
        M.write(self.args.image_receipt / "status.json", {"id": self.image_request["submissionId"], "status": "In Progress"})
        with self.assertRaises(ValueError):
            M.terminal(self.args)

    def test_unknown_archive_format_is_rejected(self):
        M.seal(self.candidate, "candidate.json", self.data | {"releaseArchive": "../../unexpected.dmg"})
        with self.assertRaises(ValueError):
            M.verify(self.candidate, "candidate.json")


if __name__ == "__main__":
    unittest.main()
