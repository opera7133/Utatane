#!/bin/sh
set -eu
if [ "$#" -lt 2 ]; then
    echo "usage: $0 /path/to/Utatane.app architecture [architecture...]" >&2
    exit 64
fi
application=$(cd "$1" && pwd)
shift
repository=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
bundled="$application/Contents/Resources/NativeShiori/kagari"

sh "$repository/tools/native-shiori/verify-bundled-kagari.sh" "$application" "$@"

# Exercise the packaged binary after relocation, without the source/build tree
# or the user's Application Support overriding the selected library.
relocated=$(mktemp -d "${TMPDIR:-/tmp}/utatane-kagari-relocation.XXXXXX")
trap 'rm -rf "$relocated"' EXIT HUP INT TERM
cp "$bundled/libkagari.dylib" "$bundled/liblua5.4.dylib" "$relocated/"
UTATANE_KAGARI_MODULE="$relocated/libkagari.dylib" \
    swift test --package-path "$repository/packages" --filter Kagari
