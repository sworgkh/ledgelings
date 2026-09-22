#!/bin/bash
# Build the two things you can hand to someone:
#   build/Ledgelings-<version>.pkg   double-click installer, puts the app in /Applications
#   build/Ledgelings-<version>.dmg   disk image, drag the app onto Applications
# Both wear the creature as their Finder icon.
#
#   scripts/make-installer.sh              # version 0.10.0
#   VERSION=0.3.0 scripts/make-installer.sh
#
# The app is ad-hoc signed, not notarised. On another Mac, Gatekeeper will
# object the first time: right-click the app (or the .pkg) and choose Open.
set -euo pipefail
cd "$(dirname "$0")/.."
export VERSION="${VERSION:-0.15.0}"

scripts/make-app.sh
APP=build/Ledgelings.app
ICON="$APP/Contents/Resources/AppIcon.icns"
PKG="build/Ledgelings-$VERSION.pkg"
DMG="build/Ledgelings-$VERSION.dmg"
STAGE=build/stage
rm -rf "$STAGE" "$PKG" "$DMG"

# --- .pkg -------------------------------------------------------------------
mkdir -p "$STAGE/pkg"
cp -R "$APP" "$STAGE/pkg/"
# Drop what extended attributes we can, so they do not ride along in the payload.
# macOS re-adds its own provenance tag, which still shows up as "._" entries;
# those are harmless -- the expanded payload passes `codesign --verify --strict`.
xattr -cr "$STAGE/pkg"
export COPYFILE_DISABLE=1
# Without this the installer "helpfully" upgrades whichever copy of the app it
# finds first -- such as build/Ledgelings.app -- instead of /Applications.
pkgbuild --analyze --root "$STAGE/pkg" "$STAGE/component.plist" >/dev/null
/usr/libexec/PlistBuddy -c "Set :0:BundleIsRelocatable false" "$STAGE/component.plist"
pkgbuild --root "$STAGE/pkg" --component-plist "$STAGE/component.plist" \
    --install-location /Applications --identifier com.alterman.ledgelings \
    --version "$VERSION" "$PKG" >/dev/null

# --- .dmg -------------------------------------------------------------------
mkdir -p "$STAGE/dmg"
cp -R "$APP" "$STAGE/dmg/"
xattr -cr "$STAGE/dmg"
ln -s /Applications "$STAGE/dmg/Applications"
hdiutil create -volname "Ledgelings" -srcfolder "$STAGE/dmg" -format UDZO -ov "$DMG" >/dev/null

swift scripts/set-icon.swift "$ICON" "$PKG" "$DMG"
rm -rf "$STAGE"
echo "built $PKG"
echo "built $DMG"
