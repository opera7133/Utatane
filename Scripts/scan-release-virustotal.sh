#!/bin/bash
set -euo pipefail

file_path="${1:?Usage: scan-release-virustotal.sh /path/to/Utatane-macOS.zip}"
if [ ! -f "$file_path" ]; then
  echo "Error: $file_path not found"
  exit 1
fi

sha256=$(shasum -a 256 "$file_path" | awk '{print $1}')
vt_url="https://www.virustotal.com/gui/file/$sha256"
file_size=$(stat -f%z "$file_path" 2>/dev/null || stat -c%s "$file_path" 2>/dev/null || wc -c < "$file_path" | tr -d ' ')

echo "SHA-256: $sha256"
echo "File size: $file_size bytes"
echo "VT URL: $vt_url"

vt_status="Not scanned (VIRUSTOTAL_API_KEY not configured)"

if [ -n "$VT_API_KEY" ]; then
  echo "VIRUSTOTAL_API_KEY is present. Requesting VirusTotal scan..."

  # 32MB = 33554432 bytes
  upload_target="https://www.virustotal.com/api/v3/files"
  if [ "$file_size" -gt 33554432 ]; then
    echo "File size exceeds 32MB. Fetching large file upload URL..."
    upload_url_response=$(curl -s --request GET \
      --url "https://www.virustotal.com/api/v3/files/upload_url" \
      --header "x-apikey: $VT_API_KEY")
    upload_target=$(echo "$upload_url_response" | jq -r '.data // empty')
    if [ -z "$upload_target" ]; then
      echo "Failed to get upload URL"
      upload_target="https://www.virustotal.com/api/v3/files"
    fi
  fi

  echo "Uploading file to VirusTotal..."
  upload_res=$(curl -s --request POST \
    --url "$upload_target" \
    --header "x-apikey: $VT_API_KEY" \
    --form "file=@$file_path")

  analysis_id=$(echo "$upload_res" | jq -r '.data.id // empty')

  if [ -n "$analysis_id" ]; then
    echo "Analysis ID: $analysis_id"
    echo "Waiting for scan completion (up to 360s)..."

    completed=false
    for i in {1..24}; do
      sleep 15
      analysis_res=$(curl -s --request GET \
        --url "https://www.virustotal.com/api/v3/analyses/$analysis_id" \
        --header "x-apikey: $VT_API_KEY")

      status=$(echo "$analysis_res" | jq -r '.data.attributes.status // empty')
      echo "Check $i (elapsed $((i * 15))s): status = $status"

      if [ "$status" = "completed" ]; then
        completed=true
        malicious=$(echo "$analysis_res" | jq -r '.data.attributes.stats.malicious // 0')
        suspicious=$(echo "$analysis_res" | jq -r '.data.attributes.stats.suspicious // 0')
        undetected=$(echo "$analysis_res" | jq -r '.data.attributes.stats.undetected // 0')
        harmless=$(echo "$analysis_res" | jq -r '.data.attributes.stats.harmless // 0')
        total=$((malicious + suspicious + undetected + harmless))

        if [ "$malicious" -eq 0 ] && [ "$suspicious" -eq 0 ]; then
          vt_status="✅ Clean ($malicious / $total security vendors flagged as malicious)"
        else
          vt_status="⚠️ Flagged ($malicious / $total security vendors flagged as malicious)"
        fi
        break
      fi
    done

    if [ "$completed" = false ]; then
      vt_status="⏳ Scan queued / in progress (check report link)"
    fi
  else
    echo "Upload failed or returned unexpected response"
    vt_status="⚠️ Upload failed (check report link)"
  fi
else
  echo "VIRUSTOTAL_API_KEY secret not found. Skipping API upload."
fi

echo "VT_SHA256=$sha256" >> "$GITHUB_ENV"
echo "VT_URL=$vt_url" >> "$GITHUB_ENV"
echo "VT_STATUS=$vt_status" >> "$GITHUB_ENV"

{
  echo "### 🛡️ VirusTotal Scan Results"
  echo "- **File:** \`Utatane-macOS.zip\`"
  echo "- **Status:** $vt_status"
  echo "- **SHA-256:** \`$sha256\`"
  echo "- **Report:** [$vt_url]($vt_url)"
} >> "$GITHUB_STEP_SUMMARY"
