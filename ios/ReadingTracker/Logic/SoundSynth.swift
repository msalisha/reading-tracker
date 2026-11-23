import Foundation

// Focus sounds, generated live in stereo. Each sound is a few layers that mimic how the real thing is made:
// many tiny events (drops, crackles, syllables, bubbles) placed around you, over a soft bed, with slow
// natural variation, so it never loops. The app adds a little room echo on top (see FocusSoundPlayer).

/// Fast repeatable random numbers.
struct Noise {
    private var state: UInt32
    private var p0: Float = 0, p1: Float = 0, p2: Float = 0, p3: Float = 0, p4: Float = 0, p5: Float = 0, p6: Float = 0
    private var b: Float = 0

    init(_ seed: UInt32) { state = seed == 0 ? 0x9E37_79B9 : seed }

    /// −1…1
    mutating func white() -> Float {
        state ^= state << 13
        state ^= state >> 17
        state ^= state << 5
        return Float(state) * (2 / Float(UInt32.max)) - 1
    }

    /// 0…1
    mutating func unit() -> Float { white() * 0.5 + 0.5 }

    mutating func range(_ lo: Float, _ hi: Float) -> Float { lo + (hi - lo) * unit() }

    mutating func chance(_ perSecond: Float, _ sr: Float) -> Bool { unit() < perSecond / sr }

    /// Softer, "natural" noise.
    mutating func pink() -> Float {
        let w = white()
        p0 = 0.99886 * p0 + w * 0.0555179
        p1 = 0.99332 * p1 + w * 0.0750759
        p2 = 0.96900 * p2 + w * 0.1538520
        p3 = 0.86650 * p3 + w * 0.3104856
        p4 = 0.55000 * p4 + w * 0.5329522
        p5 = -0.7616 * p5 - w * 0.0168980
        let out = p0 + p1 + p2 + p3 + p4 + p5 + p6 + w * 0.5362
        p6 = w * 0.115926
        return out * 0.11
    }

    /// Deep rumbling noise.
    mutating func brown() -> Float {
        b = (b + 0.02 * white()) / 1.02
        return b * 3.5
    }
}

/// Standard two-pole filter (RBJ cookbook).
struct Biquad {
    private var b0: Float = 1, b1: Float = 0, b2: Float = 0, a1: Float = 0, a2: Float = 0
    private var z1: Float = 0, z2: Float = 0

    mutating func process(_ x: Float) -> Float {
        let y = b0 * x + z1
        z1 = b1 * x - a1 * y + z2
        z2 = b2 * x - a2 * y
        return y
    }

    private mutating func set(_ nb0: Double, _ nb1: Double, _ nb2: Double, _ a0: Double, _ na1: Double, _ na2: Double) {
        b0 = Float(nb0 / a0); b1 = Float(nb1 / a0); b2 = Float(nb2 / a0)
        a1 = Float(na1 / a0); a2 = Float(na2 / a0)
    }

    private static func w(_ f: Double, _ sr: Double) -> Double { 2 * Double.pi * min(f, sr * 0.45) / sr }

    mutating func lowpass(_ f: Double, q: Double = 0.707, sr: Double) {
        let w = Self.w(f, sr), c = cos(w), al = sin(w) / (2 * q)
        set((1 - c) / 2, 1 - c, (1 - c) / 2, 1 + al, -2 * c, 1 - al)
    }

    mutating func highpass(_ f: Double, q: Double = 0.707, sr: Double) {
        let w = Self.w(f, sr), c = cos(w), al = sin(w) / (2 * q)
        set((1 + c) / 2, -(1 + c), (1 + c) / 2, 1 + al, -2 * c, 1 - al)
    }

    /// Peak gain 1 at `f`.
    mutating func bandpass(_ f: Double, q: Double, sr: Double) {
        let w = Self.w(f, sr), c = cos(w), al = sin(w) / (2 * q)
        set(al, 0, -al, 1 + al, -2 * c, 1 - al)
    }
}

/// Equal-power left/right gains for a position from −1 (left) to 1 (right).
@inline(__always) func panGains(_ pan: Float) -> (Float, Float) {
    let a = (pan + 1) * Float.pi / 4
    return (cos(a), sin(a))
}

