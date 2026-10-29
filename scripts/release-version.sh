#!/bin/bash
# With no bump, preserve the prepare-only workflow. With a bump, publish end to end.
set -euo pipefail
cd "$(dirname "$0")/.."

bump="${1:-}"
notes="${2:-}"
case "$bump" in
    "")
        [[ -z "$notes" ]] || { echo "Release notes require patch, minor, or major." >&2; exit 1; }
        exec scripts/release.sh
        ;;
    patch|minor|major) ;;
    *) echo "Usage: just release [patch|minor|major] [notes]" >&2; exit 1 ;;
esac

[[ -z "$(git status --porcelain)" ]] || { echo "Commit or stash changes before releasing." >&2; exit 1; }
[[ "$(git branch --show-current)" == main ]] || { echo "Switch to main before releasing." >&2; exit 1; }
case "$(git remote get-url origin)" in
    git@github.com:sglavoie/AI-Sloppy-Paste.git|https://github.com/sglavoie/AI-Sloppy-Paste.git) ;;
    *) echo "origin must point to sglavoie/AI-Sloppy-Paste." >&2; exit 1 ;;
esac

source_file=Sources/SloppyCore/SloppyCore.swift
version="$(sed -n 's/.*static let version = "\(.*\)".*/\1/p' "$source_file")"
[[ "$version" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]] || {
    echo "Invalid release version: $version" >&2; exit 1;
}
IFS=. read -r major minor patch <<< "$version"
case "$bump" in
    patch) patch=$((patch + 1)) ;;
    minor) minor=$((minor + 1)); patch=0 ;;
    major) major=$((major + 1)); minor=0; patch=0 ;;
esac
next="$major.$minor.$patch"

gh auth status >/dev/null
git fetch origin main
git merge-base --is-ancestor FETCH_HEAD HEAD || {
    echo "Local main is behind or diverged from origin/main; update it before releasing." >&2; exit 1;
}
if git show-ref --verify --quiet "refs/tags/v$next" || gh release view "v$next" --repo sglavoie/AI-Sloppy-Paste >/dev/null 2>&1; then
    echo "v$next already exists; reconcile the source version before releasing." >&2
    exit 1
fi

# Keep the version commit on failure so the same version can be resumed.
bumped=0
prepared=0
finish() {
    status=$?
    if [[ "$status" -ne 0 && "$bumped" == 1 ]]; then
        echo "Release v$next stopped; its version commit is preserved. Do not bump again to retry." >&2
        if [[ "$prepared" == 0 ]]; then
            echo "Fix the failure, then run: just release && git push origin main && just publish" >&2
        else
            echo "Fix the failure, then run: git push origin main && just publish" >&2
        fi
        echo "Pass any custom release notes to just publish again." >&2
    fi
}
trap finish EXIT

echo "Bumping Sloppy Paste $version -> $next"
updated="$(sed "s/static let version = \"$version\"/static let version = \"$next\"/" "$source_file")"
printf '%s\n' "$updated" > "$source_file"
git add -- "$source_file"
git commit -m "chore(release): v$next" -- "$source_file"
bumped=1
commit="$(git rev-parse HEAD)"

scripts/release.sh
prepared=1
[[ "$(git rev-parse HEAD)" == "$commit" && -z "$(git status --porcelain)" ]] || {
    echo "Source changed during release preparation; rebuild before publishing." >&2; exit 1;
}
git push origin "$commit:refs/heads/main"
scripts/publish.sh "$notes"
