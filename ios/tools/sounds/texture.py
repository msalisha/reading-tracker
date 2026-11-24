"""Generate a brand-new sound texture (rain, fire...) that has the same measured character as a reference recording.

The reference is only measured, never copied: we take statistics of how loud each of ~34 frequency bands is from
moment to moment (the spread of loudness, its rhythm, and how bands move together), then shape random noise until
it has the same statistics (after McDermott & Simoncelli, "Sound texture perception via statistics of the auditory
periphery", 2011). The result is periodic, so it loops with no join.

usage: texture.py REFERENCE OUT.wav --seconds 70 [--iterations 40] [--seed 1] [--ref-start S --ref-seconds S]
"""
import argparse, subprocess
import numpy as np
from scipy import fft as sfft
from scipy.io import wavfile
from scipy.linalg import sqrtm

SR = 44100
DEC = 30            # envelopes are tracked at 1470 Hz: fine enough for the snap of a crackle or a drop
COMP = 0.3          # loudness compression, as in the ear
NBANDS = 34

ap = argparse.ArgumentParser()
ap.add_argument("ref"); ap.add_argument("out")
ap.add_argument("--seconds", type=float, default=70)
ap.add_argument("--iterations", type=int, default=40)
ap.add_argument("--seed", type=int, default=1)
ap.add_argument("--ref-start", type=float, default=0)
ap.add_argument("--ref-seconds", type=float, default=None)
a = ap.parse_args()
rng = np.random.default_rng(a.seed)


def decode(path):
    cmd = ["ffmpeg", "-v", "error", "-ss", str(a.ref_start)] + (["-t", str(a.ref_seconds)] if a.ref_seconds else []) + \
          ["-i", path, "-ac", "1", "-ar", str(SR), "-f", "f32le", "-"]
    return np.frombuffer(subprocess.run(cmd, capture_output=True, check=True).stdout, np.float32).astype(np.float64)


def erb(f): return 21.4 * np.log10(1 + 0.00437 * f)
def erb_inv(e): return (10 ** (e / 21.4) - 1) / 0.00437


def filters(n):
    """Half-cosine bands evenly spaced on the ear's frequency scale; their squares sum to one."""
    f = sfft.rfftfreq(n, 1 / SR)
    edges = np.linspace(erb(30), erb(18000), NBANDS + 2)
    e = erb(np.maximum(f, 1e-3))
    bank = []
    for k in range(NBANDS):
        lo, mid, hi = edges[k], edges[k + 1], edges[k + 2]
        w = np.zeros(len(f))
        up = (e >= lo) & (e < mid); dn = (e >= mid) & (e < hi)
        w[up] = np.sin(np.pi / 2 * (e[up] - lo) / (mid - lo))
        w[dn] = np.cos(np.pi / 2 * (e[dn] - mid) / (hi - mid))
        bank.append(w)
    bank = np.array(bank)
    low = np.where(e < edges[1], np.sqrt(np.clip(1 - bank[0] ** 2, 0, 1)), 0)      # below the first band
    high = np.where(e >= edges[-2], np.sqrt(np.clip(1 - bank[-1] ** 2, 0, 1)), 0)  # above the last
    return np.vstack([low, bank, high])


def subband(X, w, n):
    """Analytic (complex) subband from the signal's spectrum X and one filter."""
    full = np.zeros(n, np.complex128)
    full[: len(X)] = X * w * 2
    full[0] = X[0] * w[0]
    return sfft.ifft(full, workers=4)


def envelopes(x, bank):
    n = len(x); X = sfft.rfft(x, workers=4); m = n // DEC
    E = np.empty((m, len(bank)))
    for k, w in enumerate(bank):
        env = np.abs(subband(X, w, n))
        E[:, k] = env[: m * DEC].reshape(m, DEC).mean(1) ** COMP
    return E


def mod_spectrum(E, nseg):
    """Average modulation power (how each band's loudness fluctuates over time), per band."""
    hop = nseg // 2; win = np.hanning(nseg)[:, None]
    acc = 0; c = 0
    for s in range(0, len(E) - nseg + 1, hop):
        seg = E[s:s + nseg] - E[s:s + nseg].mean(0)
        acc = acc + np.abs(np.fft.rfft(seg * win, axis=0)) ** 2; c += 1
    return acc / max(c, 1)