/// A slowly wandering value between lo and hi, for natural ebb and flow.
struct Drift {
    private var value: Float
    private var target: Float
    let lo: Float, hi: Float, speed: Float

    init(_ lo: Float, _ hi: Float, speed: Float) {
        self.lo = lo; self.hi = hi; self.speed = speed
        value = (lo + hi) / 2; target = value
    }

    mutating func next(_ n: inout Noise) -> Float {
        if abs(target - value) < (hi - lo) * 0.02 { target = n.range(lo, hi) }
        value += (target - value) * speed
        return value
    }
}

/// A short ringing tone (a drop on a leaf, a spoon on a cup), placed left or right.
struct Ping {
    var active = false
    var phase1: Float = 0, phase2: Float = 0, phase3: Float = 0
    var inc1: Float = 0, inc2: Float = 0, inc3: Float = 0
    var env: Float = 0, decay: Float = 0, amp: Float = 0
    var glide: Float = 1
    var gl: Float = 0, gr: Float = 0

    mutating func start(freq: Float, partials: (Float, Float), decaySeconds: Float, amp: Float, pan: Float, glide: Float = 1, sr: Float) {
        active = true
        phase1 = 0; phase2 = 0; phase3 = 0
        inc1 = 2 * .pi * freq / sr
        inc2 = inc1 * partials.0
        inc3 = inc1 * partials.1
        env = 1
        decay = exp(-1 / (decaySeconds * sr))
        self.amp = amp
        self.glide = glide
        (gl, gr) = panGains(pan)
    }

    mutating func next() -> (Float, Float) {
        guard active else { return (0, 0) }
        let s = (sin(phase1) + 0.45 * sin(phase2) + 0.2 * sin(phase3)) * env * amp
        phase1 += inc1; phase2 += inc2; phase3 += inc3
        inc1 *= glide; inc2 *= glide; inc3 *= glide
        if phase1 > 2 * .pi { phase1 -= 2 * .pi }
        if phase2 > 2 * .pi { phase2 -= 2 * .pi }
        if phase3 > 2 * .pi { phase3 -= 2 * .pi }
        env *= decay
        if env < 0.0005 { active = false }
        return (s * gl, s * gr)
    }
}

// MARK: - Rain

final class RainSound {
    private let sr: Float, srD: Double
    private var n = Noise(11)
    private var nR = Noise(12)
    private var distL = Biquad(), distR = Biquad()
    private var hissL = Biquad(), hissR = Biquad(), hissLoL = Biquad(), hissLoR = Biquad()
    private var patL = Biquad(), patR = Biquad(), patHiL = Biquad(), patHiR = Biquad()
    private var pings = [Ping](repeating: Ping(), count: 10)
    private var nextPing = 0
    private var drip = Ping()
    private var dripIn: Int
    private var intensity = Drift(0.75, 1.05, speed: 0.000_02)

    init(sampleRate: Double) {
        srD = sampleRate; sr = Float(sampleRate)
        distL.lowpass(900, sr: sampleRate); distR.lowpass(900, sr: sampleRate)
        hissL.highpass(1200, sr: sampleRate); hissR.highpass(1200, sr: sampleRate)
        hissLoL.lowpass(9000, sr: sampleRate); hissLoR.lowpass(9000, sr: sampleRate)
        patL.bandpass(3800, q: 0.9, sr: sampleRate); patR.bandpass(4200, q: 0.9, sr: sampleRate)
        patHiL.highpass(1500, sr: sampleRate); patHiR.highpass(1500, sr: sampleRate)
        dripIn = Int(sampleRate * 1.3)
    }

