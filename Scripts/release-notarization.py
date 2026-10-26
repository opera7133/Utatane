#!/usr/bin/env python3
"""Persist notarization requests and resume publication without rebuilding."""

import argparse
import base64
from datetime import datetime, timedelta, timezone
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import plistlib
import re
import shutil
import stat
import subprocess
import tempfile
import uuid
from urllib.request import Request, urlopen
import xml.etree.ElementTree as ET
import zipfile

TAG = re.compile(r"v\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?")
REQUEST = "Utatane-notary-request"
CANDIDATE = "Utatane-notary-candidate"
SPARKLE = "{http://www.andymatuschak.org/xml-namespaces/sparkle}"


def run(*args, **kwargs):
    return subprocess.check_output(list(map(str, args)), **kwargs)


def notary_auth(profile):
    result = ["--keychain-profile", profile]
    if os.environ.get("UTATANE_SIGNING_KEYCHAIN"):
        result += ["--keychain", os.environ["UTATANE_SIGNING_KEYCHAIN"]]
    return result


def digest(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def read(path):
    return json.loads(path.read_text())


def write(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n")


def output(key, value):
    if "GITHUB_OUTPUT" in os.environ:
        with open(os.environ["GITHUB_OUTPUT"], "a") as stream:
            stream.write(f"{key}={value}\n")


def summary(value):
    print(value, flush=True)
    if "GITHUB_STEP_SUMMARY" in os.environ:
        with open(os.environ["GITHUB_STEP_SUMMARY"], "a") as stream:
            stream.write(value + "\n")


def inventory(root, exclude):
    result = {}
    for path in root.rglob("*"):
        if path.is_symlink():
            raise ValueError("Unexpected link in release state")
        if path.is_file() and path != root / exclude:
            result[path.relative_to(root).as_posix()] = digest(path)
    return result


def seal(root, name, data):
    write(root / name, {**data, "files": inventory(root, name)})


def verify(root, name):
    data = read(root / name)
    if data["schemaVersion"] != 1 or data["files"] != inventory(root, name):
        raise ValueError("Release state differs from its checksum manifest")
    if not TAG.fullmatch(data["tag"]) or not re.fullmatch(r"[0-9a-f]{40}", data["commit"]):
        raise ValueError("Invalid release identity")
    if not isinstance(data["runId"], int) or data["runId"] <= 0:
        raise ValueError("Invalid source run")
    if name == "candidate.json" and data["archiveSHA256"] != data["files"]["Utatane-submission.zip"]:
        raise ValueError("Submission hash differs from the candidate manifest")
    return data


class GitHub:
    def __init__(self):
        self.repository = os.environ["GITHUB_REPOSITORY"]
        if not re.fullmatch(r"[\w.-]+/[\w.-]+", self.repository):
            raise ValueError("Invalid repository")

    def api(self, path):
        return json.loads(run("gh", "api", "--method", "GET", f"repos/{self.repository}/{path}"))

    def source(self, run_id):
        value = self.api(f"actions/runs/{int(run_id)}")
        if (value["event"] != "push" or value["status"] != "completed" or value["conclusion"] != "success"
                or value["head_repository"]["full_name"].lower() != self.repository.lower()
                or value["path"] != ".github/workflows/build.yml" or not TAG.fullmatch(value["head_branch"])):
            raise ValueError("Only a successful trusted release-tag Build can be resumed")
        target = self.api(f"git/ref/tags/{value['head_branch']}")["object"]
        for _ in range(5):
            if target["type"] == "commit":
                break
            if target["type"] != "tag":
                raise ValueError("Invalid release tag target")
            target = self.api(f"git/tags/{target['sha']}")["object"]
        if target["type"] != "commit" or target["sha"] != value["head_sha"]:
            raise ValueError("Release tag moved after the original build")
        return value

    def source_artifact(self, run_id, name):
        items = self.api(f"actions/runs/{int(run_id)}/artifacts?per_page=100")["artifacts"]
        matches = [item for item in items if item["name"] == name and not item["expired"]]
        if len(matches) != 1:
            raise ValueError(f"Missing or expired {name}; do not resubmit or rebuild implicitly")
        return matches[0]

    def continuation_artifact(self, name):
        items = self.api(f"actions/artifacts?name={name}&per_page=100")["artifacts"]
        for item in items:
            if item["name"] != name or item["expired"]:
                continue
            owner = self.api(f"actions/runs/{item['workflow_run']['id']}")
            if (owner["path"] == ".github/workflows/release.yml"
                    and owner["event"] in ("schedule", "workflow_run", "workflow_dispatch")
                    and owner["head_repository"]["full_name"].lower() == self.repository.lower()):
                return item
        return None

    def download(self, artifact, destination):
        destination.mkdir(parents=True, exist_ok=False)
        with tempfile.TemporaryFile() as stream:
            subprocess.run(["gh", "api", "--method", "GET", f"repos/{self.repository}/actions/artifacts/{artifact['id']}/zip"], stdout=stream, check=True)
            stream.seek(0)
            with zipfile.ZipFile(stream) as archive:
                for entry in archive.infolist():
                    path = PurePosixPath(entry.filename)
                    if (path.is_absolute() or ".." in path.parts or "\\" in entry.filename
                            or stat.S_ISLNK(entry.external_attr >> 16)):
                        raise ValueError("Unsafe release artifact")
                archive.extractall(destination)


def bind(source, candidate, receipt=None):
    if (candidate["runId"] != source["id"] or candidate["commit"] != source["head_sha"]
            or candidate["tag"] != source["head_branch"] or candidate["buildNumber"] != source["run_number"]):
        raise ValueError("Candidate does not match the trusted source run")
    if receipt is not None:
        if any(receipt[key] != candidate[key] for key in ("tag", "commit", "runId", "archiveSHA256")):
            raise ValueError("Notarization receipt does not match this candidate")
        uuid.UUID(receipt["submissionId"])


def prepare(args):
    root = args.directory
    if root.exists():
        raise ValueError("Candidate directory already exists")
    root.mkdir(parents=True)
    tag = os.environ["GITHUB_REF_NAME"]
    if not TAG.fullmatch(tag):
        raise ValueError("Expected a version tag")
    info = plistlib.loads((args.app / "Contents/Info.plist").read_bytes())
    number = int(os.environ["GITHUB_RUN_NUMBER"])
    if info["CFBundleShortVersionString"] != tag[1:] or int(info["CFBundleVersion"]) != number:
        raise ValueError("App version differs from the tagged build")
    subprocess.run(["codesign", "--verify", "--deep", "--strict", str(args.app)], check=True)
    subprocess.run(["ditto", "-c", "-k", "--keepParent", str(args.app), str(root / "Utatane-submission.zip")], check=True)
    shutil.copyfile(args.generator, root / "generate_appcast")
    shutil.copytree(args.content, root / "content")
    (root / "release-notes.md").write_bytes(run("python3", "Scripts/generate-release-notes.py", "--tag", tag))
    seal(root, "candidate.json", {
        "schemaVersion": 1, "tag": tag, "commit": os.environ["GITHUB_SHA"],
        "runId": int(os.environ["GITHUB_RUN_ID"]), "buildNumber": number,
        "teamId": os.environ["APPLE_TEAM_ID"], "archiveSHA256": digest(root / "Utatane-submission.zip"),
        "sparklePublicKey": info["SUPublicEDKey"],
    })


def submit(args):
    candidate = verify(args.directory, "candidate.json")
    if candidate["runId"] != int(os.environ["GITHUB_RUN_ID"]):
        raise ValueError("Submission must belong to the current source run")
    github = GitHub()
    artifacts = github.api(f"actions/runs/{candidate['runId']}/artifacts?per_page=100")["artifacts"]
    previous = next((item for item in artifacts if item["name"] == REQUEST and not item["expired"]), None)
    if previous:
        github.download(previous, args.receipt)
        receipt = read(args.receipt / "request.json")
        for key in ("tag", "commit", "runId", "archiveSHA256"):
            if receipt[key] != candidate[key]:
                raise ValueError("Existing notarization belongs to different bytes")
        uuid.UUID(receipt["submissionId"])
        output("reused", "true")
        summary(f"Existing notarization request retained: {receipt['submissionId']}")
        return
    name = f"Utatane-{candidate['tag']}-run{candidate['runId']}-{candidate['archiveSHA256'][:16]}.zip"
    history = json.loads(run("xcrun", "notarytool", "history", *notary_auth(args.profile), "--output-format", "json"))
    matches = [item for item in history.get("history", []) if item.get("name") == name]
    if matches:
        submission = matches[0]["id"]
    else:
        with tempfile.TemporaryDirectory(prefix="utatane-submit-") as temporary:
            archive = Path(temporary) / name
            shutil.copyfile(args.directory / "Utatane-submission.zip", archive)
            response = json.loads(run("xcrun", "notarytool", "submit", archive, *notary_auth(args.profile), "--output-format", "json"))
            submission = response["id"]
    uuid.UUID(submission)
    write(args.receipt / "request.json", {key: candidate[key] for key in ("tag", "commit", "runId", "archiveSHA256")} | {"submissionId": submission})
    output("reused", "false")
    summary(f"Notarization submitted: {submission}. Scheduled checks will resume this exact candidate.")


def discover(args):
    github = GitHub()
    requested = os.environ.get("SOURCE_RUN_ID", "").strip()
    if requested:
        if not requested.isdecimal():
            raise ValueError("Source run ID must be numeric")
        if os.environ.get("GITHUB_EVENT_NAME") == "workflow_run":
            event = github.api(f"actions/runs/{int(requested)}")
            if (event["event"] != "push" or event["conclusion"] != "success"
                    or not TAG.fullmatch(event["head_branch"] or "")):
                output("runs", "[]")
                summary("Ordinary, failed, or pull-request Build; no release work to perform.")
                return
        sources = [github.source(int(requested))]
    else:
        sources = []
        cutoff = datetime.now(timezone.utc) - timedelta(days=30)
        for page in range(1, 11):
            items = github.api(f"actions/workflows/build.yml/runs?event=push&status=success&per_page=100&page={page}")["workflow_runs"]
            for item in items:
                if datetime.fromisoformat(item["created_at"].replace("Z", "+00:00")) >= cutoff and TAG.fullmatch(item["head_branch"] or ""):
                    sources.append(item)
            if len(items) < 100 or datetime.fromisoformat(items[-1]["created_at"].replace("Z", "+00:00")) < cutoff:
                break
    result = []
    for source in sorted(sources, key=lambda item: item["run_number"]):
        run_id = source["id"]
        if github.continuation_artifact(f"Utatane-notary-terminal-{run_id}"):
            continue
        try:
            github.source_artifact(run_id, REQUEST)
        except ValueError:
            if requested and os.environ.get("GITHUB_EVENT_NAME") == "workflow_dispatch":
                raise
            continue  # Old releases and ordinary builds never submitted to this pipeline.
        try:
            github.source(run_id)
            github.source_artifact(run_id, CANDIDATE)
        except ValueError as error:
            if requested and os.environ.get("GITHUB_EVENT_NAME") == "workflow_dispatch":
                raise
            summary(f"::warning::Cannot resume source run {run_id}: {error}")
            continue
        result.append(run_id)
    output("runs", json.dumps(result, separators=(",", ":")))
    summary(f"Pending notarization release runs: {result}")


def load_candidate(args):
    github = GitHub()
    source = github.source(args.run_id)
    github.download(github.source_artifact(args.run_id, CANDIDATE), args.directory)
    github.download(github.source_artifact(args.run_id, REQUEST), args.receipt)
    candidate = verify(args.directory, "candidate.json")
    receipt = read(args.receipt / "request.json")
    bind(source, candidate, receipt)
    output("tag", candidate["tag"])
    output("submission", receipt["submissionId"])


def check(args):
    candidate = verify(args.directory, "candidate.json")
    receipt = read(args.receipt / "request.json")
    bind(GitHub().source(candidate["runId"]), candidate, receipt)
    response = json.loads(run("xcrun", "notarytool", "info", receipt["submissionId"], *notary_auth(args.profile), "--output-format", "json"))
    if response["id"].lower() != receipt["submissionId"].lower():
        raise ValueError("Apple returned a different notarization submission")
    status = response["status"]
    if status not in ("Accepted", "In Progress", "Invalid", "Rejected"):
        raise ValueError(f"Unexpected notarization status: {status}")
    write(args.receipt / "status.json", response)
    output("status", {"Accepted": "accepted", "In Progress": "pending", "Invalid": "rejected", "Rejected": "rejected"}[status])
    summary(f"{candidate['tag']}: Apple notarization is **{status}** ({receipt['submissionId']}).")
    if status != "In Progress":
        subprocess.run(["xcrun", "notarytool", "log", receipt["submissionId"], *notary_auth(args.profile), str(args.receipt / "notary-log.json")], check=True)
        log = read(args.receipt / "notary-log.json")
        if log["status"] != status or (status == "Accepted" and any(item.get("severity") == "error" for item in log.get("issues") or [])):
            raise ValueError("Notarization log contradicts the accepted status")


def verify_feed(root, public):
    appcast = root / "update-feed/appcast.xml"
    contents = appcast.read_bytes()
    marker = contents.rfind(b"<!-- sparkle-signatures:\n")
    if marker < 0:
        raise ValueError("Missing Sparkle feed signature")
    fields = dict(line.split(b":", 1) for line in contents[marker:].split(b"-->", 1)[0].splitlines() if b":" in line)
    if int(fields[b"length"]) != marker:
        raise ValueError("Invalid signed feed length")
    item = ET.fromstring(contents).find("channel/item")
    enclosure = item.find("enclosure")
    archive = root / "Utatane-macOS.zip"
    if int(enclosure.attrib["length"]) != archive.stat().st_size:
        raise ValueError("Feed does not match final ZIP size")
    with tempfile.TemporaryDirectory() as temporary:
        temp = Path(temporary)
        (temp / "public.der").write_bytes(bytes.fromhex("302a300506032b6570032100") + base64.b64decode(public))
        subprocess.run(["openssl", "pkey", "-pubin", "-inform", "DER", "-in", str(temp / "public.der"), "-out", str(temp / "public.pem")], check=True)
        (temp / "feed.xml").write_bytes(contents[:marker])
        for name, path, signature in (("archive", archive, enclosure.attrib[SPARKLE + "edSignature"]), ("feed", temp / "feed.xml", fields[b"edSignature"].strip())):
            (temp / f"{name}.sig").write_bytes(base64.b64decode(signature))
            subprocess.run(["openssl", "pkeyutl", "-verify", "-rawin", "-pubin", "-inkey", str(temp / "public.pem"), "-sigfile", str(temp / f"{name}.sig"), "-in", str(path)], check=True)
    return item


def finalize(args):
    github = GitHub()
    candidate = verify(args.directory, "candidate.json")
    receipt = read(args.receipt / "request.json")
    bind(github.source(candidate["runId"]), candidate, receipt)
    status = read(args.receipt / "status.json")
    if status["status"] != "Accepted" or status["id"].lower() != receipt["submissionId"].lower():
        raise ValueError("Publication requires Apple's Accepted status")
    existing = github.continuation_artifact(f"Utatane-notary-finalized-{candidate['runId']}")
    if existing:
        github.download(existing, args.final)
        saved = verify(args.final, "finalized.json")
        if any(saved[key] != candidate[key] for key in ("tag", "commit", "runId", "buildNumber", "archiveSHA256", "sparklePublicKey")) or saved["submissionId"] != receipt["submissionId"]:
            raise ValueError("Finalized artifact belongs to another notarization")
        verify_feed(args.final, saved["sparklePublicKey"])
        output("reused", "true")
        return
    args.final.mkdir(parents=True, exist_ok=False)
    with tempfile.TemporaryDirectory(prefix="utatane-staple-") as temporary:
        subprocess.run(["ditto", "-x", "-k", str(args.directory / "Utatane-submission.zip"), temporary], check=True)
        app = Path(temporary) / "Utatane.app"
        info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
        if info["CFBundleShortVersionString"] != candidate["tag"][1:] or int(info["CFBundleVersion"]) != candidate["buildNumber"]:
            raise ValueError("Signed app version changed")
        details = subprocess.run(["codesign", "-dvv", str(app)], capture_output=True, text=True, check=True).stderr
        if f"TeamIdentifier={candidate['teamId']}" not in details or "runtime" not in details:
            raise ValueError("Unexpected signing team or missing hardened runtime")
        for command in (["xcrun", "stapler", "staple"], ["xcrun", "stapler", "validate"], ["codesign", "--verify", "--deep", "--strict"], ["spctl", "--assess", "--type", "execute", "--verbose=2"]):
            subprocess.run([*command, str(app)], check=True)
        subprocess.run(["ditto", "-c", "-k", "--keepParent", str(app), str(args.final / "Utatane-macOS.zip")], check=True)
    feed = args.final / "update-feed"
    feed.mkdir()
    shutil.copyfile(args.final / "Utatane-macOS.zip", feed / "Utatane-macOS.zip")
    generator = (args.directory / "generate_appcast").resolve()
    generator.chmod(0o755)
    subprocess.run([str(generator), "--ed-key-file", "-", "--download-url-prefix", f"https://github.com/{github.repository}/releases/download/{candidate['tag']}/", "--link", "https://dl.wmsci.com/utatane.html", "--maximum-deltas", "0", "-o", str(feed / "appcast.xml"), str(feed)], input=os.environ["SPARKLE_PRIVATE_KEY"].encode(), check=True)
    (feed / "Utatane-macOS.zip").unlink()
    shutil.copytree(args.directory / "content", args.final / "content")
    shutil.copyfile(args.directory / "release-notes.md", args.final / "release-notes.md")
    shutil.copyfile(args.receipt / "notary-log.json", args.final / "notary-log.json")
    item = verify_feed(args.final, candidate["sparklePublicKey"])
    if item.find(SPARKLE + "version").text != str(candidate["buildNumber"]):
        raise ValueError("Feed build number differs from source")
    if item.find("enclosure").attrib["url"] != f"https://github.com/{github.repository}/releases/download/{candidate['tag']}/Utatane-macOS.zip":
        raise ValueError("Feed download URL differs from source")
    seal(args.final, "finalized.json", {**{key: candidate[key] for key in ("schemaVersion", "tag", "commit", "runId", "buildNumber", "archiveSHA256", "sparklePublicKey")}, "submissionId": receipt["submissionId"]})
    output("reused", "false")


def production_feed():
    request = Request("https://dl.wmsci.com/utatane/appcast.xml", headers={"User-Agent": "Utatane-Release/1.0", "Cache-Control": "no-cache"})
    with urlopen(request, timeout=45) as response:
        data = response.read(2_000_001)
    if len(data) > 2_000_000:
        raise ValueError("Unexpectedly large production feed")
    return data


def feed_build(contents):
    numbers = [int(item.text) for item in ET.fromstring(contents).findall(f"channel/item/{SPARKLE}version")]
    if not numbers:
        raise ValueError("Production feed contains no build number")
    return max(numbers)


def publish(args):
    github = GitHub()
    saved = verify(args.final, "finalized.json")
    source = github.source(saved["runId"])
    if saved["commit"] != source["head_sha"] or saved["tag"] != source["head_branch"]:
        raise ValueError("Finalized release no longer matches its source")
    verify_feed(args.final, saved["sparklePublicKey"])
    if os.environ["VT_SHA256"] != digest(args.final / "Utatane-macOS.zip"):
        raise ValueError("VirusTotal result belongs to different bytes")
    promote = saved["buildNumber"] >= feed_build(production_feed())
    tag = saved["tag"]
    assets = [args.final / "Utatane-macOS.zip", args.final / "update-feed/appcast.xml"]
    result = subprocess.run(["gh", "release", "view", tag, "--repo", github.repository, "--json", "assets,isDraft"], capture_output=True, text=True)
    if result.returncode == 0:
        release = json.loads(result.stdout)
        if release["isDraft"]:
            raise ValueError("Refusing to overwrite an existing draft release")
        by_name = {item["name"]: item for item in release["assets"]}
        for path in assets:
            if path.name in by_name:
                with tempfile.TemporaryDirectory() as temporary:
                    subprocess.run(["gh", "release", "download", tag, "--repo", github.repository, "--pattern", path.name, "--dir", temporary], check=True)
                    if digest(Path(temporary) / path.name) != digest(path):
                        raise ValueError("Published asset differs; refusing to replace an existing update")
            else:
                subprocess.run(["gh", "release", "upload", tag, str(path), "--repo", github.repository], check=True)
        # Preserve any edits the maintainer made to already-published notes.
        if promote:
            subprocess.run(["gh", "release", "edit", tag, "--repo", github.repository, "--latest"], check=True)
    else:
        # Do not treat network/authentication failures as permission to create.
        github.api(f"releases?per_page=1")
        notes = (args.final / "release-notes.md").read_text()
        notes += f"\n### 🛡️ VirusTotal Scan\n- **Status:** {os.environ['VT_STATUS']}\n- **SHA-256:** `{os.environ['VT_SHA256']}`\n- **Report:** {os.environ['VT_URL']}\n"
        with tempfile.NamedTemporaryFile(mode="w", suffix=".md") as stream:
            stream.write(notes)
            stream.flush()
            subprocess.run(["gh", "release", "create", tag, *map(str, assets), "--repo", github.repository, "--verify-tag", "--title", tag, "--notes-file", stream.name, "--latest=" + str(promote).lower()], check=True)
    output("promote", str(promote).lower())
    summary(f"{tag} published. Production feed promotion: {promote}.")


def verify_published(args):
    saved = verify(args.final, "finalized.json")
    contents = production_feed()
    if feed_build(contents) < saved["buildNumber"]:
        raise ValueError("Production feed has not reached this build")
    if feed_build(contents) == saved["buildNumber"] and contents != (args.final / "update-feed/appcast.xml").read_bytes():
        raise ValueError("Production appcast differs from the signed final artifact")


def terminal(args):
    candidate = verify(args.directory, "candidate.json")
    receipt = read(args.receipt / "request.json")
    status = read(args.receipt / "status.json")
    if status["status"] not in ("Accepted", "Invalid", "Rejected"):
        raise ValueError("A pending submission is not terminal")
    write(Path("dist/notary-terminal/result.json"), {
        "sourceRunId": candidate["runId"], "tag": candidate["tag"], "commit": candidate["commit"],
        "submissionId": receipt["submissionId"], "status": status["status"],
        "finishedAt": datetime.now(timezone.utc).isoformat(),
    })


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("prepare", "submit", "discover", "load", "check", "finalize", "publish", "verify-published", "terminal"))
    parser.add_argument("--directory", type=Path, default=Path("dist/notary-candidate"))
    parser.add_argument("--receipt", type=Path, default=Path("dist/notary-request"))
    parser.add_argument("--final", type=Path, default=Path("dist/release"))
    parser.add_argument("--profile", default="utatane-ci")
    parser.add_argument("--run-id", type=int)
    parser.add_argument("--app", type=Path)
    parser.add_argument("--generator", type=Path)
    parser.add_argument("--content", type=Path)
    args = parser.parse_args()
    {"prepare": prepare, "submit": submit, "discover": discover, "load": load_candidate, "check": check, "finalize": finalize, "publish": publish, "verify-published": verify_published, "terminal": terminal}[args.command](args)


if __name__ == "__main__":
    main()
