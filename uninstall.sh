#!/usr/bin/env bash
# Kadraj uninstaller — removes the app and its user data. No admin rights required.
#
#   curl -fsSL https://raw.githubusercontent.com/mahiruslu/kadraj/main/uninstall.sh | bash
#
# Environment:
#   KADRAJ_INSTALL_DIR  only look for Kadraj.app in this directory
#   KADRAJ_NO_LAUNCH=1  do not quit a running Kadraj (testing)

main() {
  set -euo pipefail
  local bundle_id="com.mahiruslu.kadraj" dirs app path warned=0

  if [ "${KADRAJ_NO_LAUNCH:-}" != 1 ]; then
    pkill -x Kadraj 2>/dev/null || true
  fi

  if [ -n "${KADRAJ_INSTALL_DIR:-}" ]; then
    dirs="$KADRAJ_INSTALL_DIR"
  else
    dirs="/Applications $HOME/Applications"
  fi

  for d in $dirs; do
    app="$d/Kadraj.app"
    [ -e "$app" ] || continue
    if rm -rf "$app" 2>/dev/null && [ ! -e "$app" ]; then
      echo "Removed $app"
    else
      echo "warning: could not remove $app — ask your administrator to delete it." >&2
      warned=1
    fi
  done

  for path in \
    "$HOME/Library/Application Support/Kadraj" \
    "$HOME/Library/Preferences/$bundle_id.plist" \
    "$HOME/Library/Caches/$bundle_id"; do
    if [ -e "$path" ]; then
      rm -rf "$path" && echo "Removed $path"
    fi
  done

  if [ $warned -eq 0 ]; then
    echo "Kadraj has been uninstalled."
  fi
}

main "$@"
