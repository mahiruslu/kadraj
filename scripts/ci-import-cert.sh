#!/usr/bin/env bash
# CI only: imports the Developer ID certificate into a temporary keychain and
# exports KADRAJ_SIGN_IDENTITY for scripts/bundle.sh.
#
# Env (GitHub secrets): DEVELOPER_ID_P12 (base64), DEVELOPER_ID_P12_PASSWORD, DEVELOPER_ID_NAME
set -euo pipefail

if [ -z "${DEVELOPER_ID_P12:-}" ]; then
  echo "::warning::DEVELOPER_ID_P12 not set — building with an ad-hoc signature (not notarized)."
  exit 0
fi

KEYCHAIN="$RUNNER_TEMP/kadraj-signing.keychain-db"
KEYCHAIN_PASSWORD="$(uuidgen)"
P12="$RUNNER_TEMP/developer-id.p12"

echo "$DEVELOPER_ID_P12" | base64 --decode > "$P12"
security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
security set-keychain-settings -lut 21600 "$KEYCHAIN"
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
security import "$P12" -P "$DEVELOPER_ID_P12_PASSWORD" -A -t cert -f pkcs12 -k "$KEYCHAIN"
security set-key-partition-list -S apple-tool:,apple: -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN" >/dev/null
# shellcheck disable=SC2046
security list-keychains -d user -s "$KEYCHAIN" $(security list-keychains -d user | tr -d '"')
rm -f "$P12"

echo "KADRAJ_SIGN_IDENTITY=$DEVELOPER_ID_NAME" >> "$GITHUB_ENV"
echo "Imported signing identity: $DEVELOPER_ID_NAME"