    func next() -> (Float, Float) {
        let k = intensity.next(&n)
        // far-off rain: a soft low rush
        let farL = distL.process(n.brown()) * 0.55, farR = distR.process(nR.brown()) * 0.55
        // the main shower: airy hiss
        let hisL = hissLoL.process(hissL.process(n.pink())) * 0.5
        let hisR = hissLoR.process(hissR.process(nR.pink())) * 0.5
        // thousands of tiny drops: sparse clicks through a bright filter, independently left and right
        let rate = 900 * k
        let clickL: Float = n.chance(rate, sr) ? n.range(-1, 1) * 3.2 : 0
        let clickR: Float = nR.chance(rate, sr) ? nR.range(-1, 1) * 3.2 : 0
        let patterL = patL.process(patHiL.process(clickL)) * 0.55
        let patterR = patR.process(patHiR.process(clickR)) * 0.55
        // a few bigger drops close by, landing on leaves and the sill
        if n.chance(7 * k, sr) {
            pings[nextPing].start(freq: n.range(1600, 4200), partials: (2.1, 3.4), decaySeconds: n.range(0.012, 0.035),
                                  amp: n.range(0.04, 0.12), pan: n.range(-0.9, 0.9), glide: 1.000_02, sr: sr)
            nextPing = (nextPing + 1) % pings.count
        }
        var pl: Float = 0, pr: Float = 0
        for i in 0..<pings.count where pings[i].active {
            let (a, b) = pings[i].next()
            pl += a; pr += b
        }
        // a slow drip from a gutter, roughly in rhythm
        dripIn -= 1
        if dripIn <= 0 {
            drip.start(freq: n.range(900, 1250), partials: (2.6, 4.1), decaySeconds: 0.05, amp: 0.10, pan: 0.55, glide: 0.999_97, sr: sr)
            dripIn = Int(srD * Double(n.range(1.1, 1.8)))
        }
        let (dl, dr) = drip.next()
        let l = (farL + hisL) * k + patterL + pl + dl
        let r = (farR + hisR) * k + patterR + pr + dr
        return (l, r)
    }
}

// MARK: - Fireplace

final class FireSound {
    private let sr: Float, srD: Double
    private var n = Noise(21)
    private var nR = Noise(22)
    private var roarL = Biquad(), roarR = Biquad()
    private var hissL = Biquad(), hissR = Biquad()
    private var flicker = Drift(0.55, 1.0, speed: 0.000_3)
    private var crackL = Biquad(), crackR = Biquad(), crackL2 = Biquad(), crackR2 = Biquad()
    private var burstClicks = 0, untilClick = 0
    private var popEnv: Float = 0, popDecay: Float = 0, popPan: (Float, Float) = (0.7, 0.7)
    private var popLP = Biquad()
    private var sap = Ping()

    init(sampleRate: Double) {
        srD = sampleRate; sr = Float(sampleRate)
        roarL.lowpass(220, q: 0.8, sr: sampleRate); roarR.lowpass(260, q: 0.8, sr: sampleRate)
        hissL.highpass(3000, sr: sampleRate); hissR.highpass(3000, sr: sampleRate)
        popLP.lowpass(700, q: 1.2, sr: sampleRate)
        popDecay = exp(-1 / (0.035 * sr))
    }

    func next() -> (Float, Float) {
        let f = flicker.next(&n)
        // the low roar of the flames
        let rl = roarL.process(n.brown()) * 0.75 * f
        let rr = roarR.process(nR.brown()) * 0.75 * f
        // a faint gassy hiss
        let hl = hissL.process(n.white()) * 0.012 * f
        let hr = hissR.process(nR.white()) * 0.012 * f
        // crackles: bursts of sharp ticks, each with its own pitch and place
        var cl: Float = 0, cr: Float = 0
        if burstClicks == 0 && n.chance(3.2, sr) {
            burstClicks = Int(n.range(2, 18))
            untilClick = 0
        }
        if burstClicks > 0 {
            untilClick -= 1
            if untilClick <= 0 {
                let fq = Double(n.range(1200, 6500))
                crackL.bandpass(fq, q: 2.5, sr: srD); crackR.bandpass(fq * 1.07, q: 2.5, sr: srD)
                crackL2.bandpass(fq * 0.5, q: 1.5, sr: srD); crackR2.bandpass(fq * 0.52, q: 1.5, sr: srD)
                let (gl, gr) = panGains(n.range(-0.8, 0.8))
                let a = n.range(2, 9)
                cl = a * gl; cr = a * gr
                burstClicks -= 1
                untilClick = Int(Double(n.range(0.004, 0.06)) * srD)
            }
        }
        let crackleL = crackL.process(cl) + crackL2.process(cl) * 0.6
        let crackleR = crackR.process(cr) + crackR2.process(cr) * 0.6
        // the odd bigger pop of a log
        if popEnv < 0.001 && n.chance(0.22, sr) {
            popEnv = 1
            popPan = panGains(n.range(-0.6, 0.6))
        }
        var pop: Float = 0
        if popEnv > 0.001 {
            pop = popLP.process(n.white()) * popEnv * 1.4
            popEnv *= popDecay
        }
        // and very occasionally, a whistle of sap
        if !sap.active && n.chance(0.03, sr) {
            sap.start(freq: n.range(2200, 3600), partials: (2.0, 3.0), decaySeconds: 0.5, amp: 0.012, pan: n.range(-0.5, 0.5), glide: 0.999_995, sr: sr)
        }
        let (sl, sr2) = sap.next()
        return (rl + hl + crackleL + pop * popPan.0 + sl, rr + hr + crackleR + pop * popPan.1 + sr2)
    }
}

