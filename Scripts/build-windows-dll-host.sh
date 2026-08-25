#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 OUTPUT_PATH" >&2
  exit 2
fi

repository_root=$(cd "$(dirname "$0")/.." && pwd)
output_path=$1
object_path="${output_path}.obj"
source_date_epoch=${SOURCE_DATE_EPOCH:-$(git -C "$repository_root" show -s --format=%ct HEAD)}

mkdir -p "$(dirname "$output_path")"
trap 'rm -f -- "$object_path"' EXIT

SOURCE_DATE_EPOCH=$source_date_epoch zig cc \
  -target x86-windows-gnu \
  -Os \
  -g0 \
  -fno-stack-protector \
  -c "$repository_root/tools/windows-dll-host/main.c" \
  -o "$object_path"

SOURCE_DATE_EPOCH=$source_date_epoch zig cc \
  -target x86-windows-gnu \
  -nostdlib \
  -s \
  -Wl,--entry=mainCRTStartup \
  -Wl,--subsystem,console \
  "$object_path" \
  -lkernel32 \
  -o "$output_path"
