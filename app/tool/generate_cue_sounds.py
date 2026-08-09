"""Regenerate the coach cue sounds in `assets/audio/`.

Pure stdlib, 16-bit mono 22.05 kHz WAV. These are synthesised stand-ins for
properly recorded gym bells: unambiguous through a phone speaker in a noisy
room, which is all v0.1 needs. Replace the files with real recordings whenever
someone gets a decent microphone near a real bell — nothing in the app cares
where the samples came from, only that the file names in `CueSound` still
resolve.

    python3 tool/generate_cue_sounds.py
"""

import array
import math
import os
import wave

RATE = 22050
ASSET_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "audio")


def write(path, samples):
    data = array.array("h")
    peak = max(1e-9, max(abs(s) for s in samples))
    for s in samples:
        v = int(max(-1.0, min(1.0, s / peak * 0.85)) * 32767)
        data.append(v)
    with wave.open(path, "w") as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(RATE)
        f.writeframes(data.tobytes())
    print("%s (%.2fs)" % (path, len(samples) / RATE))


def strike(buf, start, duration, freq, decay, partials=(1.0, 2.76, 5.4)):
    """A struck-metal tone: inharmonic partials under an exponential decay."""
    n = int(duration * RATE)
    for i in range(n):
        idx = start + i
        if idx >= len(buf):
            break
        t = i / RATE
        env = math.exp(-decay * t)
        env *= min(1.0, t / 0.004)  # short attack so it does not click
        v = 0.0
        for k, p in enumerate(partials):
            v += (0.6 ** k) * math.sin(2 * math.pi * freq * p * t)
        buf[idx] += v * env


def silence(seconds):
    return [0.0] * int(seconds * RATE)


def bell():
    """Round start."""
    buf = silence(1.4)
    strike(buf, 0, 1.4, 660.0, 3.0)
    return buf


def end_bell():
    """Round end — two strikes, so it is never confused with the start."""
    buf = silence(1.9)
    strike(buf, 0, 1.9, 520.0, 2.6)
    strike(buf, int(0.28 * RATE), 1.5, 520.0, 2.6)
    return buf


def tick():
    """Last ten seconds of work."""
    buf = silence(0.09)
    strike(buf, 0, 0.09, 1400.0, 55.0, partials=(1.0, 2.0))
    return buf


def warning():
    """Rest is nearly over."""
    buf = silence(0.5)
    strike(buf, 0, 0.25, 880.0, 12.0, partials=(1.0, 2.0))
    strike(buf, int(0.22 * RATE), 0.28, 1180.0, 12.0, partials=(1.0, 2.0))
    return buf


def finish():
    """Session complete — three strikes."""
    buf = silence(3.0)
    for i in range(3):
        strike(buf, int(i * 0.42 * RATE), 3.0 - i * 0.42, 600.0, 2.2)
    return buf


def main():
    target = os.path.abspath(ASSET_DIR)
    os.makedirs(target, exist_ok=True)
    write(os.path.join(target, "bell.wav"), bell())
    write(os.path.join(target, "end_bell.wav"), end_bell())
    write(os.path.join(target, "tick.wav"), tick())
    write(os.path.join(target, "warning.wav"), warning())
    write(os.path.join(target, "finish.wav"), finish())


if __name__ == "__main__":
    main()
