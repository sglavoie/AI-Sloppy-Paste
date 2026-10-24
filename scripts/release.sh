#!/bin/bash
# Build a tested, universal, Developer ID signed and notarized release.
# SIGN_IDENTITY: certificate hash (defaults to the only Developer ID Application).
# NOTARY_PROFILE: notarytool keychain profile (defaults to the existing launchgrid
# account profile). To create another profile, run:
#   xcrun notarytool store-credentials sloppy-paste --apple-id … --team-id …
set -euo pipefail
cd "$(dirname "$0")/.."

out=.build/release
app="$out/SloppyPaste.app"
archive="$out/SloppyPaste.zip"
profile="${NOTARY_PROFILE:-launchgrid}"
version="$(sed -n 's/.*static let version = "\(.*\)".*/\1/p' Sources/SloppyCore/SloppyCore.swift)"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "Invalid release version: $version" >&2; exit 1; }
[[ -z "$(git status --porcelain)" ]] || { echo "Commit or stash changes before releasing." >&2; exit 1; }
gh auth status >/dev/null
if gh release view "v$version" >/dev/null 2>&1; then
    echo "v$version already exists; bump SloppyCore.version before building another release." >&2
    exit 1
fi

identity="${SIGN_IDENTITY:-}"
if [[ -z "$identity" ]]; then
    identity="$(security find-identity -v -p codesigning | sed -n 's/.*) \([0-9A-F]\{40\}\) "Developer ID Application: .*/\1/p' | sort -u)"
    [[ "$identity" =~ ^[0-9A-F]{40}$ ]] || { echo "Set SIGN_IDENTITY to one Developer ID Application certificate hash." >&2; exit 1; }
fi
# Fail before building if the account profile is unavailable. No credentials are printed.
xcrun notarytool history --keychain-profile "$profile" --output-format json >/dev/null
swift test
UNIVERSAL=1 just bundle

rm -rf "$out"
mkdir -p "$out"
ditto .build/bundle/SloppyPaste.app "$app"
for executable in SloppyPaste sloppyctl; do
    lipo -verify_arch arm64 x86_64 "$app/Contents/MacOS/$executable"
done
codesign --force --options runtime --timestamp --sign "$identity" "$app/Contents/MacOS/sloppyctl"
codesign --force --options runtime --timestamp --sign "$identity" "$app"
codesign --verify --deep --strict --verbose=2 "$app"
"$app/Contents/MacOS/sloppyctl" --version
ditto -c -k --keepParent "$app" "$archive"
git rev-parse HEAD > "$out/COMMIT"

if ! xcrun notarytool submit "$archive" --keychain-profile "$profile" --wait \
    --output-format json > "$out/notarization.json"; then
    cat "$out/notarization.json"
    echo "Notarization failed; use the submission ID with notarytool log." >&2
    exit 1
fi
cat "$out/notarization.json"
grep -Eq '"status"[[:space:]]*:[[:space:]]*"Accepted"' "$out/notarization.json" || exit 1
attempt=0
until xcrun stapler staple "$app"; do
    attempt=$((attempt + 1))
    [[ "$attempt" -lt 5 ]] || exit 1
    sleep 15
done
xcrun stapler validate "$app"
spctl --assess --type execute --verbose "$app"
rm "$archive"
ditto -c -k --keepParent "$app" "$archive"
(cd "$out" && shasum -a 256 SloppyPaste.zip > SHA256SUMS)
sha="$(cut -d' ' -f1 "$out/SHA256SUMS")"
sed -e "s/@VERSION@/$version/" -e "s/@SHA256@/$sha/" \
    Resources/homebrew-cask.rb.in > "$out/sloppy-paste.rb"
echo "Prepared Sloppy Paste $version. Run just publish to release it and update the tap."
