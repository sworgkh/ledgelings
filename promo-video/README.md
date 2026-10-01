# Ledgelings promo video

A 78-second motion-infographic promo: what the app does, scene by scene, with the
real creatures. Built with [Remotion](https://www.remotion.dev) (React rendered to
video), 1920×1080 at 30 fps, with a chiptune loop made in code.

```bash
nvm use            # Node 24 LTS, from .nvmrc
npm install
PYTHON=python3 npm run render     # out/ledgelings-promo.mp4
npm run dev                       # Remotion Studio, to scrub and tweak
```

`PYTHON` must have Pillow and numpy (`spritetool/requirements.txt` plus numpy).

## Where things come from

| What | Source |
|---|---|
| Creature art | `scripts/export-sprites.py` copies `Sources/Ledgelings/Resources/sprites`, recoloured per species exactly as `SpriteAtlas.recoloured(around:)` does; Blocky's cast wear `AppSettings.defaultColors` |
| Lines in bubbles and notes | Quoted from the built-in scripts: `Script+BuiltIn.swift`, `Letters.swift`, `TeaParty.swift`, `Complaints.swift`, `Reminders.swift` |
| Music | `scripts/make-music.py`, triangle and pulse waves, no samples |

## Scenes

`src/Promo.tsx` lists them with their lengths: intro, the edges, your hand, day and
night, talk, flowers and planting, paper planes, tea parties, reminders, the numbers,
and the parade home. Each lives in `src/scenes/`. When a feature changes, edit its
scene; when the numbers change (species, characters, conversations), edit
`src/scenes/Numbers.tsx`.
