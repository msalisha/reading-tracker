"""Gently re-balance a sound's tone to match a reference recording's average spectrum (octave-smoothed).
usage: match_eq.py RENDERED.wav REFERENCE OUT.wav [--max 18]"""
import sys, subprocess, numpy as np
from scipy.io import wavfile
SR = 44100
def load(f, ch=None):
    args = ["ffmpeg","-v","error","-i",f,"-ar",str(SR)] + (["-ac",str(ch)] if ch else []) + ["-f","f32le","-"]
    return np.frombuffer(subprocess.run(args, capture_output=True).stdout, np.float32)
src, ref, out = sys.argv[1], sys.argv[2], sys.argv[3]
limit = float(sys.argv[sys.argv.index("--max") + 1]) if "--max" in sys.argv else 18
x = load(src, 2).reshape(-1, 2).astype(np.float64)
r = load(ref, 1).astype(np.float64)

def smooth_spectrum(sig, nfft=8192):
    frames = np.lib.stride_tricks.sliding_window_view(sig, nfft)[::nfft // 2]
    S = (np.abs(np.fft.rfft(frames * np.hanning(nfft), axis=1)) ** 2).mean(0)
    f = np.fft.rfftfreq(nfft, 1 / SR)
    out = np.empty_like(S)
    for i, fi in enumerate(f):  # third-octave smoothing
        lo, hi = fi / 2 ** (1 / 6), fi * 2 ** (1 / 6)
        m = (f >= lo) & (f <= hi)
        out[i] = S[m].mean() if m.any() else S[i]
    return f, out

f, Sx = smooth_spectrum(x.mean(1))
_, Sr = smooth_spectrum(r)
gain_db = 10 * np.log10((Sr / Sr.sum()) / (Sx / Sx.sum()) + 1e-20)
gain_db = np.clip(gain_db, -limit, limit)
gain_db[f < 30] = gain_db[np.argmin(np.abs(f - 30))]
g = 10 ** (gain_db / 20)
Y = np.fft.rfft(x, axis=0)
fy = np.fft.rfftfreq(len(x), 1 / SR)
Y *= np.interp(fy, f, g)[:, None]
y = np.fft.irfft(Y, len(x), axis=0)
y /= np.abs(y).max() + 1e-9
wavfile.write(out, SR, (y * 0.7).astype(np.float32))
print("matched tone of", src.split("/")[-1], "to", ref.split("/")[-1])
