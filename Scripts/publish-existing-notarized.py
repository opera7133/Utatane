#!/usr/bin/env python3
"""Verify and announce a notarized addition to an already published release."""

import argparse
import importlib.util
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile
import uuid
import zipfile

sys.dont_write_bytecode = True
SPEC = importlib.util.spec_from_file_location("notary_release", Path(__file__).with_name("release-notarization.py"))
M = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(M)
ARCHIVE = "Utatane-macOS-notarized.zip"
FEED = "appcast-notarized.xml"


def validate_inputs(tag, sha256, submission):
    if not M.TAG.fullmatch(tag or "") or not re.fullmatch(r"[0-9a-f]{64}", sha256 or ""):
        raise ValueError("A release tag and exact ZIP SHA-256 are required")
    if str(uuid.UUID(submission)) != submission:
        raise ValueError("Expected a canonical notarization submission ID")


def validate_ticket(log, submission, tag, team, info, signatures):
    if (log["jobId"] != submission or log["status"] != "Accepted"
            or any(item.get("severity") == "error" for item in log.get("issues") or [])):
        raise ValueError("The existing submission was not accepted")
    if info["CFBundleShortVersionString"] != tag[1:]:
        raise ValueError("The notarized app belongs to a different release")
    for arch in ("arm64", "x86_64"):
        matches = [item for item in log["ticketContents"]
                   if item.get("arch") == arch and item["path"].endswith("/Utatane.app")]
        details = signatures[arch]
        if (len(matches) != 1 or "CDHash=" + matches[0]["cdhash"] + "\n" not in details
                or "TeamIdentifier=" + team + "\n" not in details or "runtime" not in details):
            raise ValueError("The app signature does not match Apple's accepted ticket")


def verified_files(root):
    record = M.read(root / "verification.json")
    if M.digest(root / ARCHIVE) != record["archiveSHA256"] or M.digest(root / FEED) != record["feedSHA256"]:
        raise ValueError("Verified publication files have changed")
    return record


def verify(args):
    validate_inputs(args.tag, args.sha256, args.submission_id)
    root = args.directory
    if M.digest(root / ARCHIVE) != args.sha256:
        raise ValueError("The public ZIP differs from the explicitly selected candidate")
    github = M.GitHub()
    release = github.api(f"releases/tags/{args.tag}")
    if release["draft"] or release["tag_name"] != args.tag:
        raise ValueError("Expected an existing published release")
    prefix = f"https://github.com/{github.repository}/releases/download/{args.tag}/"
    for name in (ARCHIVE, FEED):
        assets = [item for item in release["assets"] if item["name"] == name]
        if (len(assets) != 1 or assets[0]["browser_download_url"] != prefix + name
                or assets[0].get("digest") != "sha256:" + M.digest(root / name)):
            raise ValueError("Unexpected public release asset")
    # Inspect paths before passing a manually selected, checksummed ZIP to ditto.
    with zipfile.ZipFile(root / ARCHIVE) as archive:
        for entry in archive.infolist():
            path = M.PurePosixPath(entry.filename)
            if path.is_absolute() or ".." in path.parts or "\\" in entry.filename or path.parts[0] != "Utatane.app":
                raise ValueError("Unsafe app archive path")
    log_path = root / "notary-log.json"
    subprocess.run(["xcrun", "notarytool", "log", args.submission_id, *M.notary_auth(args.profile), str(log_path)], check=True)
    log = M.read(log_path)
    with tempfile.TemporaryDirectory(prefix="utatane-existing-notary-") as temporary:
        temp = Path(temporary)
        subprocess.run(["ditto", "-x", "-k", str(root / ARCHIVE), str(temp)], check=True)
        app = temp / "Utatane.app"
        info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
        signatures = {arch: subprocess.run(["codesign", "-dvvv", "--arch", arch, str(app)], check=True, capture_output=True, text=True).stderr for arch in ("arm64", "x86_64")}
        validate_ticket(log, args.submission_id, args.tag, os.environ["APPLE_TEAM_ID"], info, signatures)
        for command in (["codesign", "--verify", "--deep", "--strict"], ["xcrun", "stapler", "validate"], ["spctl", "--assess", "--type", "execute", "--verbose=2"]):
            subprocess.run([*command, str(app)], check=True)
        public = re.search(r'^\s+SUPublicEDKey:\s*"?([^"\s]+)', Path("project.yml").read_text(), re.M)[1]
        if info["SUPublicEDKey"] != public:
            raise ValueError("App Sparkle key differs from the configured distribution key")
        (temp / "update-feed").mkdir()
        shutil.copyfile(root / ARCHIVE, temp / "Utatane-macOS.zip")
        shutil.copyfile(root / FEED, temp / "update-feed/appcast.xml")
        item = M.verify_feed(temp, public)
        build = int(info["CFBundleVersion"])
        if (item.find(M.SPARKLE + "version").text != str(build)
                or item.find(M.SPARKLE + "shortVersionString").text != args.tag[1:]
                or item.find("enclosure").attrib["url"] != prefix + ARCHIVE):
            raise ValueError("Signed update feed differs from the selected app")
        if M.feed_build(M.production_feed()) > build:
            raise ValueError("A newer release is already in production; refusing a feed rollback")
    M.write(root / "verification.json", {"tag": args.tag, "submissionId": args.submission_id,
            "buildNumber": build, "archiveSHA256": args.sha256, "feedSHA256": M.digest(root / FEED)})
    M.summary(f"Verified notarized addition to {args.tag}, build {build}, Apple submission {args.submission_id}.")


