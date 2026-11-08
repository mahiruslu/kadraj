#!/usr/bin/env bash
# Tests for install.sh / uninstall.sh. Uses file:// fixtures, so no network or HTTP server is needed.
# Runs under macOS's /bin/bash 3.2.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'chmod -R u+w "$TMP" 2>/dev/null; rm -rf "$TMP"' EXIT
FIX="$TMP/fixtures"
FAILED=0

pass() { echo "pass: $1"; }
fail() { echo "FAIL: $1 — $2"; FAILED=1; }
# expect <name> <failure detail> <test command...>
expect() {
  local name="$1" detail="$2"; shift 2
  if "$@"; then pass "$name"; else fail "$name" "$detail"; fi
}

# make_release <dir> <marker>: fake Kadraj.app zip + sha256 in $FIX/<dir>
make_release() {
  local dir="$FIX/$1" stage="$TMP/stage-$1"
  mkdir -p "$dir" "$stage/Kadraj.app/Contents"
  echo "<plist/>" > "$stage/Kadraj.app/Contents/Info.plist"
  echo "$2" > "$stage/Kadraj.app/marker"
  (cd "$stage" && ditto -c -k --keepParent Kadraj.app "$dir/Kadraj.zip")
  (cd "$dir" && shasum -a 256 Kadraj.zip > Kadraj.zip.sha256)
}

make_release v1.2.0 1.2.0
make_release latest latest
make_release nightly nightly
make_release vbad bad
echo "0000000000000000000000000000000000000000000000000000000000000000  Kadraj.zip" > "$FIX/vbad/Kadraj.zip.sha256"

APPS="$TMP/apps"
run_install() {
  KADRAJ_BASE_URL="file://$FIX" KADRAJ_NO_LAUNCH=1 KADRAJ_INSTALL_DIR="$APPS" \
    bash "$ROOT/install.sh" "$@"
}
marker() { cat "$APPS/Kadraj.app/marker" 2>/dev/null || echo "<none>"; }

# --- resolve_tag / download_url (sourced) ---
# shellcheck source=/dev/null
KADRAJ_SOURCE_ONLY=1 . "$ROOT/install.sh"

check_tag() {
  local got
  got="$(resolve_tag "$1")"
  expect "resolve_tag '$1' -> $2" "got '$got', want '$2'" [ "$got" = "$2" ]
}
check_tag "" latest
check_tag latest latest
check_tag main nightly
check_tag 1.2.0 v1.2.0
check_tag v1.2.0 v1.2.0
check_tag V1.2.0 v1.2.0

got="$(KADRAJ_BASE_URL='' download_url latest Kadraj.zip)"
want="https://github.com/mahiruslu/kadraj/releases/latest/download/Kadraj.zip"
expect "download_url latest" "got $got" [ "$got" = "$want" ]
got="$(KADRAJ_BASE_URL='' download_url v1.2.0 Kadraj.zip)"
want="https://github.com/mahiruslu/kadraj/releases/download/v1.2.0/Kadraj.zip"
expect "download_url version" "got $got" [ "$got" = "$want" ]

# --- pick_install_dir fallback ---
got="$(HOME="$TMP/home" KADRAJ_INSTALL_DIR='' pick_install_dir)"
if [ -w /Applications ]; then
  expect "install dir uses writable /Applications" "got $got" [ "$got" = "/Applications" ]
else
  if [ "$got" = "$TMP/home/Applications" ] && [ -d "$TMP/home/Applications" ]; then pass "install dir falls back to home"; else fail "install dir falls back to home" "got $got"; fi
fi
# Force the fallback branch regardless of this machine's permissions.
got="$(HOME="$TMP/home2" KADRAJ_INSTALL_DIR='' KADRAJ_SYSTEM_APPS="$TMP/readonly" pick_install_dir)"
if [ "$got" = "$TMP/home2/Applications" ] && [ -d "$TMP/home2/Applications" ]; then pass "install dir falls back to home (forced)"; else fail "install dir falls back to home (forced)" "got $got"; fi

