#!/usr/bin/env bash

set -euo pipefail

repository_root=$(cd "$(dirname "$0")/.." && pwd)
output_directory=${1:-"$repository_root/dist/validator-web"}

case "$output_directory" in
  "$repository_root"/dist/*) ;;
  *)
    echo "Output directory must be under $repository_root/dist" >&2
    exit 1
    ;;
esac

output_name=${output_directory#"$repository_root/dist/"}
if [[ "$output_name" == */* ]]; then
  echo "Output directory must be a direct child of $repository_root/dist" >&2
  exit 1
fi
archive_path="$repository_root/dist/utatane-validator-web-linux-x86_64.tar.gz"

cd "$repository_root"

swift build \
  --package-path packages \
  --configuration release \
  --static-swift-stdlib \
  --product utatane-validate

binary="$repository_root/packages/.build/x86_64-unknown-linux-gnu/release/utatane-validate"
test -x "$binary"

rm -rf "$output_directory"
mkdir -p "$output_directory/bin" "$output_directory/public_html"
cp -R "$repository_root/services/validator-web/public/." "$output_directory/public_html/"
cp -R "$repository_root/services/validator-web/src" "$output_directory/src"
cp -R "$repository_root/services/validator-web/views" "$output_directory/views"
cp -R "$repository_root/services/validator-web/licenses" "$output_directory/licenses"
cp "$repository_root/services/validator-web/README.md" "$output_directory/README.md"
install -m 755 "$binary" "$output_directory/bin/utatane-validate"
strip --strip-unneeded "$output_directory/bin/utatane-validate"

rm -f "$archive_path"
tar -C "$repository_root/dist" -czf "$archive_path" "$output_name"

echo "Validator web bundle: $output_directory"
echo "Validator web archive: $archive_path"
