#!/usr/bin/env bash
# Writes the Homebrew cask for a release and pushes it to mahiruslu/homebrew-kadraj.
#
#   scripts/update-homebrew-tap.sh VERSION SHA256           # used by the release workflow
#   scripts/update-homebrew-tap.sh VERSION SHA256 --print   # just print the cask
#
# Env: TAP_DEPLOY_KEY  private SSH deploy key with write access to the tap repository.
#                      Without it (forks, local runs) the push is skipped.
set -euo pipefail

version="${1:?version}"
sha="${2:?sha256}"
mode="${3:-}"

cask() {
  cat <<EOF
cask "kadraj" do
  version "$version"
  sha256 "$sha"

  url "https://github.com/mahiruslu/kadraj/releases/download/v#{version}/Kadraj.zip"
  name "Kadraj"
  desc "Screenshot tool with annotation, OCR, scrolling capture and recording"
  homepage "https://github.com/mahiruslu/kadraj"

  livecheck do
    url :url
    strategy :github_latest
  end

  # Kadraj updates itself from the menu (and checks daily), so brew leaves upgrades to it.
  auto_updates true
  depends_on macos: ">= :sonoma"

  app "Kadraj.app"

  uninstall quit: "com.mahiruslu.kadraj"

  zap trash: [
    "~/Library/Application Support/Kadraj",
    "~/Library/Caches/com.mahiruslu.kadraj",
    "~/Library/Preferences/com.mahiruslu.kadraj.plist",
  ]
end
EOF
}

if [ "$mode" = "--print" ]; then
  cask
  exit 0
fi

if [ -z "${TAP_DEPLOY_KEY:-}" ]; then
  echo "::warning::HOMEBREW_TAP_DEPLOY_KEY is not set; the Homebrew tap was not updated."
  exit 0
fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
printf '%s\n' "$TAP_DEPLOY_KEY" > "$work/key"
chmod 600 "$work/key"
export GIT_SSH_COMMAND="ssh -i $work/key -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new"

git clone --depth 1 git@github.com:mahiruslu/homebrew-kadraj.git "$work/tap"
mkdir -p "$work/tap/Casks"
cask > "$work/tap/Casks/kadraj.rb"
cd "$work/tap"
git add Casks/kadraj.rb
if git diff --cached --quiet; then
  echo "Cask already at $version."
  exit 0
fi
git -c user.name="github-actions[bot]" -c user.email="41898282+github-actions[bot]@users.noreply.github.com" \
  commit -m "kadraj $version"
git push origin HEAD
echo "Homebrew tap updated to $version."
