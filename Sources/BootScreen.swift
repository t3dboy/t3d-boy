// T3d Boy — fake boot screen: "T3dboy" logo scrolls down and the classic
// two-note ding plays, in the spirit of the original DMG boot ROM.

import Foundation

enum BootScreen {
    static let scrollFrames = 90   // logo reaches center
    static let dingFrame = 95      // first chime note
    static let totalFrames = 168   // hand over to the game

    // 7×8 chunky pixel glyphs
    private static let glyphs: [Character: [String]] = [
        "T": ["1111111",
              "1111111",
              "0011100",
              "0011100",
              "0011100",
              "0011100",
              "0011100",
              "0011100"],
        "3": ["0111110",
              "1100011",
              "0000011",
              "0011110",
              "0000011",
              "0000011",
              "1100011",
              "0111110"],
        "d": ["0000011",
              "0000011",
              "0111111",
              "1100011",
              "1100011",
              "1100011",
              "1100011",
              "0111111"],
        "b": ["1100000",
              "1100000",
              "1111110",
              "1100011",
              "1100011",
              "1100011",
              "1100011",
              "1111110"],
        "o": ["0000000",
              "0000000",
              "0111110",
              "1100011",
              "1100011",
              "1100011",
              "1100011",
              "0111110"],
        "y": ["0000000",
              "0000000",
              "1100011",
              "1100011",
              "1100011",
              "0111111",
              "0000011",
              "1111110"],
    ]

    // 12×16 Game Boy icon: screen hole on top, d-pad + buttons below
    private static let icon: [String] = [
        "011111111110",
        "111111111111",
        "110000000011",
        "110000000011",
        "110000000011",
        "110000000011",
        "110000000011",
        "110000000011",
        "111111111111",
        "111111111111",
        "111011111111",
        "110001110111",
        "111011111011",
        "111111111111",
        "111111111110",
        "011111111100",
    ]

    // Composed logo bitmap: 0 = empty, 1 = text, 2 = icon
    private static let logo: (width: Int, height: Int, pixels: [UInt8]) = {
        let text = "T3dboy"
        let glyphW = 7, glyphH = 8, spacing = 1
        let iconW = 12, iconH = 16, gap = 5
        let textW = text.count * glyphW + (text.count - 1) * spacing
        let width = iconW + gap + textW
        let height = iconH
        var px = [UInt8](repeating: 0, count: width * height)

        for (r, row) in icon.enumerated() {
            for (c, ch) in row.enumerated() where ch == "1" {
                px[r * width + c] = 2
            }
        }
        let textTop = (iconH - glyphH) / 2
        var x = iconW + gap
        for ch in text {
            if let glyph = glyphs[ch] {
                for (r, row) in glyph.enumerated() {
                    for (c, bit) in row.enumerated() where bit == "1" {
                        px[(textTop + r) * width + x + c] = 1
                    }
                }
            }
            x += glyphW + spacing
        }
        return (width, height, px)
    }()

    static func frame(_ n: Int, cgb: Bool) -> [UInt32] {
        let bg: UInt32 = cgb ? 0xFFFFFFFF : PPU.palette[0]
        let fg: UInt32 = cgb ? 0xFF14141C : PPU.palette[3]
        let accent: UInt32 = cgb ? 0xFF6A4FB8 : PPU.palette[3]

        var fb = [UInt32](repeating: bg, count: 160 * 144)
        let (w, h, px) = logo

        let progress = min(1.0, Double(n) / Double(scrollFrames))
        let yEnd = 72 - h / 2
        let y = Int((Double(yEnd + h) * progress).rounded()) - h
        let x = (160 - w) / 2

        for r in 0 ..< h {
            let sy = y + r
            guard sy >= 0 && sy < 144 else { continue }
            for c in 0 ..< w {
                switch px[r * w + c] {
                case 1: fb[sy * 160 + x + c] = fg
                case 2: fb[sy * 160 + x + c] = accent
                default: break
                }
            }
        }
        return fb
    }

    // The DMG boot chime, using the same register values the real boot ROM
    // writes to square channel 1 (1048 Hz then 2080 Hz, decaying envelope)
    static func dingStep(_ apu: APU, bootFrame: Int) {
        switch bootFrame {
        case dingFrame:
            apu.write(0xFF24, 0x77) // NR50 full volume
            apu.write(0xFF25, 0xF3) // NR51 channel routing
            apu.write(0xFF11, 0x80) // 50% duty
            apu.write(0xFF12, 0xF3) // vol 15, decaying
            apu.write(0xFF13, 0x83)
            apu.write(0xFF14, 0x87) // trigger, 1048 Hz
        case dingFrame + 6:
            apu.write(0xFF13, 0xC1)
            apu.write(0xFF14, 0x87) // trigger, 2080 Hz
        default:
            break
        }
    }
}