# --- end-to-end installs ---
run_install 1.2.0 >/dev/null 2>&1
expect "installs specific version" "marker $(marker)" [ "$(marker)" = "1.2.0" ]

run_install main >/dev/null 2>&1
expect "installs main" "marker $(marker)" [ "$(marker)" = "nightly" ]

run_install 1.2.0 >/dev/null 2>&1
run_install >/dev/null 2>&1
if [ "$(marker)" = "latest" ] && [ ! -e "$APPS/Kadraj.app.old" ]; then
  pass "reinstall replaces existing app"
else
  fail "reinstall replaces existing app" "marker $(marker)"
fi

run_install 1.2.0 >/dev/null 2>&1
err="$(run_install bad 2>&1 >/dev/null)"; code=$?
if [ $code -ne 0 ] && echo "$err" | grep -qi checksum && [ "$(marker)" = "1.2.0" ]; then
  pass "checksum mismatch keeps old app"
else
  fail "checksum mismatch keeps old app" "code=$code marker=$(marker) err=$err"
fi

err="$(run_install 9.9.9 2>&1 >/dev/null)"; code=$?
if [ $code -ne 0 ] && echo "$err" | grep -q "9.9.9" && [ "$(marker)" = "1.2.0" ]; then
  pass "missing release fails clearly"
else
  fail "missing release fails clearly" "code=$code err=$err"
fi

rm -rf "$APPS"
KADRAJ_BASE_URL="file://$FIX" KADRAJ_NO_LAUNCH=1 KADRAJ_INSTALL_DIR="$APPS" \
  bash -s -- 1.2.0 < "$ROOT/install.sh" >/dev/null 2>&1
expect "piped install works" "marker $(marker)" [ "$(marker)" = "1.2.0" ]

if grep -n 'sudo' "$ROOT/install.sh" "$ROOT/uninstall.sh" | grep -v '#' | grep -q .; then
  fail "no sudo" "$(grep -n sudo "$ROOT/install.sh" "$ROOT/uninstall.sh")"
else
  pass "no sudo"
fi

# --- undeletable leftovers must not block installs ---
rm -rf "$APPS"; mkdir -p "$APPS/Kadraj.app.old/locked"; touch "$APPS/Kadraj.app.old/locked/f"; chmod 555 "$APPS/Kadraj.app.old/locked"
run_install 1.2.0 >/dev/null 2>&1; code=$?
expect "stuck old copy does not block install" "code=$code marker=$(marker)" [ $code -eq 0 ] && [ "$(marker)" = "1.2.0" ]

mkdir -p "$APPS/Kadraj.app/locked"; touch "$APPS/Kadraj.app/locked/f"; chmod 555 "$APPS/Kadraj.app/locked"
run_install >/dev/null 2>&1; code=$?
expect "undeletable previous app still upgrades" "code=$code marker=$(marker)" [ $code -eq 0 ] && [ "$(marker)" = "latest" ]
chmod -R u+w "$APPS"

# --- running app is really quit before the swap ---
mkdir -p "$TMP/bin"; cp /bin/sleep "$TMP/bin/kadrajtestproc"; codesign -f -s - "$TMP/bin/kadrajtestproc" 2>/dev/null
"$TMP/bin/kadrajtestproc" 60 &
disown
sleep 0.3
pgrep -x kadrajtestproc >/dev/null || fail "quits running app" "test process did not start"
# shellcheck source=/dev/null
( KADRAJ_SOURCE_ONLY=1 . "$ROOT/install.sh"; KADRAJ_PROCESS_NAME=kadrajtestproc quit_running_app ) >/dev/null 2>&1
if pgrep -x kadrajtestproc >/dev/null; then fail "quits running app" "process still alive"; pkill -9 -x kadrajtestproc; else pass "quits running app"; fi

# --- uninstall ---
KADRAJ_INSTALL_DIR="$APPS" KADRAJ_NO_LAUNCH=1 HOME="$TMP/home" bash "$ROOT/uninstall.sh" >/dev/null 2>&1
expect "uninstall removes app" "still exists" [ ! -e "$APPS/Kadraj.app" ]

exit $FAILED
