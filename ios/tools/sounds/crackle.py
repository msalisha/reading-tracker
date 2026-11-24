"""Add crackles to a generated fire bed. The crackles are new, but their timing, loudness, tone and length are
measured from a reference recording (measured, never copied).

usage: crackle.py REFERENCE BED.wav OUT.wav [--gain 1.0] [--seed 1]   -> stereo wav, same length as the bed, loop-safe
"""
import argparse, subprocess
import numpy as np
from scipy.io import wavfile
from scipy.signal import butter, sosfiltfilt

SR = 44100
ap = argparse.ArgumentParser()
ap.add_argument("ref"); ap.add_argument("bed"); ap.add_argument("out")
ap.add_argument("--gain", type=float, default=1.0)
ap.add_argument("--seed", type=int, default=1)
a = ap.parse_args()
rng = np.random.default_rng(a.seed)

ref = np.frombuffer(subprocess.run(["ffmpeg", "-v", "error", "-i", a.ref, "-ac", "1", "-ar", str(SR), "-f", "f32le", "-"],
                                   capture_output=True, check=True).stdout, np.float32).astype(float)
ref /= ref.std()
_, bed = wavfile.read(a.bed); bed = bed.astype(float); bed /= bed.std()

# ---- measure the reference's crackles
hf = sosfiltfilt(butter(4, 1500, "high", fs=SR, output="sos"), ref)
BLK = 64
env = np.abs(hf)[: len(hf) // BLK * BLK].reshape(-1, BLK).max(1)
med = np.median(env)
is_peak = (env[1:-1] > env[:-2]) & (env[1:-1] >= env[2:]) & (env[1:-1] > 3.0 * med)
idx = np.nonzero(is_peak)[0] + 1
times = idx * BLK / SR
amps = env[idx] / med                                   # each crackle's size, relative to the fire's steady hiss
gaps = np.diff(times)
W = int(0.012 * SR); PRE = int(0.001 * SR)
spec = np.zeros(W // 2 + 1); shape = np.zeros(W); count = 0
for i in idx[amps > 5]:
    c = i * BLK + int(np.argmax(np.abs(hf[i * BLK:(i + 1) * BLK])))
    if c - PRE < 0 or c - PRE + W > len(ref): continue
    seg = ref[c - PRE:c - PRE + W]
    spec += np.abs(np.fft.rfft(seg * np.hanning(W))) / (np.abs(seg).max() + 1e-9)
    shape += np.abs(seg) / (np.abs(seg).max() + 1e-9); count += 1
spec /= count; shape /= count
shape = np.convolve(shape, np.ones(16) / 16, "same"); shape /= shape.max()
print(f"reference: {len(idx)/(len(ref)/SR):.1f} crackles/s, median gap {np.median(gaps)*1000:.0f} ms, sizes "
      f"{np.round(np.percentile(amps,[50,90,99]),1)}, {count} large ones measured")

# ---- make new crackles with the same statistics
n = len(bed)
layer = np.zeros((n, 2))
hiss_level = np.median(np.abs(sosfiltfilt(butter(4, 1500, "high", fs=SR, output="sos"), bed))[: n // BLK * BLK].reshape(-1, BLK).max(1))
t = rng.uniform(0, 0.3)
made = 0
while t < n / SR:
    size = rng.choice(amps) * rng.lognormal(0, 0.25)
    L = int(W * rng.uniform(0.6, 1.5))
    e = np.interp(np.linspace(0, W - 1, L), np.arange(W), shape)
    # a fresh burst of noise with the measured crackle tone (random tilt so no two are alike)
    burst = rng.standard_normal(L)
    F = np.fft.rfft(burst)
    f = np.fft.rfftfreq(L, 1 / SR)
    tone = np.interp(f, np.fft.rfftfreq(W, 1 / SR), spec) * (np.maximum(f, 200) / 3000) ** rng.normal(0, 0.35) * f / (f + 900)
    c = np.fft.irfft(F / (np.abs(F) + 1e-9) * tone, L) * e
    c *= size * hiss_level / (np.abs(c).max() + 1e-9) * a.gain
    pan = rng.uniform(0.15, 0.85)
    k = int(t * SR)
    pos = (k + np.arange(L)) % n                         # wraps round the end, so the loop stays seamless
    layer[pos, 0] += c * np.cos(pan * np.pi / 2); layer[pos, 1] += c * np.sin(pan * np.pi / 2)
    t += rng.choice(gaps) * rng.lognormal(0, 0.3); made += 1
print(f"made {made} crackles ({made/(n/SR):.1f}/s)")

# the bed, a different stretch in each ear with a little shared, so it is wide but not split
other = np.roll(bed, n // 2)
stereo = np.stack([bed + 0.35 * other, other + 0.35 * bed], axis=1) / 1.06
out = stereo + layer * np.sqrt(2)
out /= np.abs(out).max() + 1e-9
wavfile.write(a.out, SR, (out * 0.9).astype(np.float32))
print("wrote", a.out)
