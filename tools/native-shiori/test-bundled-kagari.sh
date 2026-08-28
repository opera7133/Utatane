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
for library in libkagari.dylib liblua5.4.dylib; do
    xcrun lipo "$bundled/$library" -verify_arch "$@"
    codesign --verify --strict "$bundled/$library"
    # No Homebrew, build directory or developer-machine library dependencies.
    otool -L "$bundled/$library" | awk '
        /^[[:space:]]/ && $1 !~ /^(@rpath\/|\/usr\/lib\/|\/System\/Library\/)/ { bad=1; print > "/dev/stderr" }
        END { exit bad }
    '
done
for license in kagari-MIT.txt sol2-MIT.txt lua-header-with-license.txt; do
    test -s "$bundled/licenses/$license"
    grep -q 'Permission is hereby granted' "$bundled/licenses/$license"
    grep -q 'Copyright' "$bundled/licenses/$license"
done
cmp "$bundled/licenses/kagari-MIT.txt" "$repository/packages/kagari-native/Vendor/kagari/LICENSE"
cmp "$bundled/dependencies.json" "$repository/tools/native-shiori/kagari-dependencies.json"

# Exercise the packaged binary after relocation, without the source/build tree
# or the user's Application Support overriding the selected library.
relocated=$(mktemp -d "${TMPDIR:-/tmp}/utatane-kagari-relocation.XXXXXX")
trap 'rm -rf "$relocated"' EXIT HUP INT TERM
cp "$bundled/libkagari.dylib" "$bundled/liblua5.4.dylib" "$relocated/"
UTATANE_KAGARI_MODULE="$relocated/libkagari.dylib" \
    swift test --package-path "$repository/packages" --filter Kagari
