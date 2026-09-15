#!/usr/bin/env python3
"""Keep documented UKADOC compatibility claims tied to production source."""

from pathlib import Path
import sys


ROOT = Path(__file__).resolve().parent.parent
DOCUMENT = ROOT / "Docs" / "Reference" / "UKADOC-Text-File-Compatibility.md"
SOURCE_ROOTS = (ROOT / "packages", ROOT / "apps")

# Add a claimed syntax here when the compatibility table starts describing it as
# implemented. The check deliberately scans production Sources only, so a token
# appearing only in a test cannot make the public claim pass.
CLAIMED_SYNTAX = (
    "seriko.zorder",
    "seriko.sticky-window",
    "seriko.alignmenttodesktop",
    "clickwaitmarker.filename",
    "windowposition.x",
    "windowposition.y",
    "windowposition.limit",
    "communicatebox.width",
    "menuitemex",
    "shared-index",
    "exclusive",
    "delete.txt",
)


def production_sources() -> list[Path]:
    files: list[Path] = []
    for source_root in SOURCE_ROOTS:
        files.extend(path for path in source_root.glob("**/Sources/**/*.swift") if path.is_file())
    return files


def main() -> int:
    document = DOCUMENT.read_text(encoding="utf-8")
    sources = production_sources()
    source_text = "\n".join(path.read_text(encoding="utf-8") for path in sources)
    failures: list[str] = []

    for syntax in CLAIMED_SYNTAX:
        if syntax not in document:
            failures.append(f"documentation is missing claimed syntax: {syntax}")
        if syntax not in source_text:
            failures.append(f"production source is missing documented syntax: {syntax}")

    if failures:
        for failure in failures:
            print(f"UKADOC compatibility error: {failure}", file=sys.stderr)
        return 1

    print(f"Checked {len(CLAIMED_SYNTAX)} UKADOC compatibility claims.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
