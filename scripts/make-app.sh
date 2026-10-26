#!/bin/bash
# Build a release binary and wrap it as build/Ledgelings.app (menu bar only).
#   scripts/make-app.sh && open build/Ledgelings.app
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="${VERSION:-0.61.0}"

swift build -c release
APP=build/Ledgelings.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$(swift build -c release --show-bin-path)/Ledgelings" "$APP/Contents/MacOS/Ledgelings"
cp -R Sources/Ledgelings/Resources/sprites "$APP/Contents/Resources/sprites"

# The icon is the creature itself, drawn from the same atlas the app animates.
python3 -m spritetool icon sprites/blocky.yaml --out build/AppIcon.iconset >/dev/null
iconutil -c icns build/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleExecutable</key><string>Ledgelings</string>
    <key>CFBundleIdentifier</key><string>com.alterman.ledgelings</string>
    <key>CFBundleName</key><string>Ledgelings</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>26.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSMicrophoneUsageDescription</key><string>Dictation listens while you hold its shortcut, and sends the sound to the model you chose to write it down. Nothing is recorded otherwise, and nothing is saved.</string>
</dict>
</plist>
PLIST

# Ad hoc, on purpose. An "Apple Development" identity looked like a way to make
# the keychain trust every build as one app, but macOS 26 quarantines such an
# app as malware on launch (it is neither Developer ID nor notarised). Ad hoc
# only ever costs a right-click > Open. SIGN_IDENTITY overrides for someone
# with a Developer ID and a notarisation step.
# An ad hoc signature names the build by its hash, and macOS keeps an
# Accessibility grant for that hash only: every rebuild silently lost it, so
# picking a clip only copied (the switch in System Settings still showed on).
# A fixed designated requirement makes every build the same app to the grant.
if [ -z "${SIGN_IDENTITY:-}" ]; then
    codesign --force --sign - -r='designated => identifier "com.alterman.ledgelings"' "$APP" >/dev/null
else
    codesign --force --sign "$SIGN_IDENTITY" "$APP" >/dev/null
fi
echo "built $APP"
