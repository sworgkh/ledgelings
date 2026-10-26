#!/bin/bash
# Write public/stills: the app's own pictures of itself, for PromoV2's scenes.
# Every still comes from a snapshot or film flag of build/Ledgelings.app (see
# AGENTS.md, "Checking your work in the real app"); nothing here draws UI.
#
#   scripts/make-app.sh                      # from the repo root, first
#   promo-video/scripts/capture-stills.sh
#
# The app's preferences are shared with the running copy: they are exported first
# and imported back after (the run adds no keys). The stills are taken in English
# with the built-in lines (brainProvider script), so no key and no network.
set -euo pipefail
cd "$(dirname "$0")/.."
APP=../build/Ledgelings.app/Contents/MacOS/Ledgelings
OUT=public/stills
RAW=$(mktemp -d)
PREFS="$RAW/prefs.plist"
mkdir -p "$OUT"

defaults export com.alterman.ledgelings "$PREFS"
trap 'defaults import com.alterman.ledgelings "$PREFS"; rm -rf "$RAW"' EXIT
defaults write com.alterman.ledgelings brainProvider script
defaults write com.alterman.ledgelings language en

run() { perl -e 'alarm 300; exec @ARGV' "$APP" "$@" 2>&1 | tail -3; }

run --tools --snapshot "$OUT/tools.png"
run --settings costs --snapshot "$OUT/costs.png"
run --settings sprites --snapshot "$OUT/sprites.png"
run --relationships --snapshot "$OUT/relationships.png"
run --kit-images "$RAW/kit"
cp "$RAW/kit/1-poses.png" "$OUT/kit-poses.png"
cp "$RAW/kit/2-template.png" "$OUT/kit-template.png"
run --shot-film "$RAW/shot.mp4"
cp "$RAW/shot-toolbar-tip.png" "$RAW/shot-rectangle.png" "$OUT/"
run --dictate-film "$RAW/dictate.mp4"
LEDGELINGS_FAKE_TRANSLATE=1 run --translate-film "$RAW/translate.mp4"
run --clip-film "$RAW/clip.mp4"
run --invite-film "$RAW/invite.mp4" soccer

# Frames of the films, cropped to what the scenes show (the films are 2560×1440).
frame() { ffmpeg -v error -y -ss "$2" -i "$RAW/$1.mp4" -frames:v 1 "$RAW/$1-$2.png"; echo "$RAW/$1-$2.png"; }
crop() { ffmpeg -v error -y -i "$1" -vf "crop=$2,scale=$3:-1:flags=lanczos" "$OUT/$4"; }
crop "$(frame clip 1.6)" 1460:1240:589:102 1100 clip-picker.png
# The soccer game the letter set up, 93 s in. The match is played afresh each run,
# so look at the frame: a goal or a scoreboard is what the Deeds scene wants.
crop "$(frame invite 92.9)" 2560:1440:0:0 1280 invite-goal.png
crop "$RAW/dictate-listening.png" 716:360:922:563 716 dictate-listening.png
crop "$RAW/dictate-copied.png" 716:360:922:563 716 dictate-copied.png
crop "$RAW/translate-russian.png" 1520:940:0:0 1000 translate-russian.png
crop "$RAW/translate-hebrew.png" 1520:940:0:0 1000 translate-hebrew.png
ls -1 "$OUT"
