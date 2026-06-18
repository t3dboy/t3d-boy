// T3d Boy — harvests a ROM's instrument "patches" for T3d Tunes.
//
// Runs the selected ROM headlessly for a few seconds, tapping the APU's trigger hook to
// capture the distinct channel configurations the game actually uses — pulse duty/envelope,
// the wave channel's custom wavetables, noise tones. The result is a palette of that cart's
// own sounds to lay into the loop. Heavy-ish (boots + runs the core), so callers should run
// it off the main thread and deliver the patches back on the main queue.

import Foundation

enum SoundHarvester {
    /// Harvest up to `maxPerVoice` distinct patches per channel from `url`.
    static func harvest(rom url: URL, maxPerVoice: Int = 12, frames: Int = 1200) -> [ChiptunePatch] {
        guard let bytes = try? ROMLoader.load(url: url), bytes.count > 0x150 else { return [] }
        let gb = GameBoy(rom: bytes)

        var patches: [ChiptunePatch] = []
        var seen = Set<String>()
        var waveCount = 0

        gb.mmu.apu.onTrigger = { ch in
            let s = gb.mmu.apu.s
            guard let patch = makePatch(ch: ch, state: s, waveCount: &waveCount) else { return }
            let count = patches.lazy.filter { $0.voice == patch.voice }.count
            guard count < maxPerVoice else { return }
            let sig = signature(patch)
            guard !seen.contains(sig) else { return }
            seen.insert(sig)
            patches.append(patch)
        }

        // Tap Start periodically so games that wait at a title screen begin their music.
        for frame in 0 ..< frames {
            gb.mmu.joypad.set(.start, pressed: (frame % 150) < 4)
            gb.runFrame()
        }
        gb.mmu.apu.onTrigger = nil
        return patches
    }

    private static func makePatch(ch: Int, state s: APUState, waveCount: inout Int) -> ChiptunePatch? {
        switch ch {
        case 0:
            guard s.ch1.dacOn, s.ch1.envInit > 0 else { return nil }
            return ChiptunePatch(voice: .pulse1, name: "PUL1 \(dutyPct(s.ch1.duty))",
                                 duty: s.ch1.duty, envInit: s.ch1.envInit,
                                 envDir: s.ch1.envDir, envPeriod: s.ch1.envPeriod)
        case 1:
            guard s.ch2.dacOn, s.ch2.envInit > 0 else { return nil }
            return ChiptunePatch(voice: .pulse2, name: "PUL2 \(dutyPct(s.ch2.duty))",
                                 duty: s.ch2.duty, envInit: s.ch2.envInit,
                                 envDir: s.ch2.envDir, envPeriod: s.ch2.envPeriod)
        case 2:
            guard s.wave.dacOn, s.wave.volCode > 0 else { return nil }
            waveCount += 1
            return ChiptunePatch(voice: .wave, name: "WAVE \(waveCount)",
                                 waveRAM: s.waveRAM, waveVol: s.wave.volCode)
        case 3:
            guard s.noise.dacOn, s.noise.envInit > 0 else { return nil }
            let nr43 = s.regs[0x12] // NR43 = $FF22
            return ChiptunePatch(voice: .noise, name: nr43 & 0x08 != 0 ? "NOIS hi" : "NOIS lo",
                                 envInit: s.noise.envInit, envDir: s.noise.envDir,
                                 envPeriod: s.noise.envPeriod, noiseReg: nr43)
        default:
            return nil
        }
    }

    private static func dutyPct(_ d: Int) -> String { ["12%", "25%", "50%", "75%"][min(3, max(0, d))] }

    private static func signature(_ p: ChiptunePatch) -> String {
        switch p.voice {
        case .pulse1, .pulse2:
            return "\(p.voice.rawValue):\(p.duty):\(p.envInit):\(p.envDir):\(p.envPeriod)"
        case .wave:
            return "w:" + p.waveRAM.map { String($0, radix: 16) }.joined()
        case .noise:
            return "n:\(p.envInit):\(p.envDir):\(p.envPeriod):\(p.noiseReg)"
        }
    }
}
