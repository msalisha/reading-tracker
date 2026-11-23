import Foundation
import AVFoundation
import Observation

/// Background sounds while you read. Generated live on the phone (no recordings), so they never loop,
/// cost nothing in app size, and have no licensing to worry about.
enum FocusSound: String, CaseIterable, Identifiable {
    case off, rain, cafe, fireplace, beach

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off: return "Off"
        case .rain: return "Rain"
        case .cafe: return "Café"
        case .fireplace: return "Fire"
        case .beach: return "Beach"
        }
    }

    var icon: String {
        switch self {
        case .off: return "speaker.slash"
        case .rain: return "cloud.rain"
        case .cafe: return "cup.and.saucer"
        case .fireplace: return "flame"
        case .beach: return "beach.umbrella"
        }
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
    @ObservationIgnored private var reverb: AVAudioUnitReverb?
    @ObservationIgnored private var recordingMixer: AVAudioMixerNode?
    @ObservationIgnored private let level = AudioLevel()
    @ObservationIgnored private var timerRunning = false
    @ObservationIgnored private var previewUntil: Date?

    private init() {
        sound = FocusSound(rawValue: UserDefaults.standard.string(forKey: "focusSound") ?? "") ?? .off
        volume = (UserDefaults.standard.object(forKey: "focusVolume") as? Double) ?? 0.6
    }

    func setSound(_ s: FocusSound) {
        let wasPlaying = isPlaying
        sound = s
        UserDefaults.standard.set(s.rawValue, forKey: "focusSound")
        if wasPlaying && (recordingMixer != nil || recording(for: s) != nil) {
            // switch between a recording and a generated sound: restart the engine
            engine?.stop(); engine = nil; synth = nil; recordingMixer = nil; isPlaying = false
        } else {
            synth?.sound = s
            if let reverb { applyRoom(reverb, for: s) }
        }
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

    /// A real recording bundled with the app (e.g. Sounds/rain.m4a), if one has been added.
    private func recording(for s: FocusSound) -> URL? {
        for ext in ["m4a", "caf", "mp3", "wav"] {
            if let url = Bundle.main.url(forResource: s.rawValue, withExtension: ext) { return url }
        }
        return nil
    }

    private func applyRoom(_ reverb: AVAudioUnitReverb, for s: FocusSound) {
        switch s {
        case .cafe: reverb.loadFactoryPreset(.mediumRoom); reverb.wetDryMix = 28
        case .fireplace: reverb.loadFactoryPreset(.smallRoom); reverb.wetDryMix = 14
        case .rain: reverb.loadFactoryPreset(.largeRoom); reverb.wetDryMix = 10
        case .beach: reverb.loadFactoryPreset(.largeHall); reverb.wetDryMix = 6
        case .off: reverb.wetDryMix = 0
        }
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
        guard let stereo = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 2) else { return }
        let reverb = AVAudioUnitReverb()
        applyRoom(reverb, for: sound)
        engine.attach(reverb)
        let level = self.level
        level.gain = 0

        if let url = recording(for: sound), let file = try? AVAudioFile(forReading: url),
           let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)),
           (try? file.read(into: buffer)) != nil {
            // a real recording, looped
            let player = AVAudioPlayerNode()
            let mixer = AVAudioMixerNode()
            engine.attach(player)
            engine.attach(mixer)
            engine.connect(player, to: mixer, format: buffer.format)
            engine.connect(mixer, to: reverb, format: nil)
            engine.connect(reverb, to: engine.mainMixerNode, format: nil)
            reverb.wetDryMix = 0
            mixer.outputVolume = 0
            player.scheduleBuffer(buffer, at: nil, options: .loops)
            recordingMixer = mixer
            do {
                try engine.start()
                player.play()
                self.engine = engine
                self.synth = nil
                isPlaying = true
                fadeRecording()
            } catch { isPlaying = false }
            return
        }

        let synth = SoundSynth(sampleRate: rate)
        synth.sound = sound
        let node = AVAudioSourceNode(format: stereo) { _, _, frameCount, buffers -> OSStatus in
            let list = UnsafeMutableAudioBufferListPointer(buffers)
            guard list.count >= 2,
                  let left = list[0].mData?.assumingMemoryBound(to: Float.self),
                  let right = list[1].mData?.assumingMemoryBound(to: Float.self) else { return noErr }
            for i in 0..<Int(frameCount) {
                // glide the volume so starts, stops and changes never click
                level.gain += (level.target - level.gain) * 0.0005
                let (l, r) = synth.nextStereo()
                left[i] = l * level.gain * 0.8
                right[i] = r * level.gain * 0.8
            }
            return noErr
        }
        engine.attach(node)
        engine.connect(node, to: reverb, format: stereo)
        engine.connect(reverb, to: engine.mainMixerNode, format: stereo)
        do {
            try engine.start()
            self.engine = engine
            self.synth = synth
            self.reverb = reverb
            recordingMixer = nil
            isPlaying = true
        } catch {
            isPlaying = false
        }
    }

    /// Recordings fade with a timer on the main thread (they don't go through the sample-by-sample path).
    private func fadeRecording() {
        guard let mixer = recordingMixer else { return }
        Task { @MainActor in
            while self.recordingMixer === mixer {
                let target = self.level.target
                let v = mixer.outputVolume + (target - mixer.outputVolume) * 0.25
                mixer.outputVolume = abs(v - target) < 0.01 ? target : v
                if !self.isPlaying && mixer.outputVolume < 0.01 { break }
                try? await Task.sleep(for: .milliseconds(40))
            }
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
            self.reverb = nil
            self.recordingMixer = nil
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }
}
