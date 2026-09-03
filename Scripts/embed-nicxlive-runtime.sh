#!/bin/sh

set -eu

if [ -z "${UTATANE_NICXLIVE_RUNTIME_LIBRARY:-}" ]; then
    exit 0
fi

library_source=$UTATANE_NICXLIVE_RUNTIME_LIBRARY
license_source=${UTATANE_NICXLIVE_RUNTIME_LICENSE:-}

if [ ! -f "$library_source" ]; then
    echo "nicxlive library not found: $library_source" >&2
    exit 66
fi
if [ -z "$license_source" ] || [ ! -f "$license_source" ]; then
    echo "UTATANE_NICXLIVE_RUNTIME_LICENSE must point to the nicxlive BSD license" >&2
    exit 66
fi

architectures=$(lipo -archs "$library_source")
case " $architectures " in
    *" arm64 "*) ;;
    *) echo "nicxlive runtime is missing arm64: $architectures" >&2; exit 65 ;;
esac
case " $architectures " in
    *" x86_64 "*) ;;
    *) echo "nicxlive runtime is missing x86_64: $architectures" >&2; exit 65 ;;
esac

frameworks_directory="$TARGET_BUILD_DIR/$FRAMEWORKS_FOLDER_PATH"
licenses_directory="$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH/Licenses/nicxlive"
mkdir -p "$frameworks_directory" "$licenses_directory"
install -m 755 "$library_source" "$frameworks_directory/libnicxlive.dylib"
install -m 644 "$license_source" "$licenses_directory/LICENSE"

codesign --force --sign - "$frameworks_directory/libnicxlive.dylib"
