#!/usr/bin/env python3
"""Generate Localizable.xcstrings from compact per-language JSON files."""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
TRANSLATIONS_DIR = ROOT / "Localizations"
CATALOG_PATH = ROOT / "apps/Utatane/Resources/Localizable.xcstrings"
SOURCE_LANGUAGE = "ja"
REFERENCE_LANGUAGE = "en"
PLACEHOLDER = re.compile(r"%(?:(\d+)\$)?([A-Za-z@]+)")
LANGUAGE_CODE = re.compile(r"[A-Za-z]{2,3}(?:-[A-Za-z0-9]+)*")


def placeholders(value: str) -> list[tuple[int, str]]:
    result: list[tuple[int, str]] = []
    implicit_index = 1
    for match in PLACEHOLDER.finditer(value.replace("%%", "")):
        index = int(match.group(1)) if match.group(1) else implicit_index
        result.append((index, match.group(2)))
        if not match.group(1):
            implicit_index += 1
    return sorted(result)


def read_translations() -> dict[str, dict[str, str]]:
    translations: dict[str, dict[str, str]] = {}
    for path in sorted(TRANSLATIONS_DIR.glob("*.json")):
        language = path.stem
        if not LANGUAGE_CODE.fullmatch(language):
            raise ValueError(f"{path}: filename must be a language code such as en or zh-Hans")
        data = json.loads(path.read_text(encoding="utf-8"))
        if not isinstance(data, dict) or not all(
            isinstance(key, str) and isinstance(value, str) for key, value in data.items()
        ):
            raise ValueError(f"{path}: expected a JSON object containing only string values")
        translations[language] = data
    if not translations:
        raise ValueError(f"no translation files found in {TRANSLATIONS_DIR}")
    if REFERENCE_LANGUAGE not in translations:
        raise ValueError(f"{TRANSLATIONS_DIR / (REFERENCE_LANGUAGE + '.json')} is required")
    return translations


def build_catalog(translations: dict[str, dict[str, str]]) -> dict[str, object]:
    all_keys = set(translations[REFERENCE_LANGUAGE])
    errors: list[str] = []
    strings: dict[str, object] = {}

    for language, items in sorted(translations.items()):
        for extra_key in sorted(set(items) - all_keys):
            errors.append(f"{language}: unknown source string {extra_key!r}")

    for key in sorted(all_keys):
        localizations: dict[str, object] = {}
        source_placeholders = placeholders(key)
        for language, items in sorted(translations.items()):
            if key not in items:
                errors.append(f"{language}: missing translation for {key!r}")
                continue
            value = items[key]
            if placeholders(value) != source_placeholders:
                errors.append(
                    f"{language}: placeholder mismatch for {key!r}: "
                    f"{source_placeholders} != {placeholders(value)}"
                )
            localizations[language] = {
                "stringUnit": {"state": "translated", "value": value}
            }
        strings[key] = {
            "extractionState": "manual",
            "localizations": localizations,
        }

    if errors:
        raise ValueError("\n".join(errors))
    return {"sourceLanguage": SOURCE_LANGUAGE, "strings": strings, "version": "1.0"}


def serialized_catalog() -> str:
    catalog = build_catalog(read_translations())
    return json.dumps(
        catalog, ensure_ascii=False, indent=2, sort_keys=True, separators=(",", " : ")
    ) + "\n"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--check", action="store_true", help="fail if the generated catalog is out of date"
    )
    args = parser.parse_args()

    try:
        generated = serialized_catalog()
    except (OSError, ValueError, json.JSONDecodeError) as error:
        print(error, file=sys.stderr)
        return 1

    if args.check:
        current = CATALOG_PATH.read_text(encoding="utf-8")
        if current != generated:
            print(
                f"{CATALOG_PATH.relative_to(ROOT)} is out of date; "
                "run `mise run localization-generate`",
                file=sys.stderr,
            )
            return 1
        return 0

    CATALOG_PATH.write_text(generated, encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
