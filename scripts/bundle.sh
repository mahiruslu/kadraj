#!/usr/bin/env bash
# Builds a universal (arm64 + x86_64) Kadraj.app, signs it and zips it into dist/.
#
#   scripts/bundle.sh [--version X.Y.Z] [--build N]
#
# Env:
#   KADRAJ_SIGN_IDENTITY  codesign identity (default "-" = ad-hoc)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VERSION="$(scripts/version.sh)"
BUILD="$(git rev-list --count HEAD 2>/dev/null || echo 0)"
while [ $# -gt 0 ]; do
  case "$1" in
    --version) VERSION="$2"; shift 2 ;;
    --build) BUILD="$2"; shift 2 ;;
    *) echo "error: unknown argument: $1" >&2; exit 1 ;;
  esac
done
IDENTITY="${KADRAJ_SIGN_IDENTITY:--}"

DIST="$ROOT/dist"
APP="$DIST/Kadraj.app"
rm -rf "$DIST"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

binaries=()
for arch in arm64 x86_64; do
  scratch=".build/$arch"
  echo "==> Building $arch"
  swift build -c release --triple "$arch-apple-macosx14.0" --scratch-path "$scratch" --product Kadraj
  bin_dir="$(swift build -c release --triple "$arch-apple-macosx14.0" --scratch-path "$scratch" --show-bin-path)"
  binaries+=("$bin_dir/Kadraj")
  # SwiftPM resource bundles (identical across archs; copy once).
  if [ "$arch" = arm64 ]; then
    for bundle in "$bin_dir"/*.bundle; do
      [ -e "$bundle" ] && cp -R "$bundle" "$APP/Contents/Resources/"
    done
  fi
done

echo "==> Creating universal binary"
lipo -create "${binaries[@]}" -output "$APP/Contents/MacOS/Kadraj"

sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD/" Resources/Info.plist > "$APP/Contents/Info.plist"
[ -f Resources/AppIcon.icns ] && cp Resources/AppIcon.icns "$APP/Contents/Resources/"
cp -R Resources/*.lproj "$APP/Contents/Resources/"

echo "==> Signing with identity: $IDENTITY"
if [ "$IDENTITY" = "-" ]; then
  codesign --force --options runtime --timestamp=none --entitlements Resources/Kadraj.entitlements -s - "$APP"
else
  codesign --force --options runtime --timestamp --entitlements Resources/Kadraj.entitlements -s "$IDENTITY" "$APP"
fi

echo "==> Zipping"
(cd "$DIST" && ditto -c -k --keepParent Kadraj.app Kadraj.zip && shasum -a 256 Kadraj.zip > Kadraj.zip.sha256)
echo "==> Done: $APP ($VERSION, build $BUILD)"