// MARK: - Café

/// One person talking at a nearby table: syllables of vowel-like sounds with a natural rhythm and pitch.
/// Several together, softened by distance and the room, become the murmur of a café.
struct Talker {
    var f0: Float, baseF0: Float
    var phase: Float = 0
    var glottal: Float = 0
    var f1 = Biquad(), f2 = Biquad(), f3 = Biquad(), distance = Biquad()
    var g2: Float = 0.6, g3: Float = 0.25
    var talking = false
    var stateLeft = 0
    var syllableLen = 1, syllablePos = 0
    var level: Float, gl: Float, gr: Float
    var pitchDrift: Float = 0

    init(_ n: inout Noise, sr: Double) {
        let deep = n.unit() < 0.5
        baseF0 = deep ? n.range(95, 140) : n.range(175, 245)
        f0 = baseF0
        level = n.range(0.25, 1.0)
        (gl, gr) = panGains(n.range(-0.85, 0.85))
        distance.lowpass(Double(n.range(1300, 3200)), sr: sr)
        stateLeft = Int(Double(n.range(0.2, 4)) * sr)
    }

    mutating func next(_ n: inout Noise, sr: Double, srF: Float) -> (Float, Float) {
        stateLeft -= 1
        if stateLeft <= 0 {
            talking.toggle()
            stateLeft = Int(Double(talking ? n.range(1.5, 6) : n.range(0.6, 4)) * sr)
            pitchDrift = n.range(-0.12, 0.12)
        }
        guard talking else { return (0, 0) }
        if syllablePos >= syllableLen {
            // a new syllable: a vowel (two or three resonances), a length and a little intonation
            f1.bandpass(Double(n.range(300, 850)), q: 5, sr: sr)
            f2.bandpass(Double(n.range(850, 2300)), q: 7, sr: sr)
            f3.bandpass(Double(n.range(2400, 3200)), q: 8, sr: sr)
            g2 = n.range(0.35, 0.8)
            syllableLen = Int(Double(n.range(0.09, 0.26)) * sr)
            syllablePos = 0
            f0 = baseF0 * (1 + pitchDrift + n.range(-0.08, 0.08))
        }
        // syllable loudness: quick rise, short hold, gentle fall
        let u = Float(syllablePos) / Float(syllableLen)
        let env: Float = u < 0.2 ? u / 0.2 : (u < 0.55 ? 1 : max(0, 1 - (u - 0.55) / 0.45))
        syllablePos += 1
        // the voice: a soft pulse at the speaking pitch, plus breath
        phase += f0 / srF
        var pulse: Float = 0
        if phase >= 1 { phase -= 1; pulse = 1 }
        glottal += (pulse * 6 - glottal) * 0.18
        let source = glottal + n.white() * 0.04
        let voiced = f1.process(source) + f2.process(source) * g2 + f3.process(source) * g3
        let s = distance.process(voiced) * env * level * 0.16
        return (s * gl, s * gr)
    }
}

