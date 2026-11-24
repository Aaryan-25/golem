# Part of Golem: GADA, the editor; MAP.md section 5.7.
"""Makes the editor's soft sounds as small WAV files (no recordings, all made from numbers).

    python3 sounds.py OUTPUT_FOLDER

thud    the gada strikes (save)          whoosh  thrown to the AI's answer
crack   something failed                 tap     a find
chime   a relic found                    rise    code ran fine
"""
import math
import os
import random
import struct
import sys
import wave

RATE = 22050
out = sys.argv[1]
os.makedirs(out, exist_ok=True)
random.seed(7)


def write(name, samples, volume=0.35):
    peak = max(1e-9, max(abs(s) for s in samples))
    with wave.open(os.path.join(out, name + ".wav"), "w") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(b"".join(struct.pack("<h", int(32767 * volume * s / peak)) for s in samples))


def env(i, n, attack=0.005, release=1.0):
    t = i / RATE
    a = min(1.0, t / attack) if attack else 1.0
    return a * math.exp(-release * 6 * i / n)


def thud():
    n = int(RATE * 0.35)
    s = []
    for i in range(n):
        t = i / RATE
        f = 70 + 60 * math.exp(-t * 25)          # a falling low tone: weight
        body = math.sin(2 * math.pi * f * t)
        knock = random.uniform(-1, 1) * math.exp(-t * 90)  # the first instant: contact
        s.append((body * 0.9 + knock * 0.5) * env(i, n, 0.002, 1.2))
    return s


def whoosh():
    n = int(RATE * 0.45)
    s, lp = [], 0.0
    for i in range(n):
        t = i / RATE
        cut = 0.02 + 0.25 * math.sin(math.pi * t / 0.45)   # air that swells and passes
        lp += cut * (random.uniform(-1, 1) - lp)
        s.append(lp * math.sin(math.pi * i / n))
    return s


def crack():
    n = int(RATE * 0.3)
    s = []
    for i in range(n):
        t = i / RATE
        grit = random.uniform(-1, 1) * (1 if random.random() < 0.3 else 0.2)
        low = math.sin(2 * math.pi * 55 * t)
        s.append((grit * 0.7 + low * 0.5) * env(i, n, 0.001, 1.6))
    return s


def tap():
    n = int(RATE * 0.08)
    return [math.sin(2 * math.pi * 420 * i / RATE) * env(i, n, 0.001, 2.5) for i in range(n)]


def chime():
    n = int(RATE * 1.2)
    notes = (523.25, 659.25, 783.99)  # a soft major chord, one after another
    s = []
    for i in range(n):
        t = i / RATE
        v = 0.0
        for k, f in enumerate(notes):
            st = t - k * 0.09
            if st > 0:
                v += math.sin(2 * math.pi * f * st) * math.exp(-st * 3.2)
        s.append(v)
    return s


def rise():
    n = int(RATE * 0.5)
    s = []
    for i in range(n):
        t = i / RATE
        f = 300 + 300 * (t / 0.5)
        s.append(math.sin(2 * math.pi * f * t) * math.sin(math.pi * i / n) * 0.6)
    return s


write("thud", thud(), 0.45)
write("whoosh", whoosh(), 0.3)
write("crack", crack(), 0.35)
write("tap", tap(), 0.18)
write("chime", chime(), 0.25)
write("rise", rise(), 0.2)
