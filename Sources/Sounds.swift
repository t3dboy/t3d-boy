// T3d Boy — small synthesized UI sounds (no audio assets shipped).
//
// powerSwitch: a short mechanical "clack" like a DMG power slide-switch — two
// quick transients (the slide passing a detent), each a sharp noise tick plus a
// little low thunk. Built once into a WAV in memory and played via NSSound.

import Cocoa

enum Sounds {
    private static let powerSwitch: NSSound? = NSSound(data: makeClickWAV())

    static func playPowerSwitch() {
        powerSwitch?.stop()
        powerSwitch?.play()
    }

    private static func makeClickWAV() -> Data {
        let sr = 44100.0
        let n = Int(sr * 0.11)
        var samples = [Int16](repeating: 0, count: n)
        let ticks: [(t: Double, amp: Double)] = [(0.0, 1.0), (0.028, 0.7)]
        var seed: UInt32 = 0x1234_5678
        func noise() -> Double {
            seed = seed &* 1_664_525 &+ 1_013_904_223
            return Double(Int32(bitPattern: seed)) / Double(Int32.max)
        }
        for i in 0 ..< n {
            let t = Double(i) / sr
            var s = 0.0
            for tk in ticks where t >= tk.t {
                let dt = t - tk.t
                s += noise() * exp(-dt * 520) * 0.6 * tk.amp           // sharp tick
                s += sin(2 * .pi * 95 * dt) * exp(-dt * 90) * 0.35 * tk.amp // low thunk
            }
            samples[i] = Int16(max(-1, min(1, s)) * 32_000)
        }
        return wav(samples: samples, sampleRate: Int(sr))
    }

    private static func wav(samples: [Int16], sampleRate: Int) -> Data {
        var d = Data()
        let dataBytes = samples.count * 2
        func u32(_ v: UInt32) { var x = v.littleEndian; d.append(Data(bytes: &x, count: 4)) }
        func u16(_ v: UInt16) { var x = v.littleEndian; d.append(Data(bytes: &x, count: 2)) }
        d.append("RIFF".data(using: .ascii)!); u32(UInt32(36 + dataBytes))
        d.append("WAVE".data(using: .ascii)!)
        d.append("fmt ".data(using: .ascii)!); u32(16); u16(1); u16(1)        // PCM, mono
        u32(UInt32(sampleRate)); u32(UInt32(sampleRate * 2)); u16(2); u16(16) // 16-bit
        d.append("data".data(using: .ascii)!); u32(UInt32(dataBytes))
        samples.withUnsafeBytes { d.append(contentsOf: $0) }
        return d
    }
}
