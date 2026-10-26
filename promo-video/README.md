# Ledgelings promo video

Two motion-infographic promos, scene by scene, with the real creatures. Built with
[Remotion](https://www.remotion.dev) (React rendered to video), 1920×1080 at 30 fps,
each with its own chiptune loop made in code.

| Composition | What it shows | Length | Output |
|---|---|---|---|
| `Promo` | What the app does, as of v0.18.0 | 78 s | `out/ledgelings-promo.mp4` |
| `PromoV2` | Everything new since then, v0.19 to v0.62 | 84 s | `out/ledgelings-promo-v2.mp4` |

```bash
nvm use            # Node 24 LTS, from .nvmrc
npm install
PYTHON=python3 npm run render     # Promo
PYTHON=python3 npm run render:v2  # PromoV2
npm run dev                       # Remotion Studio, to scrub and tweak either
```

`PYTHON` must have Pillow and numpy (`spritetool/requirements.txt` plus numpy).

## Where things come from

| What | Source |
|---|---|
| Creature art, beds, game props | `scripts/export-sprites.py` copies `Sources/Ledgelings/Resources/sprites`, recoloured per species exactly as `SpriteAtlas.recoloured(around:)` does; Blocky's cast wear `AppSettings.defaultColors` |
| Lines in bubbles, notes and letters | Quoted from the built-in scripts: `Script+BuiltIn.swift`, `Letters.swift`, `TeaParty.swift`, `Complaints.swift`, `Reminders.swift`; for PromoV2 also `Beds+Lines.swift`, `Revenge+Lines.swift`, `Deeds+Lines.swift` |
| App screens in PromoV2 (`public/stills`) | The app's own snapshot and film flags, cropped: `scripts/capture-stills.sh` (needs `scripts/make-app.sh` first; backs up and restores the app's preferences, runs in English with built-in lines, no key) |
| Music | `scripts/make-music.py`: `78.7` for Promo, `84.5 v2` for PromoV2's quicker A-minor tune with a noise-channel beat. Triangle, pulse and noise waves, no samples |

## Scenes

`src/Promo.tsx` lists the first promo's scenes with their lengths: intro, the edges,
your hand, day and night, talk, flowers and planting, paper planes, tea parties,
reminders, the numbers, and the parade home. Each lives in `src/scenes/`.

`src/v2/PromoV2.tsx` lists PromoV2's: intro, the sprite kit, screens, beds, six games,
the cursor's revenge, deeds from letters, long-term memory, clipboard and screenshots,
dictation and translate, the Tools sheet, costs, and the parade home (the first
promo's `Outro` with new lines). Each lives in `src/v2/scenes/`; `src/v2/Still.tsx`
frames a still from `public/stills`.

When a feature changes, edit its scene; when the app's screens change, run
`npm run stills:v2` and look at `invite-goal.png` (the soccer match is played afresh
each run).
