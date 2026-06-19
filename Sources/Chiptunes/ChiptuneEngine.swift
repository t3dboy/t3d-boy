// T3d Boy — T3d Tunes: the sound chip as a playable instrument.
//
// This detaches the Game Boy's APU from the emulator and drives it directly: a standalone
// `APU` instance, its own audio output, and a step sequencer that writes register "recipes"
// (patches) to the four channels in time. Patches are either built-in or harvested from the
// ROM you've selected in the library (see SoundHarvester). The whole thing is a looping
// soundboard — lay patches into a 16-step loop across the four channels and perform live.

import AVFoundation

/// The four Game Boy sound channels, used as the instrument's four lanes.
enum ChipVoice: Int, CaseIterable {
    case pulse1, pulse2, wave, noise
    var label: String {
        switch self {
        case .pulse1: return "Pulse 1"
        case .pulse2: return "Pulse 2"
        case .wave:   return "Wave"
        case .noise:  return "Noise"
        }
    }
    var short: String {
        switch self {
        case .pulse1: return "PUL1"
        case .pulse2: return "PUL2"
        case .wave:   return "WAVE"
        case .noise:  return "NOIS"
        }
    }
}

/// A "sound" — the register recipe that defines one Game Boy timbre. Pulse/Noise use the
/// envelope fields; Wave uses its 16-byte wavetable; Noise uses its polynomial register.
struct ChiptunePatch: Equatable {
    var voice: ChipVoice
    var name: String

    // Pulse + Noise envelope
    var duty: Int = 2          // pulse duty 0…3
    var envInit: Int = 13      // 0…15
    var envDir: Bool = false   // false = decay (the usual chiptune pluck)
    var envPeriod: Int = 3     // 0…7

    // Wave
    var waveRAM: [UInt8] = ChiptunePatch.triangleWave
    var waveVol: Int = 1       // 0 mute · 1 full · 2 half · 3 quarter

    // Noise tone (NR43): clock shift / width / divisor
    var noiseReg: UInt8 = 0x44

    static let triangleWave: [UInt8] = [
        0x01, 0x23, 0x45, 0x67, 0x89, 0xAB, 0xCD, 0xEF,
        0xFE, 0xDC, 0xBA, 0x98, 0x76, 0x54, 0x32, 0x10,
    ]

    /// A starter palette so the instrument is playable before harvesting a ROM.
    static let builtIns: [ChiptunePatch] = [
        ChiptunePatch(voice: .pulse1, name: "Lead",  duty: 2, envInit: 13, envPeriod: 0),
        ChiptunePatch(voice: .pulse1, name: "Pluck", duty: 1, envInit: 14, envPeriod: 3),
        ChiptunePatch(voice: .pulse2, name: "Bass",  duty: 2, envInit: 15, envPeriod: 2),
        ChiptunePatch(voice: .pulse2, name: "Blip",  duty: 0, envInit: 12, envPeriod: 4),
        ChiptunePatch(voice: .wave,   name: "Saw",   waveRAM: ChiptunePatch.triangleWave, waveVol: 1),
        ChiptunePatch(voice: .noise,  name: "Hat",   envInit: 10, envPeriod: 2, noiseReg: 0x33),
        ChiptunePatch(voice: .noise,  name: "Snare", envInit: 13, envPeriod: 4, noiseReg: 0x55),
    ]

    static func defaults(for voice: ChipVoice) -> ChiptunePatch {
        builtIns.first { $0.voice == voice } ?? ChiptunePatch(voice: voice, name: voice.label)
    }
}

// MARK: - Note ↔ Game Boy frequency

enum ChipNote {
    /// MIDI note → Hz (A4 = 69 = 440 Hz).
    static func hz(_ midi: Int) -> Double { 440 * pow(2, Double(midi - 69) / 12) }
    /// Hz → the Game Boy's 11-bit period value for pulse/wave channels.
    static func period(hz: Double) -> Int {
        guard hz > 1 else { return 0 }
        return max(0, min(2047, Int((2048 - 131072.0 / hz).rounded())))
    }
    static let names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
    static func name(_ midi: Int) -> String { "\(names[((midi % 12) + 12) % 12])\(midi / 12 - 1)" }
}

