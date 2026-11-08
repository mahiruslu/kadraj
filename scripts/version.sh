#!/usr/bin/env bash
# Prints the app version derived from the latest v* git tag (without the leading v).
set -euo pipefail
tag="$(git describe --tags --match 'v*' --abbrev=0 2>/dev/null || true)"
if [ -n "$tag" ]; then
  echo "${tag#v}"
else
  echo "0.0.0-dev"
fi
