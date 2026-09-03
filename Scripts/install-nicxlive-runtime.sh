#!/bin/sh

set -eu

if [ "$#" -ne 2 ]; then
    echo "usage: $0 /path/to/libnicxlive.dylib /path/to/nicxlive-LICENSE" >&2
    exit 64
fi

library_source=$1
license_source=$2
runtime_directory="${UTATANE_NICXLIVE_RUNTIME_DIRECTORY:-${HOME}/Library/Application Support/Utatane/Runtimes/nicxlive}"

if [ ! -f "$library_source" ]; then
    echo "nicxlive library not found: $library_source" >&2
    exit 66
fi
if [ ! -f "$license_source" ]; then
    echo "nicxlive license not found: $license_source" >&2
    exit 66
fi

mkdir -p "$runtime_directory"
install -m 755 "$library_source" "$runtime_directory/libnicxlive.dylib"
install -m 644 "$license_source" "$runtime_directory/LICENSE"

echo "Installed nicxlive runtime: $runtime_directory/libnicxlive.dylib"
lipo -archs "$runtime_directory/libnicxlive.dylib"
