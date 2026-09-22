#!/bin/sh
# Render the promo video: the colony on a clean wallpaper, directed through every
# feature, written offscreen by the app itself. Nothing on screen is recorded.
#
#   scripts/make-promo.sh                 # build/Ledgelings-promo-<version>.mp4 and a poster frame
#   OUT=/tmp/p.mp4 scripts/make-promo.sh
set -eu
cd "$(dirname "$0")/.."
VERSION=$(sed -n 's/^VERSION="${VERSION:-\(.*\)}"/\1/p' scripts/make-app.sh)
OUT="${OUT:-build/Ledgelings-promo-$VERSION.mp4}"
swift build -c release 2>&1 | tail -1
.build/release/Ledgelings --promo "$OUT"
if command -v ffmpeg >/dev/null; then
  ffmpeg -v error -y -ss 17 -i "$OUT" -frames:v 1 "${OUT%.mp4}.png"
  echo "poster ${OUT%.mp4}.png"
fi
