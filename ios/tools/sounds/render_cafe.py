"""Render a café ambience: murmuring tables, cups and cutlery, an espresso machine, in a real-sounding room.
Writes a stereo 44.1 kHz float WAV, slightly longer than the loop so the loop maker can crossfade the seam."""
import sys
import numpy as np
from scipy.signal import lfilter, butter, sosfilt, fftconvolve
from scipy.io import wavfile

SR = 44100
SECONDS = float(sys.argv[2]) if len(sys.argv) > 2 else 94
N = int(SECONDS * SR)
rng = np.random.default_rng(2026)
out = np.zeros((N, 2), np.float32)


def pan(sig, p):
    a = (p + 1) * np.pi / 4
    return np.stack([sig * np.cos(a), sig * np.sin(a)], axis=1)


def add(buf, start, sig):
    if start >= len(buf):
        return
    end = min(len(buf), start + len(sig))
    buf[start:end] += sig[: end - start]


def resonator(x, f, bw):
    """Two-pole resonance at f Hz with bandwidth bw Hz (unit gain at the peak)."""
    r = np.exp(-np.pi * bw / SR)
    th = 2 * np.pi * f / SR
    b = [(1 - r * r) * 0.5, 0, -(1 - r * r) * 0.5]
    a = [1, -2 * r * np.cos(th), r * r]
    return lfilter(b, a, x)


def lowpass(x, f, order=2):
    return sosfilt(butter(order, f, "low", fs=SR, output="sos"), x, axis=0)


def highpass(x, f, order=2):
    return sosfilt(butter(order, f, "high", fs=SR, output="sos"), x, axis=0)


def bandpass(x, lo, hi, order=2):
    return sosfilt(butter(order, [lo, hi], "band", fs=SR, output="sos"), x, axis=0)


def pink(n):
    w = rng.standard_normal(n)
    f = np.fft.rfft(w)
    k = np.arange(len(f)); k[0] = 1
    return np.fft.irfft(f / np.sqrt(k), n).astype(np.float32)


# ---------------------------------------------------------------- voices
VOWELS = {  # F1, F2, F3 (adult male; female/young voices are scaled up)
    "a": (730, 1090, 2440), "i": (270, 2290, 3010), "u": (300, 870, 2240), "e": (530, 1840, 2480),
    "o": (570, 840, 2410), "ae": (660, 1720, 2410), "uh": (520, 1190, 2390), "er": (490, 1350, 1690),
    "ih": (390, 1990, 2550), "oo": (440, 1020, 2240),
}
VK = list(VOWELS)


def glottal(f0_track):
    """Differentiated Rosenberg glottal pulses following a pitch track, with a little jitter and breath."""
    phase = np.cumsum(f0_track / SR) % 1.0
    flow = np.where(phase < 0.4, 0.5 * (1 - np.cos(np.pi * phase / 0.4)),
                    np.where(phase < 0.6, np.cos(np.pi * (phase - 0.4) / 0.4), 0.0))
    src = np.diff(flow, prepend=0.0) * 40
    breath = rng.standard_normal(len(src)) * 0.04 * (0.5 + flow)
    return (src + breath).astype(np.float32)


