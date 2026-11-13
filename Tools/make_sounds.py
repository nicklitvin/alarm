#!/usr/bin/env python3
"""Generates the app's alarm sounds (App/Sounds/*.wav). All tones are synthesized here, so they're
original and free to ship. Each file is just under 30 seconds (the longest an alarm sound can be)
and repeats its pattern, since a custom alarm sound may play only once.

Run from the repo root:  python3 Tools/make_sounds.py
"""
import math, struct, wave, os

RATE = 22050
LENGTH = 28.0
OUT = os.path.join(os.path.dirname(__file__), "..", "App", "Sounds")


def silence(seconds):
    return [0.0] * int(RATE * seconds)


def tone(freq, seconds, harmonics=((1, 1.0),), decay=0.0, attack=0.005, release=0.02, vibrato=0.0):
    n = int(RATE * seconds)
    out = []
    for i in range(n):
        t = i / RATE
        f = freq * (1 + vibrato * math.sin(2 * math.pi * 5 * t))
        v = sum(a * math.sin(2 * math.pi * f * h * t) for h, a in harmonics)
        env = min(1.0, t / attack) if attack else 1.0
        env *= min(1.0, (seconds - t) / release) if release else 1.0
        if decay:
            env *= math.exp(-decay * t)
        out.append(v * env)
    return out


def mix_into(buf, start, samples, gain=1.0):
    s = int(start * RATE)
    for i, v in enumerate(samples):
        if s + i < len(buf):
            buf[s + i] += v * gain


def repeat(pattern, period, gain_ramp=None):
    buf = [0.0] * int(RATE * LENGTH)
    t, k = 0.0, 0
    while t < LENGTH:
        g = gain_ramp(t) if gain_ramp else 1.0
        for start, samples, gain in pattern():
            mix_into(buf, t + start, samples, gain * g)
        t += period
        k += 1
    return buf


def write(name, buf):
    peak = max(1e-9, max(abs(v) for v in buf))
    scale = 0.85 / peak
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, name)
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(b"".join(struct.pack("<h", int(max(-1, min(1, v * scale)) * 32767)) for v in buf))
    print("wrote", os.path.relpath(path))


BELL = ((1, 1.0), (2.76, 0.35), (5.4, 0.12))
MARIMBA = ((1, 1.0), (4, 0.25), (10, 0.05))
BEEP = ((1, 1.0), (3, 0.15))

# Chime: a soft rising arpeggio of bell tones.
def chime():
    notes = [523.25, 659.25, 783.99, 1046.5]
    return [(i * 0.28, tone(f, 1.6, BELL, decay=2.6, release=0.3), 0.8) for i, f in enumerate(notes)]

# Beacon: two clear tones, high then low, like a lighthouse signal.
def beacon():
    return [(0.0, tone(880, 0.45, BEEP, release=0.08), 1.0), (0.6, tone(660, 0.45, BEEP, release=0.08), 1.0)]

# Pulse: three quick digital beeps and a pause.
def pulse():
    return [(i * 0.18, tone(1760, 0.1, BEEP, release=0.01), 0.9) for i in range(3)]

# Rise: a gentle marimba melody that gets louder over the first 20 seconds.
def rise():
    melody = [392.0, 493.88, 587.33, 783.99, 587.33, 493.88]
    return [(i * 0.25, tone(f, 0.8, MARIMBA, decay=5.0, release=0.1), 0.9) for i, f in enumerate(melody)]

# Bells: a bright two-bell ring, repeated.
def bells():
    out = []
    for i in range(6):
        out.append((i * 0.16, tone(1318.5 if i % 2 == 0 else 1174.66, 0.6, BELL, decay=4.0, release=0.1), 0.7))
    return out


if __name__ == "__main__":
    write("alarmie-chime.wav", repeat(chime, 2.4))
    write("alarmie-beacon.wav", repeat(beacon, 1.6))
    write("alarmie-pulse.wav", repeat(pulse, 1.0))
    write("alarmie-rise.wav", repeat(rise, 2.0, gain_ramp=lambda t: 0.15 + 0.85 * min(1.0, t / 20)))
    write("alarmie-bells.wav", repeat(bells, 1.8))
