#!/bin/sh
set -eu

if [ "$#" -lt 2 ] || [ "$#" -gt 3 ]; then
    echo "usage: $0 /path/to/lua-5.4.4 /path/to/sol2-3.5.0 [output-directory]" >&2
    exit 64
fi
lua_source=$(cd "$1/src" && pwd)
sol_include=$(cd "$2/include" && pwd)
repository=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
kagari_source="$repository/packages/kagari-native/Vendor/kagari"
output_directory=${3:-"$HOME/Library/Application Support/Utatane/NativeShiori/kagari"}
if ! grep -Eq '^#define LUA_VERSION_NUM[[:space:]]+504$' "$lua_source/lua.h"; then
    echo "Lua 5.4 sources are required (validated with 5.4.4)." >&2
    exit 65
fi
test -f "$sol_include/sol/sol.hpp"
test -f "$kagari_source/kagari_unix.cpp"
build_directory=$(mktemp -d "${TMPDIR:-/tmp}/utatane-kagari-build.XXXXXX")
trap 'rm -rf "$build_directory"' EXIT HUP INT TERM

# Build one shared Lua runtime: native Lua extensions must use this same ABI.
for source in "$lua_source"/*.c; do
    name=$(basename "$source" .c)
    case "$name" in lua|luac) continue ;; esac
    clang -O2 -fPIC -mmacosx-version-min=14.0 -DLUA_USE_MACOSX \
        -I "$lua_source" -c "$source" -o "$build_directory/$name.o"
done
clang -dynamiclib -mmacosx-version-min=14.0 \
    -Wl,-install_name,@rpath/liblua5.4.dylib \
    "$build_directory"/*.o -o "$build_directory/liblua5.4.dylib"
clang++ -std=c++17 -O2 -dynamiclib -mmacosx-version-min=14.0 \
    -I "$sol_include" -I "$lua_source" \
    "$kagari_source/kagari.cpp" "$kagari_source/kagari_unix.cpp" \
    -L "$build_directory" -llua5.4 \
    -Wl,-install_name,@rpath/libkagari.dylib -Wl,-rpath,@loader_path \
    -o "$build_directory/libkagari.dylib"
mkdir -p "$output_directory/licenses"
cp "$build_directory/liblua5.4.dylib" "$build_directory/libkagari.dylib" "$output_directory/"
cp "$kagari_source/LICENSE" "$output_directory/licenses/kagari-MIT.txt"
cp "$sol_include/../LICENSE.txt" "$output_directory/licenses/sol2-MIT.txt"
cp "$lua_source/lua.h" "$output_directory/licenses/lua-header-with-license.txt"
echo "Installed: $output_directory/libkagari.dylib"