def syllable(f0, scale, stress, dur):
    """One syllable: an optional consonant then a vowel, as a short waveform."""
    parts = []
    kind = rng.random()
    if kind < 0.28:  # fricative: s, sh, f, h
        cdur = int(rng.uniform(0.05, 0.11) * SR)
        lo, hi = rng.choice([(3500, 8000), (2000, 5000), (1200, 6000), (600, 3000)])
        n = bandpass(rng.standard_normal(cdur), lo, hi) * np.hanning(cdur) * rng.uniform(0.04, 0.12)
        parts.append(n)
    elif kind < 0.5:  # plosive: short closure then a burst
        parts.append(np.zeros(int(rng.uniform(0.02, 0.05) * SR)))
        b = int(0.012 * SR)
        parts.append(bandpass(rng.standard_normal(b), 900, 5000) * np.exp(-np.linspace(0, 6, b)) * 0.2)
    elif kind < 0.62:  # nasal: m, n
        ndur = int(rng.uniform(0.05, 0.09) * SR)
        g = glottal(np.full(ndur, f0))
        v = resonator(g, 260 * scale, 80) + 0.25 * resonator(g, 1100 * scale, 150)
        parts.append(v * np.hanning(ndur) * 0.5)
    vdur = int(dur * SR)
    t = np.linspace(0, 1, vdur)
    track = f0 * (1 + stress * 0.18 * np.sin(np.pi * t)) * (1 + 0.012 * rng.standard_normal() )
    track = track * (1 + 0.006 * np.sin(2 * np.pi * rng.uniform(4, 7) * t * dur))
    g = glottal(track)
    v1, v2 = VOWELS[VK[rng.integers(len(VK))]], VOWELS[VK[rng.integers(len(VK))]]
    half = vdur // 2
    out_v = np.zeros(vdur)
    for seg, (F1, F2, F3) in ((slice(0, half + 400), v1), (slice(half - 400, vdur), v2)):  # glide between two vowel shapes
        s = g[seg]
        y = resonator(s, F1 * scale, 90) + 0.6 * resonator(s, F2 * scale, 120) + 0.25 * resonator(s, F3 * scale, 180)
        w = np.ones(len(y)); r = min(400, len(y) // 2)
        w[:r] = np.linspace(0, 1, r) if seg.start else 1; w[-r:] = np.linspace(1, 0, r) if seg.stop < vdur else 1
        out_v[seg] += y * w
    env = np.minimum(1, t / 0.18) * np.minimum(1, (1 - t) / 0.35)
    parts.append(out_v * env * (0.7 + 0.5 * stress))
    return np.concatenate(parts).astype(np.float32)


def talker(total, deep, start_quiet):
    f0 = rng.uniform(95, 135) if deep else rng.uniform(175, 240)
    scale = 1.0 if deep else rng.uniform(1.12, 1.2)
    sig = np.zeros(total, np.float32)
    pos = int(start_quiet * SR)
    while pos < total:
        # one utterance: a phrase with falling pitch, stresses and a natural pace
        n_syl = rng.integers(4, 18)
        pitch = f0 * rng.uniform(1.05, 1.2)
        rate = rng.uniform(4.2, 6.5)
        for k in range(n_syl):
            stress = 1.0 if rng.random() < 0.3 else 0.0
            syl = syllable(pitch * (1 - 0.18 * k / n_syl), scale, stress, rng.uniform(0.07, 0.2) + 0.06 * stress)
            add(sig, pos, syl)
            pos += int(SR / rate * rng.uniform(0.7, 1.3))
            if rng.random() < 0.06:
                pos += int(rng.uniform(0.15, 0.35) * SR)  # little hesitation
        pos += int(rng.uniform(0.5, 3.2) * SR)  # the other person talks
        if rng.random() < 0.1:  # a laugh: a few breathy, higher syllables
            for _ in range(rng.integers(3, 6)):
                add(sig, pos, syllable(f0 * 1.5, scale, 1, 0.09) * 0.8)
                pos += int(0.14 * SR)
    return sig


voices = np.zeros((N, 2), np.float32)
tables = 7
for t in range(tables):
    distance = rng.uniform(0.35, 1.0)        # 1 = far
    p = rng.uniform(-0.9, 0.9)
    for person in range(2):                  # two people at each table, taking turns
        s = talker(N, deep=rng.random() < 0.5, start_quiet=rng.uniform(0, 4) + person * 1.5)
        s = lowpass(s, 5500 - 3200 * distance)
        voices += pan(s * (1.15 - 0.85 * distance), np.clip(p + rng.uniform(-0.15, 0.15), -1, 1))

# ---------------------------------------------------------------- crockery, cutlery, machine
events = np.zeros((N, 2), np.float32)


def clink(f, amp, decay_scale=1.0):
    n = int(0.9 * SR)
    t = np.arange(n) / SR
    ratios = [1, 2.61, 4.82, 7.4, 9.9]
    s = np.zeros(n)
    for i, r in enumerate(ratios):
        fr = f * r * rng.uniform(0.985, 1.015)
        if fr > SR * 0.45:
            continue
        s += np.sin(2 * np.pi * fr * t + rng.uniform(0, 6)) * np.exp(-t / (decay_scale * rng.uniform(0.08, 0.35) / (1 + i * 0.6))) / (1 + i)
    click = highpass(rng.standard_normal(200), 2000) * np.exp(-np.linspace(0, 8, 200))
    s[:200] += click * 0.6
    return (s * amp).astype(np.float32)


t = 0.0
while t < SECONDS:
    t += rng.exponential(1.6)
    pos = int(t * SR)
    kind = rng.random()
    p = rng.uniform(-0.95, 0.95)
    if kind < 0.55:   # cup on saucer (sometimes a double tap)
        c = clink(rng.uniform(1700, 3200), rng.uniform(0.03, 0.09))
        add(events, pos, pan(c, p))
        if rng.random() < 0.4:
            add(events, pos + int(rng.uniform(0.05, 0.12) * SR), pan(clink(rng.uniform(1700, 3200), rng.uniform(0.02, 0.05)), p))
    elif kind < 0.75:  # spoon stirring
        f = rng.uniform(4500, 7000)
        for k in range(rng.integers(6, 14)):
            add(events, pos + int(k * rng.uniform(0.11, 0.16) * SR), pan(clink(f, rng.uniform(0.008, 0.02), 0.25), p))
    elif kind < 0.9:   # knife and fork on a plate
        n = int(rng.uniform(0.25, 0.7) * SR)
        sc = bandpass(rng.standard_normal(n), 2200, 6000) * np.hanning(n) * (0.6 + 0.4 * np.sin(np.linspace(0, 40, n)) ** 2)
        add(events, pos, pan((sc * rng.uniform(0.01, 0.025)).astype(np.float32), p))
    else:              # a chair moved
        n = int(rng.uniform(0.3, 0.6) * SR)
        f0 = rng.uniform(90, 180)
        tt = np.arange(n) / SR
        sc = (np.sign(np.sin(2 * np.pi * f0 * tt * (1 + 0.2 * tt))) * 0.3 + rng.standard_normal(n) * 0.4)
        sc = bandpass(sc, 150, 1800) * np.hanning(n) * rng.uniform(0.01, 0.02)
        add(events, pos, pan(sc.astype(np.float32), p))

# espresso machine, behind the counter: grinder, then the steam wand, a couple of times
for start in rng.uniform(5, SECONDS - 25, 2):
    pos = int(start * SR)
    n = int(rng.uniform(4, 6) * SR)
    tt = np.arange(n) / SR
    motor = sum(np.sin(2 * np.pi * 148 * h * tt) / h for h in range(1, 12)) * 0.3
    grind = highpass(rng.standard_normal(n), 1500) * 0.5 * (0.7 + 0.3 * np.sin(2 * np.pi * 9 * tt) ** 2)
    env = np.minimum(1, tt / 0.15) * np.minimum(1, (tt[-1] - tt) / 0.2)
    add(events, pos, pan(((motor + grind) * env * 0.02).astype(np.float32), 0.65))
    pos += n + int(rng.uniform(8, 14) * SR)
    n = int(rng.uniform(5, 8) * SR)
    tt = np.arange(n) / SR
    steam = bandpass(rng.standard_normal(n), 2500, 9000) * (0.8 + 0.2 * np.sin(2 * np.pi * rng.uniform(3, 6) * tt))
    gurgle = bandpass(rng.standard_normal(n), 300, 1200) * (np.sin(2 * np.pi * 11 * tt) > 0.3) * 0.5
    env = np.minimum(1, tt / 0.3) * np.minimum(1, (tt[-1] - tt) / 0.6)
    add(events, pos, pan(((steam + gurgle) * env * 0.018).astype(np.float32), 0.7))

# ---------------------------------------------------------------- the room
def room_ir(seconds=1.1, rt60=0.65):
    n = int(seconds * SR)
    t = np.arange(n) / SR
    ir = np.zeros((n, 2))
    for ch in range(2):
        tail = rng.standard_normal(n) * np.exp(-6.9 * t / rt60)
        tail = lowpass(tail, 6000) * 0.6 + tail * 0.4 * np.exp(-t * 8)  # high frequencies die away faster
        for d in rng.uniform(0.004, 0.045, 10):  # early reflections off walls and tables
            tail[int(d * SR)] += rng.uniform(0.3, 0.8) * rng.choice([-1, 1])
        tail[0] = 0
        ir[:, ch] = tail / np.sqrt((tail ** 2).sum())
    return ir


ir = room_ir()
wet = np.zeros_like(voices)
dry_mix = voices * 0.35 + events * 0.6
src = voices + events * 0.8
for ch in range(2):
    wet[:, ch] = fftconvolve(src[:, ch], ir[:, ch])[:N]
room_tone = pan(lowpass(pink(N), 350) * 0.02, 0.0) + pan(resonator(rng.standard_normal(N), 100, 3) * 0.004, -0.3)
mix = dry_mix + wet * 0.9 + room_tone
mix = highpass(mix, 70)
mix /= np.abs(mix).max() + 1e-9
wavfile.write(sys.argv[1], SR, (mix * 0.7).astype(np.float32))
print("café rendered", mix.shape[0] / SR, "s")