// MARK: - Engine

final class ChiptuneEngine {
    /// One lane = one Game Boy channel in the loop.
    struct Lane {
        var patch: ChiptunePatch
        var steps: [Bool]
        var rootNote: Int   // MIDI note the lane plays
        var volume: Double  // 0…1 (scales the patch envelope)
        var muted: Bool = false
    }

    private let apu = APU()
    private var audio: AVAudioEngine?
    private var timer: Timer?

    // Output FX — real audio units inserted into the signal chain (synth-style controls).
    private let eq = AVAudioUnitEQ(numberOfBands: 1)   // sweepable resonant low-pass
    private let dist = AVAudioUnitDistortion()          // drive / crush
    private let delayFX = AVAudioUnitDelay()            // tempo-synced echo
    private let reverbFX = AVAudioUnitReverb()          // space

    // Sequencer feel
    var swing: Double = 0       // 0…0.6 — delays the off-beat steps
    var glideEnabled = [Bool](repeating: false, count: 4) // per-lane portamento between consecutive notes
    private var lastNote = [Int?](repeating: nil, count: 4)
    private struct Glide { var from: Int; var to: Int; var t: Double; let dur: Double; let voice: ChipVoice }
    private var glides: [Int: Glide] = [:] // lane → active pitch slide

    // Sequencer
    let stepCount = 16
    private(set) var lanes: [Lane]
    var bpm = 120 { didSet { updateDelayTime() } }
    var stepsPerBeat = 4 // 16th notes
    private(set) var currentStep = -1
    private(set) var isPlaying = false
    /// Fired (on the main thread) when the playhead advances, with the new step index.
    var onStep: ((Int) -> Void)?

    private var stepAccum = 0.0
    private var laneFreed = [Bool](repeating: true, count: 4) // for retrigger spacing (unused v1)

    init() {
        lanes = ChipVoice.allCases.map { voice in
            Lane(patch: .defaults(for: voice),
                 steps: [Bool](repeating: false, count: 16),
                 rootNote: voice == .pulse2 ? 36 : (voice == .noise ? 48 : 60),
                 volume: 0.85)
        }
        // FX defaults = effect-off: filter fully open, everything else dry.
        eq.bands[0].filterType = .resonantLowPass
        eq.bands[0].frequency = 20000
        eq.bands[0].gain = 0
        eq.bands[0].bypass = false
        dist.loadFactoryPreset(.multiDecimated1)
        dist.preGain = -6
        dist.wetDryMix = 0
        delayFX.delayTime = 0.25
        delayFX.feedback = 0
        delayFX.wetDryMix = 0
        delayFX.lowPassCutoff = 14000
        reverbFX.loadFactoryPreset(.mediumHall)
        reverbFX.wetDryMix = 0
    }

    // MARK: - FX controls (0…1 knob values)

    /// Low-pass cutoff: 0 = muffled, 1 = fully open. Log-mapped 200 Hz … 20 kHz.
    func setCutoff(_ v: Double) {
        let t = max(0, min(1, v))
        eq.bands[0].frequency = Float(200.0 * pow(20000.0 / 200.0, t))
    }
    /// Filter resonance peak at the cutoff (0…18 dB).
    func setResonance(_ v: Double) { eq.bands[0].gain = Float(max(0, min(1, v)) * 18) }
    /// Drive / bit-crush amount.
    func setDrive(_ v: Double) {
        let m = max(0, min(1, v))
        dist.wetDryMix = Float(m * 70)
        dist.preGain = Float(-6 + m * 12)
    }
    /// Echo: ties mix and feedback to one knob.
    func setDelayMix(_ v: Double) {
        let m = max(0, min(1, v))
        delayFX.wetDryMix = Float(m * 50)
        delayFX.feedback = Float(m * 55)
    }
    /// Reverb mix (space).
    func setReverbMix(_ v: Double) { reverbFX.wetDryMix = Float(max(0, min(1, v)) * 60) }

