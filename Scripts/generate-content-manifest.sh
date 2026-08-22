#!/usr/bin/env bash

set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "usage: $0 CONTENT_DIRECTORY OUTPUT_FILE" >&2
  exit 64
fi

content_directory=$1
output_file=$2

if [[ ! -d "$content_directory" ]]; then
  echo "content directory not found: $content_directory" >&2
  exit 66
fi

hash_file() {
  if command -v md5 >/dev/null 2>&1; then
    md5 -q "$1"
  else
    md5sum "$1" | awk '{print $1}'
  fi
}

temporary_file=$(mktemp)
trap 'rm -f "$temporary_file"' EXIT

while IFS= read -r -d '' file; do
  relative_path=${file#"$content_directory"/}
  checksum=$(hash_file "$file")
  printf '%s\001%s\001\n' "$relative_path" "$checksum" >> "$temporary_file"
done < <(
  find "$content_directory" -type f \
    ! -name '.DS_Store' \
    ! -name '*_variable.cfg' \
    ! -name 'updates2.dau' \
    ! -name 'updates.txt' \
    ! -name '*.tmp' \
    ! -name '*.bak' \
    -print0 \
    | LC_ALL=C sort -z
)

mkdir -p "$(dirname "$output_file")"
cp "$temporary_file" "$output_file"
