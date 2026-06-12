// T3d Boy — APU: 2 square channels, wave channel, noise channel.
// All channel state lives in Codable structs so save states capture sound.

import Foundation

struct SquareChannel: Codable {
    var enabled = false, dacOn = false
    var duty = 0, dutyPos = 0
    var freq = 0, timer = 0
    var lengthCounter = 0, lengthEnable = false
    var envInit = 0, envDir = false, envPeriod = 0
    var envVol = 0, envTimer = 0
    var hasSweep = false
    var sweepPeriod = 0, sweepNegate = false, sweepShift = 0
    var sweepTimer = 0, sweepShadow = 0, sweepEnabled = false

    static let dutyTable: [[Int]] = [
        [0, 0, 0, 0, 0, 0, 0, 1],
        [1, 0, 0, 0, 0, 0, 0, 1],
        [1, 0, 0, 0, 0, 1, 1, 1],
        [0, 1, 1, 1, 1, 1, 1, 0],
    ]

    mutating func step(_ cycles: Int) {
        guard enabled else { return }
        timer -= cycles
        while timer <= 0 {
            timer += (2048 - freq) * 4
            dutyPos = (dutyPos + 1) & 7
        }
    }

    var output: Int {
        guard enabled && dacOn else { return 0 }
        return SquareChannel.dutyTable[duty][dutyPos] == 1 ? envVol : 0
    }

    mutating func clockLength() {
        if lengthEnable && lengthCounter > 0 {
            lengthCounter -= 1
            if lengthCounter == 0 { enabled = false }
        }
    }

    mutating func clockEnvelope() {
        guard envPeriod > 0 else { return }
        envTimer -= 1
        if envTimer <= 0 {
            envTimer = envPeriod
            if envDir && envVol < 15 { envVol += 1 }
            else if !envDir && envVol > 0 { envVol -= 1 }
        }
    }

    private func sweepCalc() -> Int {
        let delta = sweepShadow >> sweepShift
        return sweepNegate ? sweepShadow - delta : sweepShadow + delta
    }

    mutating func clockSweep() {
        guard hasSweep else { return }
        sweepTimer -= 1
        if sweepTimer <= 0 {
            sweepTimer = sweepPeriod > 0 ? sweepPeriod : 8
            if sweepEnabled && sweepPeriod > 0 {
                let nf = sweepCalc()
                if nf > 2047 {
                    enabled = false
                } else if sweepShift > 0 {
                    sweepShadow = nf
                    freq = nf
                    if sweepCalc() > 2047 { enabled = false }
                }
            }
        }
    }

    mutating func trigger() {
        enabled = dacOn
        if lengthCounter == 0 { lengthCounter = 64 }
        timer = (2048 - freq) * 4
        envVol = envInit
        envTimer = envPeriod
        if hasSweep {
            sweepShadow = freq
            sweepTimer = sweepPeriod > 0 ? sweepPeriod : 8
            sweepEnabled = sweepPeriod > 0 || sweepShift > 0
            if sweepShift > 0 && sweepCalc() > 2047 { enabled = false }
        }
    }
}

struct WaveChannel: Codable {
    var enabled = false, dacOn = false
    var freq = 0, timer = 0, pos = 0
    var lengthCounter = 0, lengthEnable = false
    var volCode = 0
    var sample = 0

    mutating func step(_ cycles: Int, waveRAM: [UInt8]) {
        guard enabled else { return }
        timer -= cycles
        while timer <= 0 {
            timer += (2048 - freq) * 2
            pos = (pos + 1) & 31
            let byte = waveRAM[pos >> 1]
            sample = Int(pos & 1 == 0 ? byte >> 4 : byte & 0x0F)
        }
    }

    var output: Int {
        guard enabled && dacOn else { return 0 }
        switch volCode {
        case 0: return 0
        case 1: return sample
        case 2: return sample >> 1
        default: return sample >> 2
        }
    }

    mutating func clockLength() {
        if lengthEnable && lengthCounter > 0 {
            lengthCounter -= 1
            if lengthCounter == 0 { enabled = false }
        }
    }

    mutating func trigger() {
        enabled = dacOn
        if lengthCounter == 0 { lengthCounter = 256 }
        timer = (2048 - freq) * 2
        pos = 0
    }
}

