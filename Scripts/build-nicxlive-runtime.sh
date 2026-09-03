#!/bin/sh

set -eu

if [ "$#" -ne 3 ]; then
    echo "usage: $0 /path/to/nicxlive/source /path/to/build /path/to/output" >&2
    exit 64
fi

script_directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$script_directory/nicxlive-runtime-version.env"

source_directory=$1
build_directory=$2
output_directory=$3

if [ ! -d "$source_directory/.git" ]; then
    echo "nicxlive source checkout not found: $source_directory" >&2
    exit 66
fi

source_commit=$(git -C "$source_directory" rev-parse HEAD)
if [ "$source_commit" != "$NICXLIVE_COMMIT" ]; then
    echo "nicxlive source must be checked out at $NICXLIVE_COMMIT (found $source_commit)" >&2
    exit 65
fi

source_remote=$(git -C "$source_directory" remote get-url origin)
case "$source_remote" in
    "$NICXLIVE_REPOSITORY"|"${NICXLIVE_REPOSITORY%.git}") ;;
    *)
        echo "unexpected nicxlive origin: $source_remote" >&2
        exit 65
        ;;
esac

if ! git -C "$source_directory" diff --quiet || ! git -C "$source_directory" diff --cached --quiet; then
    echo "nicxlive tracked source files have local changes" >&2
    exit 65
fi

if [ ! -f "$source_directory/LICENSE" ]; then
    echo "nicxlive LICENSE not found" >&2
    exit 66
fi

cmake \
    -S "$source_directory" \
    -B "$build_directory" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_OSX_ARCHITECTURES='arm64;x86_64' \
    -DNICXLIVE_BUILD_SHARED=ON \
    -DNICXLIVE_BUILD_TESTS=OFF
cmake --build "$build_directory" --config Release --target nicxlive_shared --parallel 8

library="$build_directory/libnicxlive.dylib"
if [ ! -f "$library" ]; then
    echo "nicxlive build did not produce $library" >&2
    exit 70
fi

architectures=$(lipo -archs "$library")
case " $architectures " in
    *" arm64 "*) ;;
    *) echo "nicxlive runtime is missing arm64: $architectures" >&2; exit 65 ;;
esac
case " $architectures " in
    *" x86_64 "*) ;;
    *) echo "nicxlive runtime is missing x86_64: $architectures" >&2; exit 65 ;;
esac

mkdir -p "$output_directory"
install -m 755 "$library" "$output_directory/libnicxlive.dylib"
install -m 644 "$source_directory/LICENSE" "$output_directory/LICENSE"

echo "Built nicxlive runtime from $NICXLIVE_COMMIT"
echo "Library: $output_directory/libnicxlive.dylib"
echo "Architectures: $architectures"