final class CafeSound {
    private let sr: Float, srD: Double
    private var n = Noise(31)
    private var talkers: [Talker] = []
    private var roomL = Biquad(), roomR = Biquad()
    private var hum = Biquad()
    private var clinks = [Ping](repeating: Ping(), count: 6)
    private var nextClink = 0
    private var steamEnv: Float = 0, steamTarget: Float = 0, steamLeft = 0
    private var steamBP = Biquad()

    init(sampleRate: Double) {
        srD = sampleRate; sr = Float(sampleRate)
        for _ in 0..<7 { talkers.append(Talker(&n, sr: sampleRate)) }
        roomL.lowpass(160, sr: sampleRate); roomR.lowpass(180, sr: sampleRate)
        hum.bandpass(118, q: 12, sr: sampleRate)
        steamBP.bandpass(4200, q: 0.8, sr: sampleRate)
        steamLeft = Int(30 * sampleRate)
    }

    func next() -> (Float, Float) {
        var l: Float = 0, r: Float = 0
        for i in 0..<talkers.count {
            let (a, b) = talkers[i].next(&n, sr: srD, srF: sr)
            l += a; r += b
        }
        // room tone and the fridge hum
        let room = roomL.process(n.brown()) * 0.18
        let room2 = roomR.process(n.brown()) * 0.18
        let h = hum.process(n.white()) * 0.012
        // cups on saucers and spoons on cups
        if n.chance(0.55, sr) {
            let cup = n.unit() < 0.6
            clinks[nextClink].start(freq: cup ? n.range(1700, 3000) : n.range(4200, 6800),
                                    partials: cup ? (2.32, 4.25) : (1.59, 2.71),
                                    decaySeconds: cup ? n.range(0.18, 0.45) : n.range(0.05, 0.12),
                                    amp: n.range(0.015, 0.05), pan: n.range(-0.9, 0.9), sr: sr)
            nextClink = (nextClink + 1) % clinks.count
        }
        for i in 0..<clinks.count where clinks[i].active {
            let (a, b) = clinks[i].next()
            l += a; r += b
        }
        // now and then, the espresso machine's steam wand
        if steamLeft <= 0 {
            if steamTarget > 0 { steamTarget = 0; steamLeft = Int(Double(n.range(40, 120)) * srD) }
            else { steamTarget = 1; steamLeft = Int(Double(n.range(3, 7)) * srD) }
            if steamTarget > 0 && n.unit() < 0.5 { steamTarget = 0 }
        }
        steamLeft -= 1
        steamEnv += (steamTarget - steamEnv) * 0.000_08
        let steam = steamBP.process(n.white()) * steamEnv * 0.035
        return (l + room + h + steam * 0.6, r + room2 + h + steam)
    }
}

// MARK: - Beach

/// One wave: it swells, breaks, then fizzes back down the sand.
struct Wave {
    var length = 1, pos = 0
    var body = Biquad(), fizz = Biquad(), fizzLP = Biquad()
    var gl: Float = 0.7, gr: Float = 0.7
    var size: Float = 1

    mutating func restart(_ n: inout Noise, sr: Double) {
        length = Int(Double(n.range(7, 12)) * sr)
        pos = 0
        size = n.range(0.6, 1.0)
        (gl, gr) = panGains(n.range(-0.5, 0.5))
    }

