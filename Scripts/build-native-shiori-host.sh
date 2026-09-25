#!/bin/sh
set -eu
if [ "$#" -lt 1 ]; then
    echo "usage: $0 output [arm64 x86_64]" >&2
    exit 64
fi
repository_root=$(cd "$(dirname "$0")/.." && pwd)
output_path=$1
shift
if [ "$#" -eq 0 ]; then set -- "$(uname -m)"; fi
build_dir=$(mktemp -d "${TMPDIR:-/tmp}/utatane-shiori-host.XXXXXX")
trap 'rm -rf "$build_dir"' EXIT HUP INT TERM
mkdir -p "$(dirname "$output_path")"
for arch in "$@"; do
    case "$arch" in arm64|x86_64) ;; *) exit 65 ;; esac
    xcrun clang -std=c11 -Wall -Wextra -Werror -O2 -arch "$arch" -mmacosx-version-min=14.0 \
        "$repository_root/tools/native-shiori-host/main.c" -o "$build_dir/$arch"
done
xcrun lipo -create "$build_dir"/* -output "$output_path"
codesign --force --sign "${EXPANDED_CODE_SIGN_IDENTITY:--}" --identifier dev.utatane.shiori-host "$output_path"