struct NoiseChannel: Codable {
    var enabled = false, dacOn = false
    var shift = 0, width7 = false, divCode = 0
    var timer = 0
    var lfsr: UInt16 = 0x7FFF
    var lengthCounter = 0, lengthEnable = false
    var envInit = 0, envDir = false, envPeriod = 0
    var envVol = 0, envTimer = 0

    static let divisors = [8, 16, 32, 48, 64, 80, 96, 112]

    mutating func step(_ cycles: Int) {
        guard enabled else { return }
        timer -= cycles
        while timer <= 0 {
            timer += NoiseChannel.divisors[divCode] << shift
            let bit = (lfsr ^ (lfsr >> 1)) & 1
            lfsr = (lfsr >> 1) | (bit << 14)
            if width7 { lfsr = (lfsr & ~0x40) | (bit << 6) }
        }
    }

    var output: Int {
        guard enabled && dacOn else { return 0 }
        return lfsr & 1 == 0 ? envVol : 0
    }

    mutating func clockLength() {
        if lengthEnable && lengthCounter > 0 {
            lengthCounter -= 1
            if lengthCounter == 0 { enabled = false }
        }
    }

    mutating func clockEnvelope() {
        guard envPeriod > 0 else { return }
        envTimer -= 1
        if envTimer <= 0 {
            envTimer = envPeriod
            if envDir && envVol < 15 { envVol += 1 }
            else if !envDir && envVol > 0 { envVol -= 1 }
        }
    }

    mutating func trigger() {
        enabled = dacOn
        if lengthCounter == 0 { lengthCounter = 64 }
        timer = NoiseChannel.divisors[divCode] << shift
        lfsr = 0x7FFF
        envVol = envInit
        envTimer = envPeriod
    }
}

struct APUState: Codable {
    var ch1 = SquareChannel()
    var ch2 = SquareChannel()
    var wave = WaveChannel()
    var noise = NoiseChannel()
    var waveRAM = [UInt8](repeating: 0, count: 16)
    var regs = [UInt8](repeating: 0, count: 0x20) // raw NRxx writes for readback
    var nr50: UInt8 = 0x77, nr51: UInt8 = 0xF3
    var power = true
    var fsStep = 0, fsCounter = 0
    var sampleCounter = 0.0
}

// Thread-safe ring buffer between the emulation (main) thread and the
// audio render thread. Interleaved stereo floats.
final class AudioRingBuffer {
    private var buf: [Float]
    private var readIdx = 0, writeIdx = 0, used = 0
    private let lock = NSLock()
    private let capacity: Int

    init(capacity: Int = 16384) {
        self.capacity = capacity
        buf = [Float](repeating: 0, count: capacity)
    }

    func write(_ samples: [Float]) {
        lock.lock()
        defer { lock.unlock() }
        for s in samples {
            if used == capacity { break } // overrun: drop the newest audio
            buf[writeIdx] = s
            writeIdx = (writeIdx + 1) % capacity
            used += 1
        }
    }

    func readDeinterleaved(left: UnsafeMutablePointer<Float>,
                           right: UnsafeMutablePointer<Float>, frames: Int) {
        lock.lock()
        defer { lock.unlock() }
        for f in 0 ..< frames {
            if used >= 2 {
                left[f] = buf[readIdx]; readIdx = (readIdx + 1) % capacity
                right[f] = buf[readIdx]; readIdx = (readIdx + 1) % capacity
                used -= 2
            } else {
                left[f] = 0
                right[f] = 0
            }
        }
    }

    var fill: Int {
        lock.lock()
        defer { lock.unlock() }
        return used
    }
}

final class APU {
    static let sampleRate = 44100.0
    static let cyclesPerSample = 4194304.0 / APU.sampleRate

    var s = APUState()
    let ring = AudioRingBuffer()
    private var pending: [Float] = []
    private var capL: Float = 0, capR: Float = 0 // high-pass filter state

    // Debug counters for headless verification
    var totalSamples = 0
    var maxAmp: Float = 0

    init() {
        s.ch1.hasSweep = true
    }

