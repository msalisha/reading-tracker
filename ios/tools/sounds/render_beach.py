"""Render a beach: waves that swell, break and fizz back over sand, distant surf and a light breeze.
Each wave's sound is shaped frame by frame in the frequency domain, so its brightness follows the wave."""
import sys
import numpy as np
from scipy.signal import stft, istft, butter, sosfilt
from scipy.io import wavfile

SR = 44100
SECONDS = float(sys.argv[2]) if len(sys.argv) > 2 else 104
N = int(SECONDS * SR)
rng = np.random.default_rng(1977)
NPER = 2048
HOP = NPER // 4


def shaped_noise(n, gain_fn, colour=0.5):
    """Noise of length n whose spectrum at frame time t (0..1) and frequency f is gain_fn(t, f)."""
    w = rng.standard_normal(n)
    f, t, Z = stft(w, SR, nperseg=NPER, noverlap=NPER - HOP)
    ff = np.maximum(f, 20)[:, None]
    tt = (t / (n / SR))[None, :]
    Z = Z * gain_fn(tt, ff) / ff ** (colour / 2)  # colour 0 = white, 1 = pink, 2 = brown
    _, y = istft(Z, SR, nperseg=NPER, noverlap=NPER - HOP)
    return y[:n].astype(np.float32)


def smoothstep(x):
    x = np.clip(x, 0, 1)
    return x * x * (3 - 2 * x)


def wave(dur, size):
    """One wave: swell (dull, rising) -> break (bright crash) -> wash up the sand -> foam fizzing back."""
    n = int(dur * SR)
    tb = rng.uniform(0.28, 0.38)            # moment it breaks, as a fraction of its life

    def body(t, f):
        rise = smoothstep(t / tb) ** 1.5
        onset = smoothstep((t - tb + 0.02) / 0.05)          # the crash builds over a fraction of a second
        crash = onset * np.exp(-np.maximum(0, t - tb) / 0.12)
        amp = (rise * 0.55 + 0.45 * crash) * np.exp(-np.maximum(0, t - tb) / 0.55)
        cutoff = 250 + 900 * rise + 4200 * crash
        return amp * (1 / (1 + (f / cutoff) ** 3))

    def wash(t, f):
        u = np.maximum(0, t - tb)
        amp = smoothstep(u / 0.12) * np.exp(-u / 0.24)
        band = np.exp(-((np.log(f) - np.log(1800 + 1500 * np.exp(-u / 0.2))) ** 2) / 1.3)
        return amp * band

    def hiss(t, f):  # wet sand and retreating water
        u = np.maximum(0, t - tb - 0.05)
        amp = smoothstep(u / 0.16) * np.exp(-u / 0.2) * 0.5
        return amp * smoothstep((f - 700) / 5000) * (1 / (1 + (f / 8000) ** 4))

    s = shaped_noise(n, body, 1.7) * 5.0 + shaped_noise(n, wash, 1.0) * 0.9 + shaped_noise(n, hiss, 0.6) * 0.16

    # foam: many small bubbles popping as the water drains back
    t0 = int((tb + 0.08) * n)
    foam_len = n - t0
    k_ = np.arange(foam_len)
    density = smoothstep(k_ / (0.12 * n)) * np.exp(-k_ / (0.16 * n)) * rng.uniform(300, 650)
    times = np.nonzero(rng.random(foam_len) < density / SR)[0]
    bub = np.zeros(foam_len + 2000)
    for k in times:
        f0 = np.exp(rng.uniform(np.log(700), np.log(5500)))
        L = int(rng.uniform(0.004, 0.02) * SR)
        tt = np.arange(L) / SR
        chirp = np.sin(2 * np.pi * f0 * tt * (1 + 0.6 * tt / tt[-1] * 0.15)) * np.exp(-tt / (L / SR / 3))
        bub[k:k + L] += chirp * rng.uniform(0.002, 0.009)
    s[t0:] += bub[:foam_len].astype(np.float32)
    fade = np.ones(n, np.float32); m = int(0.35 * n)
    fade[-m:] = np.cos(np.linspace(0, np.pi / 2, m)) ** 2
    return s * fade * size


left = np.zeros(N, np.float32)
right = np.zeros(N, np.float32)
t = -rng.uniform(2, 5)
while t < SECONDS:
    dur = rng.uniform(7.5, 11)
    size = rng.uniform(0.55, 1.0)
    state = rng.bit_generator.state
    sL = wave(dur, size)
    rng.bit_generator.state = state          # same wave shape and timing for both ears...
    rng.standard_normal(7)                   # ...but fresh noise, so the two ears differ naturally (no metallic comb)
    sR = wave(dur, size)
    p = rng.uniform(-0.35, 0.35)
    a = (p + 1) * np.pi / 4
    start = int(t * SR)
    for buf, g, off, s in ((left, np.cos(a), 0, sL), (right, np.sin(a), 0, sR)):
        lo, hi = max(0, start + off), min(N, start + off + len(s))
        if hi > lo:
            buf[lo:hi] += s[lo - (start + off):hi - (start + off)] * g
    t += dur * rng.uniform(0.55, 0.8)  # the next wave arrives before this one has drained away

mix = np.stack([left, right], axis=1)
# distant surf all along the shore, and a light breeze that comes and goes
surf = np.stack([shaped_noise(N, lambda t, f: 1 / (1 + (f / 260) ** 2), 1.8),
                 shaped_noise(N, lambda t, f: 1 / (1 + (f / 260) ** 2), 1.8)], axis=1)
breeze_env = lambda t, f: (0.55 + 0.45 * np.sin(2 * np.pi * (t * SECONDS / 23) + 1.3) ** 2) * np.exp(-((np.log(f) - np.log(700)) ** 2) / 0.9)
breeze = np.stack([shaped_noise(N, breeze_env, 1.0), shaped_noise(N, breeze_env, 1.0)], axis=1)
mix = mix + surf * (np.abs(mix).mean() / (np.abs(surf).mean() + 1e-9)) * 0.45 + breeze * (np.abs(mix).mean() / (np.abs(breeze).mean() + 1e-9)) * 0.08
mix = sosfilt(butter(2, 35, "high", fs=SR, output="sos"), mix, axis=0)
mix /= np.abs(mix).max() + 1e-9
wavfile.write(sys.argv[1], SR, (mix * 0.7).astype(np.float32))
print("beach rendered", N / SR, "s")
