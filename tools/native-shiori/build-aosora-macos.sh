#!/bin/sh
set -eu

if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
    echo "usage: $0 /path/to/aosora-shiori [output-directory]" >&2
    exit 64
fi

source_directory=$1
output_directory=${2:-"$HOME/Library/Application Support/Utatane/NativeShiori/aosora"}

if [ ! -f "$source_directory/Makefile" ] || [ ! -f "$source_directory/aosora-shiori-dll/dllmain.cpp" ]; then
    echo "Aosora source tree not found: $source_directory" >&2
    exit 66
fi
if ! command -v pkg-config >/dev/null 2>&1; then
    echo "pkg-config is required. Install pkg-config, openssl@3 and jsoncpp first." >&2
    exit 69
fi
if ! pkg-config --exists jsoncpp; then
    echo "jsoncpp was not found by pkg-config." >&2
    exit 69
fi

openssl_pkgconfig=
if command -v brew >/dev/null 2>&1; then
    openssl_prefix=$(brew --prefix openssl@3 2>/dev/null || true)
    if [ -n "$openssl_prefix" ]; then
        openssl_pkgconfig="$openssl_prefix/lib/pkgconfig"
    fi
fi
if [ -n "$openssl_pkgconfig" ]; then
    PKG_CONFIG_PATH="${PKG_CONFIG_PATH:+$PKG_CONFIG_PATH:}$openssl_pkgconfig"
    export PKG_CONFIG_PATH
fi
if ! pkg-config --exists openssl; then
    echo "OpenSSL was not found by pkg-config." >&2
    exit 69
fi

build_directory=${TMPDIR:-/tmp}/utatane-aosora-build
mkdir -p "$build_directory" "$output_directory"
build_output="$build_directory/libaosora.dylib"
cxxflags="-std=c++20 -O2 -I aosora-shiori -fPIC $(pkg-config --cflags openssl jsoncpp)"
ldflags=$(pkg-config --libs openssl jsoncpp)

make -C "$source_directory" clean
make -C "$source_directory" \
    "LIBRARY=$build_output" \
    "CXXFLAGS=$cxxflags" \
    "SO_LDFLAGS=-dynamiclib $ldflags" \
    "$build_output"
cp "$build_output" "$output_directory/libaosora.dylib"

echo "Installed: $output_directory/libaosora.dylib"
