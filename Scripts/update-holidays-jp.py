#!/usr/bin/env python3
"""Refresh factual Cabinet Office holiday data; review the diff before release."""
import argparse
import csv
import datetime
import io
from pathlib import Path
import urllib.request

SOURCE = "https://www8.cao.go.jp/chosei/shukujitsu/syukujitsu.csv"
ROOT = Path(__file__).resolve().parent.parent


def convert(data: bytes) -> str:
    rows = list(csv.reader(io.StringIO(data.decode("cp932"))))
    if not rows or len(rows) < 1000 or len(rows[0]) != 2:
        raise ValueError("Unexpected holiday CSV")
    dates = {}
    for row in rows[1:]:
        if len(row) != 2:
            raise ValueError("Invalid holiday row")
        year, month, day = map(int, row[0].split("/"))
        date = datetime.date(year, month, day).isoformat()
        name = row[1].strip()
        if not name or any(c in name for c in "\r\n\0") or date in dates:
            raise ValueError("Invalid holiday name or duplicate date")
        dates[date] = name
    if min(dates) != "1955-01-01" or max(dates) < "2027-11-23":
        raise ValueError("Unexpected data coverage")
    return ("# Source: Cabinet Office, Government of Japan; see Holidays-JP-Source.txt\n"
            + "\n".join(f"{date},{name}" for date, name in sorted(dates.items())) + "\n")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", type=Path, help="Use an already downloaded Cabinet Office CSV")
    args = parser.parse_args()
    if args.input:
        data = args.input.read_bytes()
    else:
        with urllib.request.urlopen(SOURCE, timeout=30) as response:
            data = response.read(1024 * 1024)
    output = convert(data)
    destination = ROOT / "packages/core/Sources/Resources/holidays-JP.txt"
    destination.write_text(output, encoding="utf-8")
    print(f"Updated {destination}; review coverage and Holidays-JP-Source.txt before release")


if __name__ == "__main__":
    main()
