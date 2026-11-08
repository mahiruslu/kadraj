#!/usr/bin/env bash
# Kadraj installer — no admin rights, Homebrew or Xcode required.
#
#   curl -fsSL https://raw.githubusercontent.com/mahiruslu/kadraj/main/install.sh | bash
#   curl -fsSL https://raw.githubusercontent.com/mahiruslu/kadraj/main/install.sh | bash -s -- 1.2.0
#   curl -fsSL https://raw.githubusercontent.com/mahiruslu/kadraj/main/install.sh | bash -s -- main
#
# Environment:
#   KADRAJ_INSTALL_DIR  install location (default: /Applications if writable, else ~/Applications)
#   KADRAJ_REPO         GitHub repo (default: mahiruslu/kadraj)
#   KADRAJ_BASE_URL     alternative download root: <base>/<tag>/Kadraj.zip (for testing/mirrors)
#   KADRAJ_NO_LAUNCH=1  do not quit the running app or launch the new one
#
# Everything is wrapped in functions and main runs on the last line, so a truncated
# download never executes a partial script.

APP_NAME="Kadraj"
ZIP_NAME="Kadraj.zip"
MIN_MACOS_MAJOR=14

if [ -t 1 ]; then
  BOLD=$'\033[1m'; GREEN=$'\033[32m'; RED=$'\033[31m'; DIM=$'\033[2m'; RESET=$'\033[0m'
else
  BOLD=""; GREEN=""; RED=""; DIM=""; RESET=""
fi

info() { printf '%s==>%s %s\n' "$BOLD" "$RESET" "$*"; }
error() { printf '%serror:%s %s\n' "$RED" "$RESET" "$*" >&2; exit 1; }

# resolve_tag <arg>: "" | latest -> latest, main -> nightly, [vV]X.Y.Z -> vX.Y.Z
resolve_tag() {
  case "${1:-}" in
    "" | latest) echo "latest" ;;
    main | nightly) echo "nightly" ;;
    v* | V*) echo "v${1#?}" ;;
    *) echo "v$1" ;;
  esac
}

# download_url <tag> <file>
download_url() {
  local tag="$1" file="$2" repo="${KADRAJ_REPO:-mahiruslu/kadraj}"
  if [ -n "${KADRAJ_BASE_URL:-}" ]; then
    echo "${KADRAJ_BASE_URL%/}/$tag/$file"
  elif [ "$tag" = "latest" ]; then
    echo "https://github.com/$repo/releases/latest/download/$file"
  else
    echo "https://github.com/$repo/releases/download/$tag/$file"
  fi
}

pick_install_dir() {
  if [ -n "${KADRAJ_INSTALL_DIR:-}" ]; then
    mkdir -p "$KADRAJ_INSTALL_DIR" || return 1
    echo "$KADRAJ_INSTALL_DIR"
    return
  fi
  local system_apps="${KADRAJ_SYSTEM_APPS:-/Applications}"
  if [ -d "$system_apps" ] && [ -w "$system_apps" ]; then
    echo "$system_apps"
  else
    mkdir -p "$HOME/Applications" || return 1
    echo "$HOME/Applications"
  fi
}

check_macos() {
  [ "$(uname -s)" = "Darwin" ] || error "Kadraj only runs on macOS."
  local version major
  version="$(sw_vers -productVersion)"
  major="${version%%.*}"
  if [ "$major" -lt "$MIN_MACOS_MAJOR" ]; then
    error "Kadraj requires macOS $MIN_MACOS_MAJOR or later (you have $version)."
  fi
}

describe() { [ "$1" = "latest" ] && echo "the latest release" || echo "$1"; }

main() {
  set -euo pipefail
  local tag dir tmp zip_url sha_url dest staged
  tag="$(resolve_tag "${1:-}")"
  if [ -z "${KADRAJ_BASE_URL:-}" ]; then check_macos; fi
  dir="$(pick_install_dir)" || error "Could not create install directory."
  dest="$dir/$APP_NAME.app"

  tmp="$(mktemp -d)"
  # shellcheck disable=SC2064
  trap "rm -rf '$tmp'" EXIT

  zip_url="$(download_url "$tag" "$ZIP_NAME")"
  sha_url="$(download_url "$tag" "$ZIP_NAME.sha256")"

  info "Downloading Kadraj ($(describe "$tag"))"
  printf '%s    %s%s\n' "$DIM" "$zip_url" "$RESET"
  curl -fsSL "$zip_url" -o "$tmp/$ZIP_NAME" \
    || error "Could not download Kadraj $(describe "$tag"). Does this release exist? ($zip_url)"
  curl -fsSL "$sha_url" -o "$tmp/$ZIP_NAME.sha256" \
    || error "Could not download the checksum for Kadraj $(describe "$tag") ($sha_url)"

  info "Verifying checksum"
  (cd "$tmp" && shasum -a 256 -c "$ZIP_NAME.sha256" >/dev/null 2>&1) \
    || error "checksum mismatch — the download may be corrupted. Nothing was changed."

  info "Extracting"
  ditto -x -k "$tmp/$ZIP_NAME" "$tmp/extracted"
  [ -d "$tmp/extracted/$APP_NAME.app" ] || error "Archive does not contain $APP_NAME.app"

  # Stage next to the destination so the final swap is a same-volume rename.
  staged="$dir/.$APP_NAME.app.new"
  rm -rf "$staged"
  ditto "$tmp/extracted/$APP_NAME.app" "$staged"
  xattr -dr com.apple.quarantine "$staged" 2>/dev/null || true

  if [ "${KADRAJ_NO_LAUNCH:-}" != 1 ] && pgrep -x "$APP_NAME" >/dev/null 2>&1; then
    info "Quitting running Kadraj"
    pkill -x "$APP_NAME" || true
    sleep 1
  fi

  info "Installing to $dest"
  rm -rf "$dest.old"
  if [ -e "$dest" ]; then
    mv "$dest" "$dest.old" || { rm -rf "$staged"; error "Could not replace $dest (is it writable?)"; }
  fi
  if ! mv "$staged" "$dest"; then
    [ -e "$dest.old" ] && mv "$dest.old" "$dest"
    rm -rf "$staged"
    error "Could not move Kadraj into $dir"
  fi
  rm -rf "$dest.old"

  printf '%s✓ Kadraj installed:%s %s\n' "$GREEN" "$RESET" "$dest"
  if [ "${KADRAJ_NO_LAUNCH:-}" != 1 ]; then
    open "$dest"
    echo "  Look for the viewfinder icon in the menu bar."
    echo "  On first launch macOS will ask for Screen Recording permission."
  fi
}

if [ "${KADRAJ_SOURCE_ONLY:-}" != 1 ]; then
  main "$@"
fi
