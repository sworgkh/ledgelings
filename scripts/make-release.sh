#!/bin/sh
# Build the macOS installer for a version, tag it and publish a GitHub release
# with the .pkg, the .dmg and their checksums.
#
#   VERSION=0.14.0 scripts/make-release.sh              # notes from the last merge on main
#   VERSION=0.14.0 NOTES=notes.md scripts/make-release.sh
#
# Needs `gh` logged in to an account that can write the repo (GH_TOKEN works too).
# Run it on main, with a clean tree, after the version in scripts/make-app.sh,
# scripts/make-installer.sh and win/Directory.Build.props has been bumped.
set -eu
cd "$(dirname "$0")/.."
VERSION="${VERSION:?set VERSION=x.y.z}"
TAG="v$VERSION"
PKG="build/Ledgelings-$VERSION.pkg"
DMG="build/Ledgelings-$VERSION.dmg"
SUMS="build/SHA256SUMS-$VERSION.txt"

[ -z "$(git status --porcelain)" ] || { echo "commit or stash first: the tree is not clean" >&2; exit 1; }
VERSION="$VERSION" scripts/make-installer.sh
shasum -a 256 "$PKG" "$DMG" | sed 's#build/##' > "$SUMS"

if [ -n "${NOTES:-}" ]; then
  NOTES_ARGS="--notes-file $NOTES"
else
  NOTES_ARGS="--generate-notes"
fi
# shellcheck disable=SC2086
gh release create "$TAG" "$PKG" "$DMG" "$SUMS" --target main --title "Ledgelings $VERSION" $NOTES_ARGS
echo "published $TAG"