# ---- measure the reference
ref = decode(a.ref)
ref = ref[: len(ref) // DEC * DEC]
Er = envelopes(ref, filters(len(ref)))
nseg = min(len(Er) // 4 * 2, int(8 * SR / DEC) // 2 * 2)        # up to 8 s windows: rhythms down to ~0.1 Hz
Pr = mod_spectrum(Er, nseg)
fr_mod = np.fft.rfftfreq(nseg, DEC / SR)
mean_r = Er.mean(0)
Cr = np.cov(Er, rowvar=False)
sorted_r = np.sort(Er, axis=0)
print(f"reference: {len(ref)/SR:.1f}s, {Er.shape[1]} bands")

# ---- shape noise to match
n = int(a.seconds * SR) // DEC * DEC
m = n // DEC
bank = filters(n)
x = rng.standard_normal(n) * ref.std()
fs_mod = np.fft.rfftfreq(m, DEC / SR)
target_mod = np.empty((len(fs_mod), Er.shape[1]))
for k in range(Er.shape[1]):
    target_mod[:, k] = np.sqrt(np.interp(fs_mod, fr_mod, Pr[:, k]))
target_mod[0] = 0
quant = (np.arange(m) + 0.5) / m
target_sorted = np.empty((m, Er.shape[1]))
for k in range(Er.shape[1]):
    target_sorted[:, k] = np.interp(quant, (np.arange(len(sorted_r)) + 0.5) / len(sorted_r), sorted_r[:, k])
Cr_half = np.real(sqrtm(Cr))
tt_full = (np.arange(n) + 0.5) / DEC - 0.5

for it in range(a.iterations):
    X = sfft.rfft(x, workers=4)
    subs = []; E = np.empty((m, len(bank)))
    for k, w in enumerate(bank):
        s = subband(X, w, n).astype(np.complex64); subs.append(s)
        E[:, k] = np.abs(s).reshape(m, DEC).mean(1) ** COMP
    E0 = E.copy()
    for _ in range(2):
        # 1. rhythm of each band's loudness
        F = np.fft.rfft(E - E.mean(0), axis=0)
        mag = np.abs(F) + 1e-12
        scale = np.sqrt((target_mod ** 2).sum(0) / ((mag ** 2).sum(0) - mag[0] ** 2 + 1e-12))
        blend = target_mod / scale                         # same shape as the reference, same total power as now
        E = np.fft.irfft(F / mag * blend, m, axis=0)
        # 2. how bands rise and fall together
        Cs = np.cov(E, rowvar=False) + 1e-9 * np.eye(E.shape[1])
        Cs_ih = np.linalg.inv(np.real(sqrtm(Cs)))
        E = (E - E.mean(0)) @ (Cs_ih @ Cr_half) + mean_r
        # 3. the exact spread of loud and quiet moments in each band
        order = np.argsort(E, axis=0)
        for k in range(E.shape[1]):
            E[order[:, k], k] = target_sorted[:, k]
    floor = 0.02 * mean_r                                  # never divide by a near-silent moment
    gain = (np.maximum(E, floor) / np.maximum(E0, floor)) ** (1 / COMP)
    gain = np.clip(gain, 0.05, 12.0)                       # change each moment gradually; later passes finish the job
    y = np.zeros(n)
    for k, w in enumerate(bank):
        g = np.interp(tt_full, np.arange(-1, m + 1), np.concatenate([gain[-1:, k], gain[:, k], gain[:1, k]]))  # wraps around
        shaped = (subs[k] * g).real
        y += sfft.irfft(sfft.rfft(shaped, workers=4) * w, n, workers=4)
    x = y
    if it % 5 == 4 or it == a.iterations - 1:
        Ex = envelopes(x, bank)
        err_c = np.linalg.norm(np.cov(Ex, rowvar=False) - Cr) / np.linalg.norm(Cr)
        err_m = np.abs(Ex.mean(0) - mean_r).max() / mean_r.max()
        print(f"iteration {it+1}: covariance error {err_c:.3f}, mean error {err_m:.3f}", flush=True)

x = x / (np.abs(x).max() + 1e-9) * 0.7
wavfile.write(a.out, SR, x.astype(np.float32))
print("wrote", a.out, f"{n/SR:.1f}s (periodic: loops with no join)")
