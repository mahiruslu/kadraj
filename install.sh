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

# quit_running_app: terminate the current user's Kadraj and wait until it is really gone.
quit_running_app() {
  local name="${KADRAJ_PROCESS_NAME:-$APP_NAME}" uid
  uid="$(id -u)"
  pgrep -x -U "$uid" "$name" >/dev/null 2>&1 || return 0
  info "Quitting running Kadraj"
  pkill -x -U "$uid" "$name" 2>/dev/null || true
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    pgrep -x -U "$uid" "$name" >/dev/null 2>&1 || return 0
    sleep 0.5
  done
  pkill -9 -x -U "$uid" "$name" 2>/dev/null || true
  sleep 0.5
}

describe() { [ "$1" = "latest" ] && echo "the latest release" || echo "$1"; }

main() {
  set -euo pipefail
  local tag dir tmp zip_url sha_url dest stage_dir old_dir
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
  ditto -x -k "$tmp/$ZIP_NAME" "$tmp/extracted" 2>/dev/null \
    || error "Could not extract the downloaded archive. Nothing was changed."
  [ -d "$tmp/extracted/$APP_NAME.app" ] || error "Archive does not contain $APP_NAME.app"

  # Stage next to the destination so the final swap is a same-volume rename.
  # Unique names mean a stuck leftover from an earlier run can never block an install.
  stage_dir="$(mktemp -d "$dir/.$APP_NAME.new.XXXXXX")" || error "Could not write to $dir"
  # shellcheck disable=SC2064
  trap "rm -rf '$tmp' '$stage_dir'" EXIT
  ditto "$tmp/extracted/$APP_NAME.app" "$stage_dir/$APP_NAME.app" \
    || error "Could not copy Kadraj into $dir (disk full?). Nothing was changed."
  xattr -dr com.apple.quarantine "$stage_dir/$APP_NAME.app" 2>/dev/null || true

  if [ "${KADRAJ_NO_LAUNCH:-}" != 1 ]; then quit_running_app; fi

  info "Installing to $dest"
  old_dir=""
  if [ -e "$dest" ]; then
    old_dir="$(mktemp -d "$dir/.$APP_NAME.old.XXXXXX")" || error "Could not write to $dir"
    mv "$dest" "$old_dir/" || { rm -rf "$old_dir"; error "Could not replace $dest (is it writable?)"; }
  fi
  if ! mv "$stage_dir/$APP_NAME.app" "$dest"; then
    [ -n "$old_dir" ] && mv "$old_dir/$APP_NAME.app" "$dest"
    error "Could not move Kadraj into $dir"
  fi
  if [ -n "$old_dir" ] && ! rm -rf "$old_dir" 2>/dev/null; then
    printf '%s    note: could not fully remove the previous copy at %s%s\n' "$DIM" "$old_dir" "$RESET"
  fi

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
