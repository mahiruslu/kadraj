#!/usr/bin/env bash
# Fast development loop: debug build (host arch), bundle into dist-dev/Kadraj.app, sign, relaunch.
#
# Signing with a stable identity (Developer ID or Apple Development certificate) keeps the
# Screen Recording permission across rebuilds; ad-hoc signatures change every build.
#
# Env: KADRAJ_SIGN_IDENTITY  override the signing identity ("-" for ad-hoc)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

identity="${KADRAJ_SIGN_IDENTITY:-}"
if [ -z "$identity" ]; then
  # Prefer Developer ID (same identity as releases, so the permission is shared), then Apple Development.
  ids="$(security find-identity -v -p codesigning 2>/dev/null)"
  identity="$(echo "$ids" | sed -n 's/.*"\(Developer ID Application: [^"]*\)".*/\1/p' | head -1)"
  [ -n "$identity" ] || identity="$(echo "$ids" | sed -n 's/.*"\(Apple Development: [^"]*\)".*/\1/p' | head -1)"
fi
identity="${identity:--}"

swift build --product Kadraj --scratch-path .build/dev
bin_dir="$(swift build --product Kadraj --scratch-path .build/dev --show-bin-path)"

APP="$ROOT/dist-dev/Kadraj.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$bin_dir/Kadraj" "$APP/Contents/MacOS/Kadraj"
for bundle in "$bin_dir"/*.bundle; do
  [ -e "$bundle" ] && cp -R "$bundle" "$APP/Contents/Resources/"
done
cp Resources/AppIcon.icns "$APP/Contents/Resources/"
cp -R Resources/*.lproj "$APP/Contents/Resources/"
sed -e "s/__VERSION__/0.0.0-dev/" -e "s/__BUILD__/0/" Resources/Info.plist > "$APP/Contents/Info.plist"
codesign --force --options runtime --timestamp=none -s "$identity" "$APP"
echo "==> Signed with: $identity"

pkill -x Kadraj 2>/dev/null || true
sleep 0.5
open "$APP"
echo "==> Running $APP"
