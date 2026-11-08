#!/usr/bin/env bash
# Notarizes dist/Kadraj.app, staples the ticket and re-creates the zip + checksum.
#
#   scripts/notarize.sh
#
# Env (GitHub secrets): NOTARY_KEY_ID, NOTARY_ISSUER_ID, NOTARY_KEY_P8 (base64)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST="$ROOT/dist"

if [ -z "${NOTARY_KEY_P8:-}" ] || [ -z "${KADRAJ_SIGN_IDENTITY:-}" ]; then
  echo "::warning::Notarization skipped (no notary key or Developer ID identity)."
  exit 0
fi

: "${NOTARY_KEY_ID:?NOTARY_KEY_ID is required}" "${NOTARY_ISSUER_ID:?NOTARY_ISSUER_ID is required}"

KEY_DIR="$(mktemp -d)"
KEY_FILE="$KEY_DIR/AuthKey.p8"
trap 'rm -rf "$KEY_DIR"' EXIT
echo "$NOTARY_KEY_P8" | base64 --decode > "$KEY_FILE"

echo "==> Submitting for notarization"
xcrun notarytool submit "$DIST/Kadraj.zip" \
  --key "$KEY_FILE" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER_ID" --wait

echo "==> Stapling"
xcrun stapler staple "$DIST/Kadraj.app"
xcrun stapler validate "$DIST/Kadraj.app"

echo "==> Re-zipping stapled app"
rm -f "$DIST/Kadraj.zip" "$DIST/Kadraj.zip.sha256"
(cd "$DIST" && ditto -c -k --keepParent Kadraj.app Kadraj.zip && shasum -a 256 Kadraj.zip > Kadraj.zip.sha256)
