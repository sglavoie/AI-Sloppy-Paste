#!/bin/bash
# Publish the exact archive prepared by release.sh, then update the Homebrew tap.
# TAP_DIR overrides the sibling sglavoie_homebrew-tap clone.
# Re-running after a partial failure verifies the existing asset before continuing.
set -euo pipefail
cd "$(dirname "$0")/.."

out=.build/release
app="$out/AI Sloppy Paste.app"
archive="$out/AI-Sloppy-Paste.zip"
tap="${TAP_DIR:-../sglavoie_homebrew-tap}"
repo=sglavoie/AI-Sloppy-Paste
cask=Casks/sloppy-paste.rb

[[ -f "$archive" && -f "$out/COMMIT" && -f "$out/sloppy-paste.rb" ]] || {
    echo "No prepared release; run just release first." >&2; exit 1;
}
[[ -z "$(git status --porcelain)" ]] || { echo "Commit or stash source changes first." >&2; exit 1; }
commit="$(cat "$out/COMMIT")"
[[ "$(git rev-parse HEAD)" == "$commit" ]] || { echo "HEAD differs from the release build; rebuild." >&2; exit 1; }
(cd "$out" && shasum -a 256 -c SHA256SUMS)
xcrun stapler validate "$app"
codesign --verify --deep --strict "$app"
version="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$app/Contents/Info.plist")"
sha="$(shasum -a 256 "$archive" | cut -d' ' -f1)"
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
sed -e "s/@VERSION@/$version/" -e "s/@SHA256@/$sha/" \
    Resources/homebrew-cask.rb.in > "$scratch/sloppy-paste.rb"
cmp "$scratch/sloppy-paste.rb" "$out/sloppy-paste.rb"

[[ -d "$tap/.git" ]] || { echo "Set TAP_DIR to your homebrew-tap clone." >&2; exit 1; }
[[ -z "$(git -C "$tap" status --porcelain)" ]] || { echo "Commit or stash tap changes first." >&2; exit 1; }
[[ "$(git -C "$tap" branch --show-current)" == main ]] || { echo "Switch the tap to main first." >&2; exit 1; }
case "$(git -C "$tap" remote get-url origin)" in
    git@github.com:sglavoie/homebrew-tap.git|https://github.com/sglavoie/homebrew-tap.git) ;;
    *) echo "TAP_DIR must point to sglavoie/homebrew-tap." >&2; exit 1 ;;
esac
git -C "$tap" pull --ff-only
# Literal Markdown backticks, not shell substitutions.
# shellcheck disable=SC2016
if ! grep -Fq '| `sloppy-paste` |' "$tap/README.md"; then
    echo "Add AI Sloppy Paste to the tap README (Cask and Updated by tables) and commit first." >&2
    exit 1
fi
# Homebrew selects its cask-specific style rules by the Casks/ path.
mkdir "$scratch/Casks"
cp "$out/sloppy-paste.rb" "$scratch/Casks/sloppy-paste.rb"
brew style "$scratch/Casks/sloppy-paste.rb"
git fetch -q origin
git merge-base --is-ancestor "$commit" origin/main || { echo "Push $commit to origin/main first." >&2; exit 1; }

notes="${1:-AI Sloppy Paste $version. Signed and notarized for macOS 15+, Apple silicon and Intel. Includes sloppyctl. Install: brew install --cask sglavoie/tap/sloppy-paste}"
if gh release view "v$version" --repo "$repo" >/dev/null 2>&1; then
    gh release download "v$version" --repo "$repo" --pattern AI-Sloppy-Paste.zip --dir "$scratch"
    remote_sha="$(shasum -a 256 "$scratch/AI-Sloppy-Paste.zip" | cut -d' ' -f1)"
    [[ "$remote_sha" == "$sha" ]] || { echo "Existing release has a different archive; bump the version." >&2; exit 1; }
    echo "Release already contains this archive; continuing with the tap."
else
    gh release create "v$version" "$archive" "$out/SHA256SUMS" --repo "$repo" \
        --target "$commit" --title "AI Sloppy Paste $version" --notes "$notes"
fi

cp "$out/sloppy-paste.rb" "$tap/$cask"
git -C "$tap" add "$cask"
if ! git -C "$tap" diff --cached --quiet -- "$cask"; then
    git -C "$tap" commit -m "sloppy-paste $version" -- "$cask"
fi
git -C "$tap" push origin main
echo "Published v$version. Install with: brew install --cask sglavoie/tap/sloppy-paste"
