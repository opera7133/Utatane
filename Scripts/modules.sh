#!/bin/sh
# Delegate SHIORI builds to the companion repository.
set -eu
repository=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
modules=${UTATANE_MODULES_ROOT:-"$repository/../utatane-modules"}
if [ -z "${UTATANE_MODULES_ROOT:-}" ] && [ -d "$repository/.modules-source" ]; then
    modules="$repository/.modules-source"
fi
if [ ! -f "$modules/scripts/bundle_kagari.py" ]; then
    echo "utatane-modules checkout not found: $modules. Set UTATANE_MODULES_ROOT." >&2
    exit 66
fi
modules=$(CDPATH= cd -- "$modules" && pwd)
command_name=${1:-}
if [ "$#" -gt 0 ]; then shift; fi
case "$command_name" in
    bundle-kagari|check)
        uv_executable=${UTATANE_UV_EXECUTABLE:-}
        if [ -z "$uv_executable" ]; then
            uv_executable=$(command -v uv || true)
            if [ -z "$uv_executable" ]; then
                for candidate in "$HOME/.local/bin/uv" "$HOME/.cargo/bin/uv" /opt/homebrew/bin/uv /usr/local/bin/uv; do
                    if [ -x "$candidate" ]; then uv_executable=$candidate; break; fi
                done
            fi
        fi
        if [ -z "$uv_executable" ]; then echo "uv is required to build SHIORI libraries." >&2; exit 69; fi
        if [ "$command_name" = check ]; then
            cd "$modules"
            exec "$uv_executable" run --locked python -m unittest discover -s tests -v
        fi
        exec "$uv_executable" run --locked --project "$modules" python "$modules/scripts/bundle_kagari.py" "$@"
        ;;
    verify-kagari) exec sh "$modules/scripts/verify-bundled-kagari.sh" "$@" ;;
    test-kagari) exec sh "$modules/scripts/test-bundled-kagari.sh" "$repository" "$@" ;;
    *) echo "usage: $0 bundle-kagari|verify-kagari|test-kagari|check [arguments...]" >&2; exit 64 ;;
esac