def release_notes(body, tag, repository, status, sha256, report):
    notice = ("<!-- notarized-distribution -->\n"
              f"Developer ID署名・公証済みの[配布ファイル](https://github.com/{repository}/releases/download/{tag}/{ARCHIVE})を追加しました。"
              f"機能・バージョンは従来の{tag[1:]}と同じです。\n<!-- /notarized-distribution -->\n\n")
    body = re.sub(r"<!-- notarized-distribution -->.*?<!-- /notarized-distribution -->\s*", "", body, flags=re.S)
    scan = (f"### 🛡️ VirusTotal Scan\n- **File:** `{ARCHIVE}`\n- **Status:** {status}\n"
            f"- **SHA-256:** `{sha256}`\n- **Report:** {report}\n")
    pattern = r"^### 🛡️ VirusTotal Scan\n.*?(?=^### |\Z)"
    if re.search(pattern, body, re.M | re.S):
        body = re.sub(pattern, lambda _: scan, body, flags=re.M | re.S)
    else:
        body = body.rstrip() + "\n\n" + scan
    return notice + body


def announce(args):
    record = verified_files(args.directory)
    if os.environ["VT_SHA256"] != record["archiveSHA256"]:
        raise ValueError("VirusTotal result belongs to another archive")
    github = M.GitHub()
    release = github.api(f"releases/tags/{record['tag']}")
    body = release_notes(release["body"] or "", record["tag"], github.repository,
                         os.environ["VT_STATUS"], os.environ["VT_SHA256"], os.environ["VT_URL"])
    with tempfile.NamedTemporaryFile(mode="w", suffix=".md") as stream:
        stream.write(body)
        stream.flush()
        subprocess.run(["gh", "release", "edit", record["tag"], "--repo", github.repository, "--notes-file", stream.name], check=True)
    labels = {ARCHIVE: "macOS（Developer ID署名・公証済み、Apple Silicon / Intel）",
              FEED: "公証済みZIP用Sparkleフィード", "Utatane-macOS.zip": "旧配布物（未公証）",
              "appcast.xml": "旧ZIP用Sparkleフィード"}
    for asset in release["assets"]:
        if asset["name"] in labels:
            subprocess.run(["gh", "api", "--method", "PATCH", f"repos/{github.repository}/releases/assets/{int(asset['id'])}",
                            "-f", "label=" + labels[asset["name"]]], check=True, stdout=subprocess.DEVNULL)


def verify_published(args):
    record = verified_files(args.directory)
    if M.production_feed() != (args.directory / FEED).read_bytes():
        raise ValueError("Production feed does not match the verified notarized addition")
    M.summary(f"{record['tag']} notarized download and signed production feed are published.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("verify", "announce", "verify-published"))
    parser.add_argument("--directory", type=Path, default=Path("dist/existing-notarized"))
    parser.add_argument("--tag")
    parser.add_argument("--sha256")
    parser.add_argument("--submission-id")
    parser.add_argument("--profile", default="utatane-ci")
    args = parser.parse_args()
    {"verify": verify, "announce": announce, "verify-published": verify_published}[args.command](args)


if __name__ == "__main__":
    main()
