"""Render a wood fire in a fireplace: the low roar of the flames, bursts of crackles, the odd pop of a log,
a whisper of sap and settling embers, in a small room. Stereo 44.1 kHz float WAV."""
import sys
import numpy as np
from scipy.signal import butter, sosfilt, fftconvolve, lfilter
from scipy.io import wavfile

SR = 44100
SECONDS = float(sys.argv[2]) if len(sys.argv) > 2 else 74
N = int(SECONDS * SR)
rng = np.random.default_rng(1666)


def bp(x, lo, hi, order=2):
    return sosfilt(butter(order, [lo, hi], "band", fs=SR, output="sos"), x, axis=0)


def lp(x, f, order=2):
    return sosfilt(butter(order, f, "low", fs=SR, output="sos"), x, axis=0)


def hp(x, f, order=2):
    return sosfilt(butter(order, f, "high", fs=SR, output="sos"), x, axis=0)


def resonator(x, f, bw):
    r = np.exp(-np.pi * bw / SR); th = 2 * np.pi * f / SR
    return lfilter([(1 - r * r) * 0.5, 0, -(1 - r * r) * 0.5], [1, -2 * r * np.cos(th), r * r], x)


def wander(n, rate, lo, hi):
    """A value that drifts irregularly between lo and hi, `rate` changes per second."""
    knots = rng.uniform(lo, hi, int(n / SR * rate) + 3)
    return np.interp(np.linspace(0, len(knots) - 1, n), np.arange(len(knots)), knots)


mix = np.zeros((N, 2))

# 1. the roar: turbulent air and flame, low and breathing
for ch in range(2):
    brown = np.cumsum(rng.standard_normal(N)) * 0.02
    roar = lp(hp(brown, 35), 320)
    flicker = lp(wander(N, 6, 0.55, 1.0), 4, 1)
    whoosh = bp(rng.standard_normal(N), 300, 1400) * lp(wander(N, 2.5, 0.0, 1.0), 2, 1) ** 2 * 0.25
    flame_hiss = bp(rng.standard_normal(N), 900, 6000) * 0.0025 * lp(wander(N, 3, 0.4, 1.0), 3, 1)
    mix[:, ch] += (roar / (np.abs(roar).mean() + 1e-9) * 0.06 + whoosh * 0.02 + flame_hiss) * flicker

# 2. crackles: bursts of sharp ticks as pockets of moisture and sap burst
crackle = np.zeros((N, 2))
t = 0.2
while t < SECONDS:
    t += rng.exponential(0.35)
    k0 = int(t * SR)
    pan = rng.uniform(-0.7, 0.7); a = (pan + 1) * np.pi / 4
    burst_loud = rng.lognormal(-0.3, 0.4)
    pos = k0
    for _ in range(rng.integers(1, 16)):
        pos += int(rng.exponential(0.025) * SR) + 40
        if pos >= N - 3000:
            break
        L = int(rng.uniform(0.0008, 0.004) * SR)
        f = np.exp(rng.uniform(np.log(1200), np.log(7500)))
        tick = rng.standard_normal(L) * np.exp(-np.linspace(0, rng.uniform(4, 9), L))
        tick = resonator(tick, f, f * rng.uniform(0.3, 0.9)) * 2 + hp(tick, 2500) * 0.4
        amp = burst_loud * rng.lognormal(-2.6, 0.5)
        crackle[pos:pos + L, 0] += tick * amp * np.cos(a)
        crackle[pos:pos + L, 1] += tick * amp * np.sin(a)
mix += crackle

# 3. a log shifting or popping, now and then: a soft, woody thump
t = rng.uniform(2, 6)
while t < SECONDS - 1:
    k = int(t * SR); L = int(0.12 * SR)
    tt = np.arange(L) / SR
    thump = lp(rng.standard_normal(L), rng.uniform(300, 700)) * np.exp(-tt / 0.03)
    thump += np.sin(2 * np.pi * rng.uniform(90, 160) * tt) * np.exp(-tt / 0.05) * 0.5
    pan = rng.uniform(-0.4, 0.4); a = (pan + 1) * np.pi / 4
    amp = rng.uniform(0.06, 0.14)
    mix[k:k + L, 0] += thump * amp * np.cos(a)
    mix[k:k + L, 1] += thump * amp * np.sin(a)
    t += rng.uniform(4, 11)

# 4. sap hissing from the end of a log, rarely
for start in rng.uniform(3, SECONDS - 6, 3):
    k = int(start * SR); L = int(rng.uniform(1.5, 3.5) * SR)
    tt = np.linspace(0, 1, L)
    hiss = bp(rng.standard_normal(L), 3000, 7000) * np.sin(np.pi * tt) ** 2 * (0.7 + 0.3 * np.sin(2 * np.pi * 7 * tt * L / SR))
    mix[k:k + L, 0] += hiss * 0.004; mix[k:k + L, 1] += hiss * 0.006

# 5. a small room around the fireplace
def room_ir(seconds=0.6, rt60=0.35):
    n = int(seconds * SR); tt = np.arange(n) / SR; ir = np.zeros((n, 2))
    for ch in range(2):
        tail = rng.standard_normal(n) * np.exp(-6.9 * tt / rt60)
        tail = lp(tail, 5000)
        for d in rng.uniform(0.003, 0.03, 8):
            tail[int(d * SR)] += rng.uniform(0.2, 0.6) * rng.choice([-1, 1])
        tail[0] = 0
        ir[:, ch] = tail / np.sqrt((tail ** 2).sum())
    return ir

ir = room_ir()
wet = np.stack([fftconvolve(mix[:, c], ir[:, c])[:N] for c in range(2)], axis=1)
out = mix * 0.8 + wet * 0.35
out = hp(out, 40)
out /= np.abs(out).max() + 1e-9
wavfile.write(sys.argv[1], SR, (out * 0.7).astype(np.float32))
print("fire rendered", SECONDS, "s")
