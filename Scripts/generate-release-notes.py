#!/usr/bin/env python3
"""Extract the tagged version's release notes from CHANGELOG.md."""

import argparse
from pathlib import Path
import re
import sys


def render(changelog: str, tag: str) -> str:
    if not re.fullmatch(r"v\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?", tag):
        raise ValueError(f"Invalid release tag: {tag}")
    version = tag[1:]
    sections = []
    current = None
    fence = None
    for line in changelog.splitlines():
        marker = re.match(r"^\s{0,3}(`{3,}|~{3,})", line)
        if marker:
            token = marker.group(1)
            if fence is None:
                fence = token
            elif token[0] == fence[0] and len(token) >= len(fence) and not line[marker.end():].strip():
                fence = None
        heading = re.match(r"^##\s+\[([^\]]+)\](?:\s+-\s+.*)?\s*$", line) if fence is None else None
        if heading:
            current = [] if heading.group(1) == version else None
            if current is not None:
                sections.append(current)
        elif current is not None:
            # Link definitions belong to the changelog, not the section body.
            if not re.match(r"^\[[^\]]+\]:\s+", line):
                current.append(line)
    if len(sections) != 1:
        raise ValueError(f"Expected one CHANGELOG section for {version}, found {len(sections)}")
    body = "\n".join(sections[0]).strip()
    if not body or not any(line.strip() and not line.startswith("#") for line in sections[0]):
        raise ValueError(f"CHANGELOG section for {version} is empty")
    links = re.findall(rf"^\[{re.escape(version)}\]:\s+(https://\S+)\s*$", changelog, re.MULTILINE)
    if len(links) != 1:
        raise ValueError(f"Expected one CHANGELOG comparison link for {version}")
    return f"{body}\n\n**Full Changelog**: {links[0]}\n"


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--tag", required=True)
    parser.add_argument("--changelog", type=Path, default=Path("CHANGELOG.md"))
    args = parser.parse_args()
    try:
        notes = render(args.changelog.read_text(encoding="utf-8"), args.tag)
    except (OSError, ValueError) as error:
        parser.exit(1, f"Release notes: {error}\n")
    sys.stdout.write(notes)


if __name__ == "__main__":
    main()
