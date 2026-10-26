#!/bin/bash
set -euo pipefail

# Secrets are supplied through Actions env, never written into release artifacts.
: "${APPLE_ID:?Missing APPLE_ID}"
: "${APPLE_APP_PASSWORD:?Missing APPLE_APP_PASSWORD}"
: "${APPLE_TEAM_ID:?Missing APPLE_TEAM_ID}"
: "${RUNNER_TEMP:?Missing RUNNER_TEMP}"

keychain_path="$RUNNER_TEMP/utatane-signing.keychain-db"
keychain_password=$(openssl rand -base64 32)
security create-keychain -p "$keychain_password" "$keychain_path"
security set-keychain-settings -lut 3600 "$keychain_path"
security unlock-keychain -p "$keychain_password" "$keychain_path"
security list-keychains -d user -s "$keychain_path"
echo "UTATANE_SIGNING_KEYCHAIN=$keychain_path" >> "$GITHUB_ENV"

if [[ "${UTATANE_NOTARY_ONLY:-0}" != 1 ]]; then
  : "${APPLE_CERTIFICATE_P12_BASE64:?Missing APPLE_CERTIFICATE_P12_BASE64}"
  : "${APPLE_CERTIFICATE_PASSWORD:?Missing APPLE_CERTIFICATE_PASSWORD}"
  certificate_path="$RUNNER_TEMP/utatane-developer-id.p12"
  umask 077
  printf '%s' "$APPLE_CERTIFICATE_P12_BASE64" | base64 --decode > "$certificate_path"
  security import "$certificate_path" -k "$keychain_path" -P "$APPLE_CERTIFICATE_PASSWORD" -T /usr/bin/codesign -T /usr/bin/security >/dev/null
  rm -f "$certificate_path"
  security set-key-partition-list -S apple-tool:,apple: -k "$keychain_password" "$keychain_path" >/dev/null
  python3 - <<'PY'
import os,re,subprocess
text=subprocess.check_output(['security','find-identity','-v','-p','codesigning'],text=True)
matches=[digest for digest,name in re.findall(r'([0-9A-F]{40}) "(Developer ID Application: [^\"]+)"',text) if name.endswith('('+os.environ['APPLE_TEAM_ID']+')')]
if len(matches)!=1:raise SystemExit('Expected exactly one Developer ID Application identity for APPLE_TEAM_ID')
with open(os.environ['GITHUB_ENV'],'a') as output:output.write('UTATANE_SIGN_IDENTITY='+matches[0]+'\n')
PY
fi

xcrun notarytool store-credentials utatane-ci \
  --apple-id "$APPLE_ID" --password "$APPLE_APP_PASSWORD" \
  --team-id "$APPLE_TEAM_ID" --keychain "$keychain_path" >/dev/null
