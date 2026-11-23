import Foundation
import AVFoundation
import Observation

/// Background sounds while you read. Generated live on the phone (no recordings), so they never loop,
/// cost nothing in app size, and have no licensing to worry about.
enum FocusSound: String, CaseIterable, Identifiable {
    case off, rain, cafe, fireplace

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off: return "Off"
        case .rain: return "Rain"
        case .cafe: return "Café"
        case .fireplace: return "Fire"
        }
    }

    var icon: String {
        switch self {
        case .off: return "speaker.slash"
        case .rain: return "cloud.rain"
        case .cafe: return "cup.and.saucer"
        case .fireplace: return "flame"
        }
    }
}

/// The sound generator. Pure maths, so it can be tested without audio hardware.
/// One sample at a time: soft noise beds plus random events (raindrops, crackles, cup clinks).
final class SoundSynth {
    var sound: FocusSound = .off
    private let sampleRate: Double

    // random numbers (xorshift)
    private var seed: UInt32 = 0x1234_5678

    // noise colours
    private var brown: Float = 0
    private var p0: Float = 0, p1: Float = 0, p2: Float = 0, p3: Float = 0, p4: Float = 0, p5: Float = 0, p6: Float = 0

    // filters (one-pole states)
    private var lp1: Float = 0, lp2: Float = 0, lp3: Float = 0, hp1: Float = 0

    // slow movement
    private var t: Double = 0

    // events
    private var dropEnv: Float = 0, dropAmp: Float = 0, dropLP: Float = 0
    private var crackleEnv: Float = 0, crackleAmp: Float = 0, crackleClicks = 0
    private var popEnv: Float = 0
    private var clinkEnv: Float = 0, clinkPhase: Double = 0, clinkFreq: Double = 3000
    private var murmur: [Float] = [0, 0, 0]
    private var murmurTarget: [Float] = [0.5, 0.5, 0.5]

    init(sampleRate: Double) { self.sampleRate = sampleRate }

    private func white() -> Float {
        seed ^= seed << 13
        seed ^= seed >> 17
        seed ^= seed << 5
        return Float(seed) / Float(UInt32.max) * 2 - 1
    }

    private func chance(perSecond: Double) -> Bool {
        Double(white() * 0.5 + 0.5) < perSecond / sampleRate
    }

    private func coef(_ hz: Double) -> Float { Float(1 - exp(-2 * Double.pi * hz / sampleRate)) }

    private func pink() -> Float {
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

    private func brownNoise() -> Float {
        brown = (brown + 0.02 * white()) / 1.02
        return brown * 3.5
    }

    func next() -> Float {
        t += 1 / sampleRate
        let s: Float
        switch sound {
        case .off: s = 0
        case .rain: s = rain()
        case .cafe: s = cafe()
        case .fireplace: s = fireplace()
        }
        return max(-1, min(1, s))
    }

    /// Steady hiss of falling rain, slow gusts, and close-by drops.
    private func rain() -> Float {
        let n = pink()
        lp1 += coef(6000) * (n - lp1)
        hp1 += coef(250) * (lp1 - hp1)
        let bed = (lp1 - hp1) * 0.9
        let gust = Float(0.8 + 0.2 * sin(t * 0.21) * sin(t * 0.07 + 1))
        if chance(perSecond: 28) {
            dropEnv = 1
            dropAmp = 0.15 + (white() * 0.5 + 0.5) * 0.35
        }
        var drop: Float = 0
        if dropEnv > 0.001 {
            dropLP += coef(3500) * (white() - dropLP)
            drop = (white() - dropLP) * dropEnv * dropAmp
            dropEnv *= 0.9965
        }
        return bed * gust + drop
    }

    /// A low roar with flicker, crackling wood and the odd pop.
    private func fireplace() -> Float {
        let roarNoise = brownNoise()
        lp1 += coef(500) * (roarNoise - lp1)
        let flicker = Float(0.7 + 0.3 * sin(t * 1.3) * sin(t * 0.37 + 2))
        let roar = lp1 * 0.55 * flicker
        if crackleClicks == 0 && chance(perSecond: 5) {
            crackleClicks = 3 + Int((white() * 0.5 + 0.5) * 12)
        }
        if crackleClicks > 0 && crackleEnv < 0.05 && chance(perSecond: 90) {
            crackleEnv = 1
            crackleAmp = 0.2 + (white() * 0.5 + 0.5) * 0.5
            crackleClicks -= 1
        }
        var crackle: Float = 0
        if crackleEnv > 0.001 {
            let w = white()
            hp1 += coef(1500) * (w - hp1)
            crackle = (w - hp1) * crackleEnv * crackleAmp
            crackleEnv *= 0.985
        }
        if chance(perSecond: 0.35) { popEnv = 1 }
        var pop: Float = 0
        if popEnv > 0.001 {
            lp2 += coef(900) * (white() - lp2)
            pop = lp2 * popEnv * 1.6
            popEnv *= 0.9992
        }
        return roar + crackle + pop
    }

    /// Murmuring voices, room tone and the occasional cup or spoon.
    private func cafe() -> Float {
        let n = pink()
        lp1 += coef(1800) * (n - lp1)
        hp1 += coef(300) * (lp1 - hp1)
        let voices = lp1 - hp1
        // three "speakers" whose loudness drifts at speech-like rates
        if chance(perSecond: 9) {
            let i = Int((white() * 0.5 + 0.5) * 2.99)
            murmurTarget[i] = 0.2 + (white() * 0.5 + 0.5) * 0.8
        }
        var level: Float = 0
        for i in 0..<3 {
            murmur[i] += 0.0006 * (murmurTarget[i] - murmur[i])
            level += murmur[i]
        }
        let speech = voices * (0.35 + level * 0.35) * Float(0.85 + 0.15 * sin(t * 4.1) * sin(t * 2.3 + 1))
        lp2 += coef(180) * (brownNoise() - lp2)
        let room = lp2 * 0.25
        if clinkEnv < 0.001 && chance(perSecond: 0.25) {
            clinkEnv = 1
            clinkFreq = 2400 + Double(white() * 0.5 + 0.5) * 2200
        }
        var clink: Float = 0
        if clinkEnv > 0.001 {
            clinkPhase += 2 * Double.pi * clinkFreq / sampleRate
            clink = Float(sin(clinkPhase) + 0.4 * sin(clinkPhase * 2.76)) * clinkEnv * 0.07
            clinkEnv *= 0.99975
        }
        return speech + room + clink
    }
}

/// Volume shared with the audio thread (kept outside the main-thread player on purpose).
final class AudioLevel {
    var gain: Float = 0
    var target: Float = 0
}

/// Plays the chosen sound while the reading timer runs. Keeps playing with the screen locked.
@MainActor
@Observable
final class FocusSoundPlayer {
    static let shared = FocusSoundPlayer()