    mutating func next(_ n: inout Noise, sr: Double) -> (Float, Float) {
        if pos >= length { restart(&n, sr: sr) }
        let u = Float(pos) / Float(length)
        pos += 1
        // shape of a wave over its life
        let swell = u < 0.32 ? pow(u / 0.32, 2) * 0.45 : 0
        let crash: Float = u >= 0.32 && u < 0.5 ? (u < 0.36 ? 0.45 + (u - 0.32) / 0.04 * 0.55 : exp(-(u - 0.36) * 14)) : 0
        let wash: Float = u >= 0.36 ? exp(-(u - 0.36) * 3.2) * 0.75 : 0
        // brightness follows the wave: dull as it builds, bright as it breaks, softening as it retreats
        if pos % 64 == 0 {
            let cutoff = u < 0.32 ? 300 + Double(u / 0.32) * 700 : (u < 0.5 ? 2600 : 2600 - Double(u - 0.5) * 3600)
            body.lowpass(max(350, cutoff), q: 0.6, sr: sr)
            fizz.highpass(2500 + Double(wash) * 2500, sr: sr)
            fizzLP.lowpass(9000, sr: sr)
        }
        let rush = body.process(n.pink() * 2.2 + n.brown() * 0.5) * (swell + crash) * size
        // foam: lots of tiny bubbles popping as the water runs back
        let bubble: Float = n.chance(1800 * wash, Float(sr)) ? n.range(-1, 1) * 2 : 0
        let foam = fizzLP.process(fizz.process(n.white() * 0.25 + bubble)) * wash * size
        let s = rush + foam * 0.8
        return (s * gl, s * gr)
    }
}

final class BeachSound {
    private let sr: Float, srD: Double
    private var n = Noise(41)
    private var waves = [Wave(), Wave()]
    private var surfL = Biquad(), surfR = Biquad()
    private var windBP = Biquad()
    private var wind = Drift(0.2, 1.0, speed: 0.000_05)
    private var gull = Ping()
    private var gullCalls = 0, gullGap = 0, gullPan: Float = 0

    init(sampleRate: Double) {
        srD = sampleRate; sr = Float(sampleRate)
        waves[0].restart(&n, sr: sampleRate)
        waves[1].restart(&n, sr: sampleRate)
        waves[1].pos = waves[1].length / 2 // stagger the two
        surfL.lowpass(320, sr: sampleRate); surfR.lowpass(360, sr: sampleRate)
        windBP.bandpass(650, q: 0.6, sr: sampleRate)
    }

    func next() -> (Float, Float) {
        var l: Float = 0, r: Float = 0
        for i in 0..<waves.count {
            let (a, b) = waves[i].next(&n, sr: srD)
            l += a; r += b
        }
        // the constant distant surf and a light breeze
        let sl = surfL.process(n.brown()) * 0.3, sr2 = surfR.process(n.brown()) * 0.3
        let w = windBP.process(n.pink()) * 0.12 * wind.next(&n)
        // a gull, far off, every so often: two or three falling calls
        if gullCalls == 0 && n.chance(0.035, sr) {
            gullCalls = Int(n.range(2, 4.99))
            gullGap = 0
            gullPan = n.range(-0.8, 0.8)
        }
        if gullCalls > 0 {
            gullGap -= 1
            if gullGap <= 0 && !gull.active {
                gull.start(freq: n.range(1250, 1500), partials: (2.0, 2.97), decaySeconds: 0.12, amp: 0.025,
                           pan: gullPan, glide: 0.999_985, sr: sr)
                gullCalls -= 1
                gullGap = Int(Double(n.range(0.22, 0.34)) * srD)
            }
        }
        let (gl, gr) = gull.next()
        return (l + sl + w + gl, r + sr2 + w * 0.9 + gr)
    }
}

// MARK: - The mixer the player uses

/// Generates the chosen sound, one stereo sample at a time, gently limited so it never distorts.
final class SoundSynth {
    var sound: FocusSound = .off
    private let rain: RainSound, fire: FireSound, cafe: CafeSound, beach: BeachSound

    init(sampleRate: Double) {
        rain = RainSound(sampleRate: sampleRate)
        fire = FireSound(sampleRate: sampleRate)
        cafe = CafeSound(sampleRate: sampleRate)
        beach = BeachSound(sampleRate: sampleRate)
    }

    func nextStereo() -> (Float, Float) {
        let s: (Float, Float)
        switch sound {
        case .off: return (0, 0)
        case .rain: s = rain.next()
        case .fireplace: s = fire.next()
        case .cafe: s = cafe.next()
        case .beach: s = beach.next()
        }
        return (tanh(s.0), tanh(s.1))
    }

    /// Mono mix, for tests.
    func next() -> Float {
        let (l, r) = nextStereo()
        return (l + r) * 0.5
    }
}