    private func updateDelayTime() { delayFX.delayTime = 60.0 / Double(max(40, bpm)) / 2.0 } // 8th note

    /// Randomise the loop (the Dice button). Noise lane a touch denser.
    func randomize() {
        for i in lanes.indices {
            let density = (ChipVoice(rawValue: i) == .noise) ? 0.4 : 0.3
            for s in lanes[i].steps.indices { lanes[i].steps[s] = Double.random(in: 0 ..< 1) < density }
        }
    }

    // MARK: Lane editing (all on the main thread, same as the audio-feeding timer)

    func toggleStep(lane: Int, step: Int) {
        guard lanes.indices.contains(lane), lanes[lane].steps.indices.contains(step) else { return }
        lanes[lane].steps[step].toggle()
    }
    func isStepOn(lane: Int, step: Int) -> Bool {
        lanes.indices.contains(lane) && lanes[lane].steps.indices.contains(step) && lanes[lane].steps[step]
    }
    func setPatch(_ patch: ChiptunePatch, lane: Int) { if lanes.indices.contains(lane) { lanes[lane].patch = patch } }
    func patch(lane: Int) -> ChiptunePatch { lanes[lane].patch }
    func setRoot(_ note: Int, lane: Int) { if lanes.indices.contains(lane) { lanes[lane].rootNote = max(24, min(96, note)) } }
    func root(lane: Int) -> Int { lanes[lane].rootNote }
    func setVolume(_ v: Double, lane: Int) { if lanes.indices.contains(lane) { lanes[lane].volume = max(0, min(1, v)) } }
    func volume(lane: Int) -> Double { lanes[lane].volume }
    func setMuted(_ m: Bool, lane: Int) { if lanes.indices.contains(lane) { lanes[lane].muted = m } }
    func isMuted(lane: Int) -> Bool { lanes[lane].muted }
    func clear() { for i in lanes.indices { for s in lanes[i].steps.indices { lanes[i].steps[s] = false } } }

    /// Audition a patch live (a soundboard hit).
    func audition(_ patch: ChiptunePatch, note: Int) { trigger(patch, note: note, volume: 0.9) }

    /// Bypass (or re-enable) the whole FX chain. The keyboard uses this to play dry;
    /// the sequencer always re-enables it on `play()`.
    private func setFXBypass(_ bypassed: Bool) {
        eq.bypass = bypassed
        dist.bypass = bypassed
        delayFX.bypass = bypassed
        reverbFX.bypass = bypassed
    }

    /// Play one keyboard note. When `throughFX` is false (and the loop isn't running) the
    /// note is heard dry; otherwise it's coloured by the current Cutoff/Res/Drive/Delay/Reverb
    /// knob settings.
    func playKey(_ patch: ChiptunePatch, note: Int, throughFX: Bool) {
        startAudioIfNeeded()
        if !isPlaying { setFXBypass(!throughFX) }
        trigger(patch, note: note, volume: 0.9)
    }

    /// Immediately silence everything: power-cycle the chip (clears all channel state) and
    /// flush the delay/reverb tails so nothing keeps ringing after Clear/Stop.
    func panic() {
        apu.write(0xFF26, 0x00)
        powerOn()
        glides.removeAll()
        delayFX.reset()
        reverbFX.reset()
    }

    // MARK: Transport

    func togglePlay() { isPlaying ? stop() : play() }

    func play() {
        startAudioIfNeeded()
        setFXBypass(false)   // the loop always honours the FX knobs
        isPlaying = true
        currentStep = -1
        stepAccum = 0
    }

    func stop() {
        isPlaying = false
        currentStep = -1
        onStep?(-1)
    }

