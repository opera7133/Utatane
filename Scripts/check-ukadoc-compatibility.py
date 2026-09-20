#!/usr/bin/env python3
"""Keep documented UKADOC compatibility claims tied to production source."""

from pathlib import Path
import re
import sys


ROOT = Path(__file__).resolve().parent.parent
DOCUMENT = ROOT / "Docs" / "Reference" / "UKADOC-Text-File-Compatibility.md"
SHIORI_EVENT_DOCUMENT = ROOT / "Docs" / "Reference" / "UKADOC-SHIORI-Event-Compatibility.md"
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

    event_document = SHIORI_EVENT_DOCUMENT.read_text(encoding="utf-8")
    event_rows = re.findall(
        r"^\| \[`([^`]+)`\]\([^\n]+\) \| (✅|🟡|❌|➖) \|",
        event_document,
        flags=re.MULTILINE,
    )
    event_ids = [event_id for event_id, _ in event_rows]
    if len(event_rows) != 304:
        failures.append(f"SHIORI Event inventory has {len(event_rows)} rows; expected 304")
    if len(event_ids) != len(set(event_ids)):
        failures.append("SHIORI Event inventory contains duplicate event IDs")
    unclassified = [event_id for event_id, status in event_rows if status == "❌"]
    if unclassified:
        failures.append(
            "SHIORI Event inventory has unclassified events: " + ", ".join(unclassified)
        )
    counts = {status: sum(row_status == status for _, row_status in event_rows) for status in ("✅", "🟡", "❌", "➖")}
    expected_summary = (
        f"調査結果: ✅ {counts['✅']} / 🟡 {counts['🟡']} / "
        f"❌ {counts['❌']} / ➖ {counts['➖']}"
    )
    if "UKADOC掲載イベント数: 304" not in event_document:
        failures.append("SHIORI Event inventory does not declare the current 304-event baseline")
    if expected_summary not in event_document:
        failures.append("SHIORI Event inventory summary does not match its rows")

    if failures:
        for failure in failures:
            print(f"UKADOC compatibility error: {failure}", file=sys.stderr)
        return 1

    print(
        f"Checked {len(CLAIMED_SYNTAX)} UKADOC syntax claims and "
        f"{len(event_rows)} classified SHIORI Events."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
