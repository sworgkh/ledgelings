"""Write public/music.wav: a soft chiptune loop for the promo, made from
triangle and pulse waves here, so the video carries no borrowed audio.

    python3 scripts/make-music.py [seconds]        # the first promo's tune
    python3 scripts/make-music.py [seconds] v2     # public/music-v2.wav, PromoV2's tune
"""
import sys, wave
from pathlib import Path
import numpy as np

RATE = 44100
SECONDS = float(sys.argv[1]) if len(sys.argv) > 1 else 80.0
V2 = len(sys.argv) > 2 and sys.argv[2] == "v2"
BPM = 132 if V2 else 120
EIGHTH = 60 / BPM / 2
OUT = Path(__file__).resolve().parents[1] / ("public/music-v2.wav" if V2 else "public/music.wav")


def hz(midi):
    return 440.0 * 2 ** ((midi - 69) / 12)


def tone(midi, length, kind="triangle", volume=0.2, duty=0.25):
    t = np.arange(int(RATE * length)) / RATE
    phase = (t * hz(midi)) % 1.0
    wave_ = 4 * np.abs(phase - 0.5) - 1 if kind == "triangle" else np.where(phase < duty, 1.0, -1.0)
    attack = np.minimum(1, t / 0.008)
    decay = np.exp(-t * (3.5 if kind == "triangle" else 6.0))
    return wave_ * attack * decay * volume


# C, G, Am, F: one chord a bar, eight eighths a bar.
CHORDS = [(60, 64, 67), (55, 59, 62), (57, 60, 64), (53, 57, 60)]
ARP = [0, 1, 2, 1, 0, 2, 1, 2]
TUNE = [  # one bar of melody per chord, 0 = rest; repeats with a variation every other time
    [76, 0, 74, 72, 74, 0, 76, 0], [74, 0, 71, 0, 67, 0, 71, 74],
    [72, 0, 76, 0, 79, 0, 76, 72], [72, 74, 72, 69, 0, 0, 0, 0],
]
TUNE_B = [
    [79, 0, 76, 0, 72, 0, 76, 79], [81, 0, 79, 0, 74, 0, 71, 0],
    [76, 0, 72, 0, 69, 72, 76, 0], [77, 0, 76, 0, 74, 0, 72, 0],
]

if V2:
    # Am, F, C, G: brighter and quicker, a bouncing arpeggio and a tune that climbs.
    CHORDS = [(57, 60, 64), (53, 57, 60), (60, 64, 67), (55, 59, 62)]
    ARP = [0, 2, 1, 2, 0, 2, 1, 0]
    TUNE = [
        [76, 0, 76, 79, 0, 76, 74, 72], [72, 0, 69, 0, 72, 74, 0, 0],
        [79, 0, 79, 81, 79, 0, 76, 0], [74, 0, 71, 74, 0, 79, 0, 0],
    ]
    TUNE_B = [
        [81, 0, 79, 76, 0, 79, 81, 0], [77, 0, 76, 72, 0, 69, 72, 0],
        [76, 79, 0, 84, 0, 79, 76, 0], [79, 0, 74, 0, 71, 0, 74, 79],
    ]


NOISE = np.random.default_rng(7)


def hat(length, volume):
    """A tick on the chip's noise channel: white noise made here, gone in a moment."""
    t = np.arange(int(RATE * length)) / RATE
    return NOISE.uniform(-1, 1, len(t)) * np.exp(-t * 60) * volume


def kick(midi, length, volume):
    """A short low pulse that drops away fast, the beat under the v2 tune."""
    t = np.arange(int(RATE * length)) / RATE
    return tone(midi, length, "pulse", volume, 0.5) * np.exp(-t * 25)


total = int(RATE * SECONDS)
mix = np.zeros(total + RATE)
bars = int(SECONDS / (EIGHTH * 8)) + 1
for bar in range(bars):
    chord = CHORDS[bar % 4]
    tune = (TUNE if (bar // 4) % 2 == 0 else TUNE_B)[bar % 4]
    for step in range(8):
        at = int(RATE * (bar * 8 + step) * EIGHTH)
        parts = [tone(chord[ARP[step]] + 12, EIGHTH * 1.5, "pulse", 0.035, 0.125)]
        if step % 2 == 0:
            parts.append(tone(chord[0] - 12, EIGHTH * 2, "triangle", 0.28))
        if V2 and bar >= 1:
            parts.append(hat(EIGHTH, 0.05 if step % 2 else 0.09))
            if step in (0, 4):
                parts.append(kick(chord[0] - 24, EIGHTH, 0.06))
        if bar >= 2 and tune[step]:
            parts.append(tone(tune[step], EIGHTH * 1.8, "triangle", 0.16))
            parts.append(tone(tune[step], EIGHTH * 1.2, "pulse", 0.025, 0.25))
        for p in parts:
            end = min(len(mix), at + len(p))
            if end <= at:
                continue
            mix[at:end] += p[: end - at]

mix = mix[:total]
fade = np.ones(total)
fade[: int(RATE * 0.4)] = np.linspace(0, 1, int(RATE * 0.4))
fade[-int(RATE * 3):] = np.linspace(1, 0, int(RATE * 3))
mix *= fade
mix = np.tanh(mix * 1.4) * 0.6
pcm = (mix * 32767).astype(np.int16)
with wave.open(str(OUT), "wb") as w:
    w.setnchannels(1)
    w.setsampwidth(2)
    w.setframerate(RATE)
    w.writeframes(pcm.tobytes())
print(OUT, f"{SECONDS:.1f}s")