    // Sampling must interleave with oscillator stepping or tones collapse
    // into a per-call buzz, so large cycle counts are processed in slices
    // smaller than one sample period (~95 cycles).
    func step(_ cycles: Int) {
        var remaining = cycles
        while remaining > 64 {
            stepChunk(64)
            remaining -= 64
        }
        if remaining > 0 { stepChunk(remaining) }
    }

    private func stepChunk(_ cycles: Int) {
        if s.power {
            s.ch1.step(cycles)
            s.ch2.step(cycles)
            s.wave.step(cycles, waveRAM: s.waveRAM)
            s.noise.step(cycles)

            s.fsCounter += cycles
            while s.fsCounter >= 8192 { // 512 Hz frame sequencer
                s.fsCounter -= 8192
                switch s.fsStep {
                case 0, 4:
                    clockLengths()
                case 2, 6:
                    clockLengths()
                    s.ch1.clockSweep()
                case 7:
                    s.ch1.clockEnvelope()
                    s.ch2.clockEnvelope()
                    s.noise.clockEnvelope()
                default: break
                }
                s.fsStep = (s.fsStep + 1) & 7
            }
        }
        s.sampleCounter += Double(cycles)
        while s.sampleCounter >= APU.cyclesPerSample {
            s.sampleCounter -= APU.cyclesPerSample
            emitSample()
        }
    }

    private func clockLengths() {
        s.ch1.clockLength()
        s.ch2.clockLength()
        s.wave.clockLength()
        s.noise.clockLength()
    }

    private func emitSample() {
        var l: Float = 0, r: Float = 0
        if s.power {
            let outs: [Float] = [
                s.ch1.dacOn ? Float(s.ch1.output) / 7.5 - 1 : 0,
                s.ch2.dacOn ? Float(s.ch2.output) / 7.5 - 1 : 0,
                s.wave.dacOn ? Float(s.wave.output) / 7.5 - 1 : 0,
                s.noise.dacOn ? Float(s.noise.output) / 7.5 - 1 : 0,
            ]
            for i in 0 ..< 4 {
                if s.nr51 & (1 << (i + 4)) != 0 { l += outs[i] }
                if s.nr51 & (1 << i) != 0 { r += outs[i] }
            }
            l *= Float((s.nr50 >> 4) & 7 + 1) / 8.0 / 4.0
            r *= Float(s.nr50 & 7 + 1) / 8.0 / 4.0
        }
        // High-pass to strip the DAC DC offset
        let outL = l - capL
        capL = l - outL * 0.996
        let outR = r - capR
        capR = r - outR * 0.996

        pending.append(outL * 0.6)
        pending.append(outR * 0.6)
        totalSamples += 1
        maxAmp = max(maxAmp, abs(outL))
    }

    // Push this frame's samples to the audio thread
    func flush() {
        if !pending.isEmpty {
            ring.write(pending)
            pending.removeAll(keepingCapacity: true)
        }
    }

    // MARK: - Register access (0xFF10-0xFF3F)

    private static let readMasks: [UInt8] = [
        0x80, 0x3F, 0x00, 0xFF, 0xBF, // NR10-NR14
        0xFF, 0x3F, 0x00, 0xFF, 0xBF, // ----, NR21-NR24
        0x7F, 0xFF, 0x9F, 0xFF, 0xBF, // NR30-NR34
        0xFF, 0xFF, 0x00, 0x00, 0xBF, // ----, NR41-NR44
        0x00, 0x00, 0x70,             // NR50, NR51, NR52
    ]

    func read(_ addr: UInt16) -> UInt8 {
        let idx = Int(addr - 0xFF10)
        switch addr {
        case 0xFF26:
            var v: UInt8 = s.power ? 0x80 : 0
            v |= 0x70
            if s.ch1.enabled { v |= 0x01 }
            if s.ch2.enabled { v |= 0x02 }
            if s.wave.enabled { v |= 0x04 }
            if s.noise.enabled { v |= 0x08 }
            return v
        case 0xFF30...0xFF3F:
            return s.waveRAM[Int(addr - 0xFF30)]
        case 0xFF10...0xFF25:
            return s.regs[idx] | APU.readMasks[idx]
        default:
            return 0xFF // FF27-FF2F unused
        }
    }