    /// Begin generating audio (the chip free-runs even when stopped, so audition works).
    func startAudioIfNeeded() {
        guard audio == nil else { return }
        powerOn()
        // Prime the ring with a little lead to absorb timer jitter.
        topUp(target: Int(APU.sampleRate * 0.10) * 2)

        if let fmt = AVAudioFormat(standardFormatWithSampleRate: APU.sampleRate, channels: 2) {
            let ring = apu.ring
            let engine = AVAudioEngine()
            let src = AVAudioSourceNode(format: fmt) { _, _, frames, abl -> OSStatus in
                let bufs = UnsafeMutableAudioBufferListPointer(abl)
                guard bufs.count >= 2,
                      let l = bufs[0].mData?.assumingMemoryBound(to: Float.self),
                      let r = bufs[1].mData?.assumingMemoryBound(to: Float.self) else { return noErr }
                ring.readDeinterleaved(left: l, right: r, frames: Int(frames))
                return noErr
            }
            // src → filter → drive → delay → reverb → mixer
            for u in [src, eq, dist, delayFX, reverbFX] as [AVAudioNode] { engine.attach(u) }
            engine.connect(src, to: eq, format: fmt)
            engine.connect(eq, to: dist, format: fmt)
            engine.connect(dist, to: delayFX, format: fmt)
            engine.connect(delayFX, to: reverbFX, format: fmt)
            engine.connect(reverbFX, to: engine.mainMixerNode, format: fmt)
            updateDelayTime()
            try? engine.start()
            audio = engine
        }
        // Drive the chip + sequencer on the main run loop, topping the ring to ~80 ms.
        let t = Timer(timeInterval: 1.0 / 120.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    /// Stop audio entirely (e.g. when the drawer closes).
    func shutdown() {
        timer?.invalidate(); timer = nil
        audio?.stop(); audio = nil
        isPlaying = false
        currentStep = -1
    }

    // MARK: Driving the chip

    private func tick() {
        topUp(target: Int(APU.sampleRate * 0.08) * 2)
    }

    /// Step the chip (and advance the sequencer) until the ring holds `target` samples,
    /// so audio never underruns regardless of timer jitter. Tempo stays accurate because
    /// the sequencer advances by the real time each stepped chunk represents.
    private func topUp(target: Int) {
        let chunkCycles = 4096
        let chunkSeconds = Double(chunkCycles) / 4_194_304.0
        var guardCount = 0
        while apu.ring.fill < target && guardCount < 64 {
            if isPlaying { advanceSequencer(by: chunkSeconds) }
            if !glides.isEmpty { advanceGlides(by: chunkSeconds) }
            apu.step(chunkCycles)
            apu.flush()
            guardCount += 1
        }
    }

    private func advanceSequencer(by seconds: Double) {
        let base = 60.0 / Double(bpm) / Double(stepsPerBeat)
        let sw = max(0, min(0.6, swing))
        stepAccum += seconds
        while true {
            let next = (currentStep + 1) % stepCount
            // Swing: the off-beat (odd) steps land late, the on-beats early; a pair still
            // sums to 2× the base step, so tempo holds.
            let threshold = base * (next % 2 == 1 ? (1 + sw) : (1 - sw))
            if stepAccum < threshold { break }
            stepAccum -= threshold
            currentStep = next
            fireStep(currentStep)
            onStep?(currentStep)
        }
    }

    /// Advance any active pitch slides (Glide), writing the channel frequency without
    /// retriggering so the note bends from the previous pitch to the new one.
    private func advanceGlides(by dt: Double) {
        for (lane, g0) in glides {
            var g = g0
            g.t += dt
            let f = min(1, g.t / g.dur)
            let cur = Int((Double(g.from) + (Double(g.to) - Double(g.from)) * f).rounded())
            writeFreq(g.voice, cur, trigger: false)
            if f >= 1 { glides[lane] = nil } else { glides[lane] = g }
        }
    }

    private func fireStep(_ i: Int) {
        for (lane, l) in lanes.enumerated() where !l.muted && l.steps[i] {
            trigger(l.patch, note: l.rootNote, volume: l.volume, lane: lane)
        }
    }

    // MARK: Register recipes

    private func powerOn() {
        apu.write(0xFF26, 0x80) // APU power on
        apu.write(0xFF24, 0x77) // master volume L/R = max
        apu.write(0xFF25, 0xFF) // route all channels to both sides
    }

    /// Notes are gated to a fixed length so the detached chip doesn't drone — without a
    /// game's music driver to stop them, channels with no envelope decay (and the wave
    /// channel, which has none) would ring forever. We use the GB length counter (clocked
    /// at 256 Hz): enabling it makes each note a ~`gateMs` one-shot.
    var gateMs: Double = 200
    private var gateTicks: Int { max(1, min(63, Int(gateMs / 1000 * 256))) }
    private var pulseLen: UInt8 { UInt8(64 - gateTicks) }                 // NR11/NR21/NR41 length field
    private var waveLen: UInt8 { UInt8(256 - max(1, min(255, Int(gateMs / 1000 * 256)))) } // NR31

    /// Write a pitched channel's frequency; `trigger` also (re)starts the note.
    private func writeFreq(_ voice: ChipVoice, _ p: Int, trigger: Bool) {
        let lo = UInt8(p & 0xFF)
        let hi = UInt8((trigger ? 0x80 : 0) | 0x40 | ((p >> 8) & 7)) // [trigger] + length-enable
        switch voice {
        case .pulse1: apu.write(0xFF13, lo); apu.write(0xFF14, hi)
        case .pulse2: apu.write(0xFF18, lo); apu.write(0xFF19, hi)
        case .wave:   apu.write(0xFF1D, lo); apu.write(0xFF1E, hi)
        case .noise:  break
        }
    }

    private func trigger(_ patch: ChiptunePatch, note: Int, volume: Double, lane: Int? = nil) {
        let env = max(0, min(15, Int((Double(patch.envInit) * volume).rounded())))
        let target = ChipNote.period(hz: ChipNote.hz(note))

        // Glide: if enabled and this lane had a previous pitched note, start at the old
        // pitch and slide to the new one.
        var startP = target, glideTo: Int? = nil
        if let lane, glideEnabled[lane], patch.voice != .noise, let prev = lastNote[lane], prev != note {
            startP = ChipNote.period(hz: ChipNote.hz(prev))
            glideTo = target
        }

        switch patch.voice {
        case .pulse1:
            apu.write(0xFF11, UInt8((patch.duty & 3) << 6) | pulseLen)
            apu.write(0xFF12, UInt8(env << 4 | (patch.envDir ? 8 : 0) | patch.envPeriod))
            writeFreq(.pulse1, startP, trigger: true)
        case .pulse2:
            apu.write(0xFF16, UInt8((patch.duty & 3) << 6) | pulseLen)
            apu.write(0xFF17, UInt8(env << 4 | (patch.envDir ? 8 : 0) | patch.envPeriod))
            writeFreq(.pulse2, startP, trigger: true)
        case .wave:
            apu.write(0xFF1A, 0x80) // DAC on
            for i in 0 ..< 16 { apu.write(UInt16(0xFF30 + i), patch.waveRAM[i]) }
            let code = volume > 0.66 ? 1 : (volume > 0.33 ? 2 : (volume > 0.05 ? 3 : 0))
            apu.write(0xFF1C, UInt8((patch.waveVol == 0 ? 0 : code) << 5))
            apu.write(0xFF1B, waveLen)
            writeFreq(.wave, startP, trigger: true)
        case .noise:
            apu.write(0xFF20, pulseLen) // NR41 length
            apu.write(0xFF21, UInt8(env << 4 | (patch.envDir ? 8 : 0) | patch.envPeriod))
            // Transpose the noise "pitch" by nudging the clock-shift nibble of NR43.
            let baseShift = Int(patch.noiseReg >> 4)
            let shift = max(0, min(13, baseShift + (note - 48) / 4))
            apu.write(0xFF22, UInt8(shift << 4) | (patch.noiseReg & 0x0F))
            apu.write(0xFF23, UInt8(0x80 | 0x40))
        }

        if let lane {
            if patch.voice != .noise { lastNote[lane] = note }
            glides[lane] = glideTo.map { Glide(from: startP, to: $0, t: 0, dur: 0.08, voice: patch.voice) }
        }
    }
}