    private(set) var sound: FocusSound
    private(set) var volume: Double
    private(set) var isPlaying = false

    @ObservationIgnored private var engine: AVAudioEngine?
    @ObservationIgnored private var synth: SoundSynth?
    @ObservationIgnored private let level = AudioLevel()
    @ObservationIgnored private var timerRunning = false
    @ObservationIgnored private var previewUntil: Date?

    private init() {
        sound = FocusSound(rawValue: UserDefaults.standard.string(forKey: "focusSound") ?? "") ?? .off
        volume = (UserDefaults.standard.object(forKey: "focusVolume") as? Double) ?? 0.6
    }

    func setSound(_ s: FocusSound) {
        sound = s
        UserDefaults.standard.set(s.rawValue, forKey: "focusSound")
        synth?.sound = s
        if timerRunning { refresh() } else { preview() }
    }

    func setVolume(_ v: Double) {
        volume = v
        UserDefaults.standard.set(v, forKey: "focusVolume")
        if isPlaying { level.target = Float(v) }
    }

    /// Called whenever the timer changes.
    func timerChanged(running: Bool) {
        timerRunning = running
        if running { previewUntil = nil }
        refresh()
    }

    /// Plays a few seconds so you can hear a sound before starting the timer.
    func preview() {
        guard sound != .off else { refresh(); return }
        let until = Date().addingTimeInterval(5)
        previewUntil = until
        refresh()
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(5.2))
            if self.previewUntil == until { self.previewUntil = nil; self.refresh() }
        }
    }

    private func refresh() {
        let previewing = previewUntil.map { $0.timeIntervalSinceNow > 0 } ?? false
        if sound != .off && (timerRunning || previewing) { start() } else { stop() }
    }

    private func start() {
        level.target = Float(volume)
        if isPlaying { return }
        engine?.stop() // a previous one still fading out
        engine = nil
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try? session.setActive(true)

        let engine = AVAudioEngine()
        let hw = engine.outputNode.outputFormat(forBus: 0).sampleRate
        let rate = hw > 0 ? hw : 44_100
        let synth = SoundSynth(sampleRate: rate)
        synth.sound = sound
        let level = self.level
        level.gain = 0
        guard let mono = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1) else { return }
        let node = AVAudioSourceNode(format: mono) { _, _, frameCount, buffers -> OSStatus in
            let list = UnsafeMutableAudioBufferListPointer(buffers)
            guard let out = list.first?.mData?.assumingMemoryBound(to: Float.self) else { return noErr }
            for i in 0..<Int(frameCount) {
                // glide the volume so starts, stops and changes never click
                level.gain += (level.target - level.gain) * 0.0005
                out[i] = synth.next() * level.gain * 0.8
            }
            return noErr
        }
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: mono)
        do {
            try engine.start()
            self.engine = engine
            self.synth = synth
            isPlaying = true
        } catch {
            isPlaying = false
        }
    }

    private func stop() {
        guard isPlaying, let engine else { return }
        level.target = 0
        isPlaying = false
        // let it fade out, then switch off
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(450))
            guard !self.isPlaying, self.engine === engine else { return }
            engine.stop()
            self.engine = nil
            self.synth = nil
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }
}
