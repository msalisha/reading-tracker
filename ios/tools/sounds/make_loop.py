"""Turn a field recording into a seamless, loudness-matched stereo loop for Pageturner.
usage: make_loop.py SRC OUT.m4a --seconds 80 [--shuffle] [--roar DB] [--start S]"""
import argparse, subprocess, numpy as np
SR = 44100
ap = argparse.ArgumentParser()
ap.add_argument("src"); ap.add_argument("out")
ap.add_argument("--seconds", type=float, default=80)
ap.add_argument("--shuffle", action="store_true", help="build the loop from shuffled pieces (for short sources)")
ap.add_argument("--roar", type=float, default=None, help="add a low fire roar at this level (dB below the recording)")
ap.add_argument("--start", type=float, default=None)
ap.add_argument("--target", type=float, default=-24.0, help="loudness (dBFS RMS)")
ap.add_argument("--highpass", type=float, default=0)
a = ap.parse_args()

def decode(path):
    ch = int(subprocess.run(["ffprobe","-v","error","-select_streams","a:0","-show_entries","stream=channels","-of","csv=p=0",path],capture_output=True,text=True).stdout.strip() or 1)
    raw = subprocess.run(["ffmpeg","-v","error","-i",path,"-ar",str(SR),"-f","f32le","-"],capture_output=True).stdout
    x = np.frombuffer(raw, dtype=np.float32).reshape(-1, ch)
    return x[:, :2] if ch >= 2 else x

x = decode(a.src)
if a.highpass:  # gentle one-pole high-pass to remove rumble/handling noise
    k = np.exp(-2*np.pi*a.highpass/SR); y = np.zeros_like(x); lp = np.zeros(x.shape[1], dtype=np.float32)
    for i in range(len(x)): lp = k*lp + (1-k)*x[i]; y[i] = x[i]-lp
    x = y
L = int(a.seconds*SR); C = int(3*SR)
rng = np.random.default_rng(7)

def steadiest(x, n):
    """Start of the steadiest n samples: least loudness wobble, no sudden peaks."""
    if len(x) <= n: return 0
    mono = np.abs(x).mean(1); blk = SR//2
    nb = len(mono)//blk; r = np.sqrt((mono[:nb*blk].reshape(nb, blk)**2).mean(1)) + 1e-9
    db = 20*np.log10(r); w = n//blk; best, bs = 0, 1e9
    for s in range(0, nb-w, 2):
        seg = db[s:s+w]; score = seg.std() + 0.5*(seg.max()-np.median(seg))
        if score < bs: bs, best = score, s
    return best*blk

if a.shuffle:
    piece, fade = int(4.5*SR), int(0.8*SR)
    out = np.zeros((L + C + piece, x.shape[1]), np.float32); pos = 0
    ramp = np.linspace(0, 1, fade, dtype=np.float32)[:, None]
    while pos < L + C:
        s = rng.integers(0, len(x)-piece); p = x[s:s+piece].copy()
        p[:fade] *= np.sqrt(ramp); p[-fade:] *= np.sqrt(1-ramp)
        out[pos:pos+piece] += p; pos += piece - fade
    seg = out[:L+C]
else:
    s0 = int(a.start*SR) if a.start is not None else steadiest(x, L + C)
    seg = x[s0:s0+L+C]
    if len(seg) < L + C: raise SystemExit("source too short for that loop length")

# seamless loop: the stretch just after the end is crossfaded into the start
t = np.linspace(0, np.pi/2, C, dtype=np.float32)[:, None]
loop = seg[:L].copy()
loop[:C] = seg[:C]*np.sin(t) + seg[L:L+C]*np.cos(t)

if loop.shape[1] == 1:  # mono recording: a different stretch in each ear gives natural width
    loop = np.concatenate([loop, np.roll(loop, L//2, axis=0)], axis=1)

if a.roar is not None:  # a soft low roar under crackles, made loop-safe the same way
    n = L + C; w = rng.standard_normal((n, 2)).astype(np.float32)
    b = np.zeros_like(w); acc = np.zeros(2, np.float32); k = np.exp(-2*np.pi*180/SR)
    for i in range(n): acc = k*acc + (1-k)*w[i]; b[i] = acc
    flick = 0.75 + 0.25*np.sin(np.linspace(0, 2*np.pi*7, n))[:, None]*np.sin(np.linspace(0, 2*np.pi*3, n)+1)[:, None]
    b *= flick.astype(np.float32)
    roar = b[:L].copy(); roar[:C] = b[:C]*np.sin(t) + b[L:L+C]*np.cos(t)
    rr = np.sqrt((roar**2).mean()); lr = np.sqrt((loop**2).mean())
    loop = loop + roar * (lr/rr) * 10**(-a.roar/20)

rms = np.sqrt((loop**2).mean()); loop *= 10**(a.target/20)/rms
peak = np.abs(loop).max()
if peak > 0.89: loop = np.tanh(loop/0.89)*0.89  # soft limit any rare peaks
# Encoders smear the very end of a file, so add 8192 samples (the start of the loop again) past the loop point.
# The app drops these extra samples before looping (FocusSoundPlayer.loopTail), so the seam stays clean.
TAIL = 8192
padded = np.concatenate([loop, loop[:TAIL]], axis=0)
subprocess.run(["ffmpeg","-v","error","-y","-f","f32le","-ar",str(SR),"-ac","2","-i","-","-c:a","aac","-b:a","160k",a.out],
               input=padded.astype(np.float32).tobytes(), check=True)
print(f"{a.out.split('/')[-1]}: {L/SR:.0f}s loop, rms {20*np.log10(np.sqrt((loop**2).mean())):.1f} dBFS, peak {20*np.log10(np.abs(loop).max()):.1f} dBFS")
