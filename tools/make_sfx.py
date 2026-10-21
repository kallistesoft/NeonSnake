"""Synthesizes the game's sound effects into assets/sfx (no third-party audio, no licensing).

Run: python3 tools/make_sfx.py
"""
import math
import random
import struct
import wave
from pathlib import Path

RATE = 22050
OUT = Path(__file__).resolve().parents[1] / "assets" / "sfx"


def sweep(f0, f1, dur, vol=0.5, decay=6.0, wave_shape="square"):
    """Pitch slide from f0 to f1 (exponential), with a decaying envelope."""
    n = int(RATE * dur)
    out, phase = [], 0.0
    for i in range(n):
        t = i / RATE
        f = f0 * (f1 / f0) ** (t / dur)
        phase += 2 * math.pi * f / RATE
        if wave_shape == "square":
            s = 1.0 if math.sin(phase) >= 0 else -1.0
            s *= 0.6
        elif wave_shape == "saw":
            s = ((phase / math.pi) % 2) - 1
        else:
            s = math.sin(phase)
        env = min(1.0, t / 0.003) * math.exp(-decay * t)
        out.append(vol * env * s)
    return out


def noise(dur, vol=0.3, decay=30.0, seed=1, lowpass=0.0):
    rng = random.Random(seed)
    out, prev = [], 0.0
    for i in range(int(RATE * dur)):
        v = rng.uniform(-1, 1)
        prev = prev * lowpass + v * (1 - lowpass)
        out.append(vol * prev * math.exp(-decay * i / RATE))
    return out


def mix(*tracks):
    """tracks: (start_seconds, samples)"""
    length = max(int(start * RATE) + len(s) for start, s in tracks)
    buf = [0.0] * length
    for start, s in tracks:
        o = int(start * RATE)
        for i, v in enumerate(s):
            buf[o + i] += v
    return buf


def save(name, samples):
    peak = max(1e-9, max(abs(v) for v in samples))
    scale = min(1.0, 0.9 / peak)
    with wave.open(str(OUT / f"{name}.wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(b"".join(struct.pack("<h", int(v * scale * 32767)) for v in samples))


OUT.mkdir(parents=True, exist_ok=True)

# Laser: quick downward chirp, kept soft since it repeats constantly.
# Eat: short bright blip, kept soft since it repeats constantly.
save("eat", mix((0, sweep(660, 1320, 0.07, vol=0.35, decay=25)), (0.04, sweep(1320, 1500, 0.05, vol=0.2, decay=40, wave_shape="sine"))))
# Golden food: sparkling major arpeggio.
save("golden", mix(*[(i * 0.045, sweep(f, f * 1.01, 0.2, vol=0.25, decay=12, wave_shape="sine")) for i, f in enumerate([783.99, 987.77, 1174.66, 1567.98, 1975.53])]))
# Speed boost: rising zap.
save("boost", mix((0, sweep(300, 1800, 0.25, vol=0.35, decay=6, wave_shape="saw")), (0, noise(0.15, vol=0.1, decay=20, seed=5))))
# Poison: sour descending wobble.
save("poison", mix((0, sweep(500, 140, 0.35, vol=0.4, decay=5, wave_shape="square")), (0.05, sweep(470, 130, 0.3, vol=0.3, decay=6, wave_shape="square"))))
# Charge orb: power-up shimmer.
save("charge", mix(*[(i * 0.05, sweep(f, f * 1.5, 0.18, vol=0.3, decay=10)) for i, f in enumerate([392.0, 523.25, 659.25, 783.99])]))
# Crash: harsh descending buzz + boom.
save("die", mix((0, sweep(600, 70, 0.55, vol=0.4, decay=4.5, wave_shape="saw")), (0, noise(0.6, vol=0.5, decay=6, seed=3, lowpass=0.75))))
# Rival snake down: crunchy pop.
save("enemyDown", mix((0, noise(0.3, vol=0.45, decay=14, seed=2, lowpass=0.55)), (0, sweep(320, 60, 0.22, vol=0.4, decay=10, wave_shape="sine"))))
# Boss hit: heavy metallic clang.
save("bossHit", mix((0, sweep(180, 90, 0.4, vol=0.5, decay=6, wave_shape="square")), (0, sweep(1200, 900, 0.3, vol=0.25, decay=9, wave_shape="sine")),
                    (0, noise(0.3, vol=0.35, decay=10, seed=6, lowpass=0.5))))
# Warning (beam charging, walls closing): two-tone siren.
save("warning", mix(*[(i * 0.22, sweep(f, f, 0.2, vol=0.3, decay=3, wave_shape="saw")) for i, f in enumerate([880, 660, 880])]))
# Boss down: long rumbling explosion with a bright tail.
save("bossDown", mix((0, noise(1.6, vol=0.6, decay=2.2, seed=4, lowpass=0.8)), (0, sweep(160, 30, 1.2, vol=0.5, decay=2.5, wave_shape="sine")),
                     *[(0.5 + i * 0.08, sweep(f, f, 0.5, vol=0.15, decay=5, wave_shape="sine")) for i, f in enumerate([523.25, 659.25, 783.99, 1046.5])]))
# Level clear: bright major fanfare.
save("levelClear", mix(*[(i * 0.11, sweep(f, f, 0.4 if i < 3 else 0.9, vol=0.3, decay=4 if i < 3 else 2.5)) for i, f in enumerate([392.0, 523.25, 659.25, 783.99])]))
# Game over: slow descending minor.
save("gameOver", mix(*[(i * 0.22, sweep(f, f * 0.97, 0.6, vol=0.35, decay=3.5, wave_shape="saw")) for i, f in enumerate([392.0, 311.13, 261.63, 196.0])]))
print("written:", sorted(p.name for p in OUT.glob("*.wav")))
