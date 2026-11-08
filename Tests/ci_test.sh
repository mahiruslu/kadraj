#!/usr/bin/env bash
# Tests for the CI signing scripts: the official repo must never ship ad-hoc builds.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
FAILED=0
pass() { echo "pass: $1"; }
fail() { echo "FAIL: $1 — $2"; FAILED=1; }
run() { env -i PATH="$PATH" HOME="$TMP" RUNNER_TEMP="$TMP" GITHUB_ENV="$TMP/env" "$@" >/dev/null 2>&1; }

if run KADRAJ_REQUIRE_SIGNING=1 bash "$ROOT/scripts/ci-import-cert.sh"; then fail "import fails without p12" "exit 0"; else pass "import fails without p12 when signing required"; fi

if run KADRAJ_REQUIRE_SIGNING=1 DEVELOPER_ID_P12=Zm9v DEVELOPER_ID_P12_PASSWORD=x DEVELOPER_ID_NAME= bash "$ROOT/scripts/ci-import-cert.sh"; then fail "import fails with empty identity name" "exit 0"; else pass "import fails with empty identity name"; fi

if run DEVELOPER_ID_P12=Zm9v DEVELOPER_ID_P12_PASSWORD=x DEVELOPER_ID_NAME= bash "$ROOT/scripts/ci-import-cert.sh"; then fail "import fails with empty identity name (fork)" "exit 0"; else pass "import fails with empty identity name (fork)"; fi

if run bash "$ROOT/scripts/ci-import-cert.sh"; then pass "fork without secrets falls back to ad-hoc"; else fail "fork falls back to ad-hoc" "non-zero exit"; fi

if run KADRAJ_REQUIRE_SIGNING=1 KADRAJ_SIGN_IDENTITY="Developer ID Application: X" bash "$ROOT/scripts/notarize.sh"; then fail "notarize fails without key" "exit 0"; else pass "notarize fails without key when signing required"; fi
if run bash "$ROOT/scripts/notarize.sh"; then pass "fork notarize skipped"; else fail "fork notarize skipped" "non-zero exit"; fi

exit $FAILED
