#!/bin/sh
set -eu

if [ "$#" -lt 2 ] || [ "$#" -gt 3 ]; then
    echo "usage: $0 /path/to/lua-5.4.x /path/to/sol2-3.5.0 [output-directory]" >&2
    exit 64
fi
lua_source=$(cd "$1/src" && pwd)
sol_include=$(cd "$2/include" && pwd)
repository=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
kagari_source="$repository/packages/kagari-native/Vendor/kagari"
output_directory=${3:-"$HOME/Library/Application Support/Utatane/NativeShiori/kagari"}
if ! grep -Eq '^#define LUA_VERSION_NUM[[:space:]]+504$' "$lua_source/lua.h"; then
    echo "Lua 5.4 sources are required." >&2
    exit 65
fi
test -f "$sol_include/sol/sol.hpp"
test -f "$kagari_source/kagari_unix.cpp"
build_directory=$(mktemp -d "${TMPDIR:-/tmp}/utatane-kagari-build.XXXXXX")
trap 'rm -rf "$build_directory"' EXIT HUP INT TERM

# Build one shared Lua runtime: native Lua extensions must use this same ABI.
architectures=${KAGARI_ARCHS:-$(uname -m)}
sdk_path=$(xcrun --sdk macosx --show-sdk-path)
for architecture in $architectures; do
    case "$architecture" in arm64|x86_64) ;; *) echo "Unsupported architecture: $architecture" >&2; exit 65 ;; esac
    arch_directory="$build_directory/$architecture"
    mkdir -p "$arch_directory"
    for source in "$lua_source"/*.c; do
        name=$(basename "$source" .c)
        case "$name" in lua|luac) continue ;; esac
        xcrun --sdk macosx clang -arch "$architecture" -isysroot "$sdk_path" \
            -O2 -fPIC -mmacosx-version-min=14.0 -DLUA_USE_MACOSX \
            -I "$lua_source" -c "$source" -o "$arch_directory/$name.o"
    done
    xcrun --sdk macosx clang -arch "$architecture" -isysroot "$sdk_path" \
        -dynamiclib -mmacosx-version-min=14.0 \
        -Wl,-install_name,@rpath/liblua5.4.dylib \
        "$arch_directory"/*.o -o "$arch_directory/liblua5.4.dylib"
    xcrun --sdk macosx clang++ -arch "$architecture" -isysroot "$sdk_path" \
        -std=c++17 -O2 -dynamiclib -mmacosx-version-min=14.0 \
        -I "$sol_include" -I "$lua_source" \
        "$kagari_source/kagari.cpp" "$kagari_source/kagari_unix.cpp" \
        -L "$arch_directory" -llua5.4 \
        -Wl,-install_name,@rpath/libkagari.dylib -Wl,-rpath,@loader_path \
        -o "$arch_directory/libkagari.dylib"
done
mkdir -p "$output_directory/licenses"
for library in liblua5.4.dylib libkagari.dylib; do
    xcrun lipo -create "$build_directory"/*/"$library" -output "$output_directory/$library"
    codesign --force --sign - "$output_directory/$library"
done
cp "$kagari_source/LICENSE" "$output_directory/licenses/kagari-MIT.txt"
cp "$sol_include/../LICENSE.txt" "$output_directory/licenses/sol2-MIT.txt"
cp "$lua_source/lua.h" "$output_directory/licenses/lua-header-with-license.txt"
echo "Installed: $output_directory/libkagari.dylib"