    func write(_ addr: UInt16, _ v: UInt8) {
        if addr == 0xFF26 {
            let wasOn = s.power
            s.power = v & 0x80 != 0
            if wasOn && !s.power {
                // Power off clears every register and channel
                let waveRAM = s.waveRAM
                let sampleCounter = s.sampleCounter
                s = APUState()
                s.ch1.hasSweep = true
                s.power = false
                s.nr50 = 0
                s.nr51 = 0
                s.waveRAM = waveRAM
                s.sampleCounter = sampleCounter
            }
            return
        }
        if case 0xFF30...0xFF3F = addr {
            s.waveRAM[Int(addr - 0xFF30)] = v
            return
        }
        guard s.power, addr >= 0xFF10, addr <= 0xFF25 else { return }
        s.regs[Int(addr - 0xFF10)] = v

        switch addr {
        case 0xFF10: // NR10 sweep
            s.ch1.sweepPeriod = Int((v >> 4) & 7)
            s.ch1.sweepNegate = v & 0x08 != 0
            s.ch1.sweepShift = Int(v & 7)
        case 0xFF11:
            s.ch1.duty = Int(v >> 6)
            s.ch1.lengthCounter = 64 - Int(v & 0x3F)
        case 0xFF12:
            s.ch1.envInit = Int(v >> 4)
            s.ch1.envDir = v & 0x08 != 0
            s.ch1.envPeriod = Int(v & 7)
            s.ch1.dacOn = v & 0xF8 != 0
            if !s.ch1.dacOn { s.ch1.enabled = false }
        case 0xFF13:
            s.ch1.freq = (s.ch1.freq & 0x700) | Int(v)
        case 0xFF14:
            s.ch1.freq = (s.ch1.freq & 0xFF) | (Int(v & 7) << 8)
            s.ch1.lengthEnable = v & 0x40 != 0
            if v & 0x80 != 0 { s.ch1.trigger() }

        case 0xFF16:
            s.ch2.duty = Int(v >> 6)
            s.ch2.lengthCounter = 64 - Int(v & 0x3F)
        case 0xFF17:
            s.ch2.envInit = Int(v >> 4)
            s.ch2.envDir = v & 0x08 != 0
            s.ch2.envPeriod = Int(v & 7)
            s.ch2.dacOn = v & 0xF8 != 0
            if !s.ch2.dacOn { s.ch2.enabled = false }
        case 0xFF18:
            s.ch2.freq = (s.ch2.freq & 0x700) | Int(v)
        case 0xFF19:
            s.ch2.freq = (s.ch2.freq & 0xFF) | (Int(v & 7) << 8)
            s.ch2.lengthEnable = v & 0x40 != 0
            if v & 0x80 != 0 { s.ch2.trigger() }

        case 0xFF1A:
            s.wave.dacOn = v & 0x80 != 0
            if !s.wave.dacOn { s.wave.enabled = false }
        case 0xFF1B:
            s.wave.lengthCounter = 256 - Int(v)
        case 0xFF1C:
            s.wave.volCode = Int((v >> 5) & 3)
        case 0xFF1D:
            s.wave.freq = (s.wave.freq & 0x700) | Int(v)
        case 0xFF1E:
            s.wave.freq = (s.wave.freq & 0xFF) | (Int(v & 7) << 8)
            s.wave.lengthEnable = v & 0x40 != 0
            if v & 0x80 != 0 { s.wave.trigger() }

        case 0xFF20:
            s.noise.lengthCounter = 64 - Int(v & 0x3F)
        case 0xFF21:
            s.noise.envInit = Int(v >> 4)
            s.noise.envDir = v & 0x08 != 0
            s.noise.envPeriod = Int(v & 7)
            s.noise.dacOn = v & 0xF8 != 0
            if !s.noise.dacOn { s.noise.enabled = false }
        case 0xFF22:
            s.noise.shift = Int(v >> 4)
            s.noise.width7 = v & 0x08 != 0
            s.noise.divCode = Int(v & 7)
        case 0xFF23:
            s.noise.lengthEnable = v & 0x40 != 0
            if v & 0x80 != 0 { s.noise.trigger() }

        case 0xFF24: s.nr50 = v
        case 0xFF25: s.nr51 = v
        default: break
        }
    }
}
