"""Render steady rain: a soft wash of distant rain, a dense patter of nearby drops, drops landing in puddles,
the odd heavier drip from a gutter, and slow changes in intensity. Stereo 44.1 kHz float WAV."""
import sys
import numpy as np
from scipy.signal import butter, sosfilt, fftconvolve
from scipy.io import wavfile

SR = 44100
SECONDS = float(sys.argv[2]) if len(sys.argv) > 2 else 64
N = int(SECONDS * SR)
rng = np.random.default_rng(1103)


def bp(x, lo, hi, order=2):
    return sosfilt(butter(order, [lo, hi], "band", fs=SR, output="sos"), x, axis=0)


def lp(x, f, order=2):
    return sosfilt(butter(order, f, "low", fs=SR, output="sos"), x, axis=0)


def hp(x, f, order=2):
    return sosfilt(butter(order, f, "high", fs=SR, output="sos"), x, axis=0)


def pink(n):
    w = rng.standard_normal(n)
    F = np.fft.rfft(w); k = np.arange(len(F)); k[0] = 1
    return np.fft.irfft(F / np.sqrt(k), n)


def slow(n, period, depth):
    """A gentle, irregular swell between 1-depth and 1."""
    knots = rng.uniform(0, 1, int(n / SR / period) + 3)
    curve = np.interp(np.linspace(0, len(knots) - 1, n), np.arange(len(knots)), knots)
    curve = lp(curve, 0.5, 1)
    return 1 - depth * (curve - curve.min()) / (np.ptp(curve) + 1e-9)


def impulses(rate, n):
    """Random hits at `rate` per second with natural (log-normal) loudness."""
    x = np.zeros(n)
    k = np.nonzero(rng.random(n) < rate / SR)[0]
    x[k] = rng.lognormal(0, 0.5, len(k)) * rng.choice([-1, 1], len(k))
    return x


intensity = slow(N, 7, 0.25)
mix = np.zeros((N, 2))

for ch in range(2):
    # 1. far-off rain on roofs and trees: a soft, wide wash
    wash = lp(hp(pink(N), 40), 5000) * 0.35
    # rain drumming on roofs, ground and leaves: the weight underneath
    rumble = lp(np.cumsum(rng.standard_normal(N)) * 0.02, 450) 
    rumble = hp(rumble, 40) * 1.0
    wash = wash + rumble / (np.abs(rumble).mean() + 1e-9) * np.abs(wash).mean() * 1.4
    # 2. the patter: thousands of tiny drops close by, each a sharp tick shaped by what it lands on
    patter = np.zeros(N)
    for lo, hi, rate, gain in ((2500, 9000, 1400, 0.10), (1200, 5000, 900, 0.10), (600, 2500, 350, 0.12)):
        L = int(0.004 * SR)
        kern = bp(rng.standard_normal(L), lo, hi) * np.exp(-np.linspace(0, 7, L))
        patter += fftconvolve(impulses(rate, N), kern)[:N] * gain
    # 3. drops into puddles: tiny bubbles that ring and rise in pitch (the "plink" of real rain)
    plinks = np.zeros(N)
    for k in np.nonzero(rng.random(N) < 6 / SR)[0]:
        f0 = np.exp(rng.uniform(np.log(1100), np.log(3800)))
        L = int(rng.uniform(0.02, 0.05) * SR)
        t = np.arange(L) / SR
        phase = 2 * np.pi * np.cumsum(f0 * (1 + 0.35 * t / t[-1])) / SR
        s = np.sin(phase) * np.exp(-t / (L / SR / 4)) * rng.lognormal(-3.2, 0.5)
        plinks[k:k + L] += s[: max(0, min(L, N - k))]
    mix[:, ch] = (wash + patter + plinks) * intensity

# 4. a heavier drip from a gutter, roughly in rhythm, off to one side
t = 1.0
while t < SECONDS - 1:
    k = int(t * SR)
    L = int(0.06 * SR)
    tt = np.arange(L) / SR
    f0 = rng.uniform(700, 1000)
    drip = np.sin(2 * np.pi * np.cumsum(f0 * (1 + 0.5 * tt / tt[-1])) / SR) * np.exp(-tt / 0.012) * 0.05
    drip[:60] += rng.standard_normal(60) * 0.02
    mix[k:k + L, 0] += drip[: N - k] * 0.45
    mix[k:k + L, 1] += drip[: N - k] * 0.85
    t += rng.uniform(1.1, 1.9)

mix = hp(mix, 60)
mix /= np.abs(mix).max() + 1e-9
wavfile.write(sys.argv[1], SR, (mix * 0.7).astype(np.float32))
print("rain rendered", SECONDS, "s")
