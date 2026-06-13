// T3d Boy — entry point and headless test modes

import Cocoa
import UniformTypeIdentifiers

// MARK: - Headless test: T3dBoy --test <rom> [--frames N] [--out file.png] [--tap frame]...

func runHeadless(_ args: [String]) {
    var frames = 300
    var outPath = "out.png"
    var taps: [Int] = []
    let romPath = args.count > 2 ? args[2] : ""
    var i = 3
    while i < args.count {
        switch args[i] {
        case "--frames": i += 1; frames = Int(args[i]) ?? 300
        case "--out": i += 1; outPath = args[i]
        case "--tap": i += 1; taps.append(Int(args[i]) ?? 0)
        default: break
        }
        i += 1
    }
    guard let rom = try? ROMLoader.load(url: URL(fileURLWithPath: romPath)) else {
        FileHandle.standardError.write("Failed to load ROM: \(romPath)\n".data(using: .utf8)!)
        exit(1)
    }
    let gb = GameBoy(rom: rom)
    var midSnapshot: Data?
    for frame in 0 ..< frames {
        let tapping = taps.contains { frame >= $0 && frame < $0 + 5 }
        gb.mmu.joypad.set(.start, pressed: tapping)
        gb.runFrame()
        if frame == frames / 2, ProcessInfo.processInfo.environment["T3D_STATETEST"] != nil {
            let enc = PropertyListEncoder()
            enc.outputFormat = .binary
            midSnapshot = try? enc.encode(gb.snapshot())
        }
    }
    // State round trip: restore the half-way snapshot, run 2 more frames; the
    // output PNG should show the half-way screen, not the final one
    if let midSnapshot {
        if let snap = try? PropertyListDecoder().decode(Snapshot.self, from: midSnapshot) {
            gb.restore(snap)
            gb.runFrame()
            gb.runFrame()
            print("STATETEST: restored \(midSnapshot.count)-byte snapshot from frame \(frames / 2)")
        } else {
            print("STATETEST: FAILED to decode snapshot")
        }
    }
    guard let img = makeImage(from: gb.mmu.ppu.framebuffer),
          let scaled = scale3x(img) else { exit(1) }
    writePNG(scaled, to: URL(fileURLWithPath: outPath))
    print("Wrote \(outPath) after \(frames) frames (PC=\(String(format: "%04X", gb.cpu.pc)))")
    if ProcessInfo.processInfo.environment["T3D_DEBUG"] != nil {
        let c = gb.cpu, m = gb.mmu
        print(String(format: "AF=%04X BC=%04X DE=%04X HL=%04X SP=%04X IME=%d HALT=%d",
                     c.af, c.bc, c.de, c.hl, c.sp, c.ime ? 1 : 0, c.halted ? 1 : 0))
        print(String(format: "IE=%02X IF=%02X LCDC=%02X STAT=%02X LY=%02X KEY1=%02X 2x=%d",
                     m.ieReg, m.ifReg, m.ppu.lcdc, m.ppu.statRead(), m.ppu.ly,
                     m.key1, m.doubleSpeed ? 1 : 0))
        let bytes = (0 ..< 16).map { String(format: "%02X", m.read(c.pc &+ UInt16($0))) }
        print("PC bytes: " + bytes.joined(separator: " "))
        print(String(format: "APU: %d samples, peak %.3f, NR52=%02X",
                     m.apu.totalSamples, m.apu.maxAmp, m.apu.read(0xFF26)))
    }
}

// MARK: - Art preview: T3dBoy --art <rom> <out.png>  (same path the library uses)

func runArtPreview(_ args: [String]) {
    guard args.count > 3,
          let rom = try? ROMLoader.load(url: URL(fileURLWithPath: args[2])) else {
        FileHandle.standardError.write("Usage: --art <rom> <out.png>\n".data(using: .utf8)!)
        exit(1)
    }
    guard let img = ThumbnailStore.titleScreen(rom: rom), let scaled = scale3x(img) else { exit(1) }
    writePNG(scaled, to: URL(fileURLWithPath: args[3]))
    print("Wrote \(args[3])")
}

func scale3x(_ img: CGImage) -> CGImage? {
    let w = 480, h = 432
    guard let ctx = CGContext(
        data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
            | CGBitmapInfo.byteOrder32Little.rawValue
    ) else { return nil }
    ctx.interpolationQuality = .none
    ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
    return ctx.makeImage()
}

// MARK: - Entry point

let arguments = CommandLine.arguments
switch arguments.count >= 2 ? arguments[1] : "" {
case "--test":
    runHeadless(arguments)
    exit(0)
case "--ratest": // RetroAchievements unit tests (hashing, memory map, hardcore guard)
    exit(RATests.runAll() ? 0 : 1)
case "--art":
    runArtPreview(arguments)
    exit(0)
case "--dingtest": // verify the boot chime's frequency content
    let apu = APU()
    var samples: [Float] = []
    var scratchL = [Float](repeating: 0, count: 2048)
    var scratchR = [Float](repeating: 0, count: 2048)
    for frame in 0 ..< BootScreen.totalFrames {
        BootScreen.dingStep(apu, bootFrame: frame)
        apu.step(GameBoy.cyclesPerFrame) // same bulk stepping the boot screen uses
        apu.flush()
        let n = apu.ring.fill / 2
        scratchL.withUnsafeMutableBufferPointer { l in
            scratchR.withUnsafeMutableBufferPointer { r in
                apu.ring.readDeinterleaved(left: l.baseAddress!, right: r.baseAddress!, frames: n)
            }
        }
        samples.append(contentsOf: scratchL[0 ..< n])
    }
    // Estimate frequency over note 2 (after both triggers) via zero crossings
    let start = Int(Double(BootScreen.dingFrame + 10) / 59.73 * APU.sampleRate)
    let span = Int(APU.sampleRate * 0.25)
    var crossings = 0
    for i in (start + 1) ..< min(start + span, samples.count)
        where (samples[i - 1] < 0) != (samples[i] < 0) { crossings += 1 }
    let freq = Double(crossings) / 2.0 / 0.25
    print(String(format: "Note 2 measured: %.0f Hz (expected ~2080 Hz)", freq))
    exit(0)
case "--boot": // --boot <out.png> [cgb] : render the settled boot logo frame
    let cgb = arguments.contains("cgb")
    let fb = BootScreen.frame(140, cgb: cgb)
    if let img = makeImage(from: fb), let scaled = scale3x(img) {
        writePNG(scaled, to: URL(fileURLWithPath: arguments[2]))
        print("Wrote \(arguments[2])")
    }
    exit(0)
default:
    break
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
