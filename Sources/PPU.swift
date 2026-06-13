// T3d Boy — PPU (pixel processing unit), scanline renderer, DMG + CGB

final class PPU {
    weak var mmu: MMU?
    var cgb = false

    // Two 8KB banks; DMG only ever touches bank 0
    var vram = [UInt8](repeating: 0, count: 0x4000)
    var vramBank = 0
    var oam = [UInt8](repeating: 0, count: 0xA0)

    var lcdc: UInt8 = 0x91
    var statEnable: UInt8 = 0 // STAT bits 3-6 (interrupt enables)
    var scy: UInt8 = 0, scx: UInt8 = 0
    var ly: UInt8 = 0, lyc: UInt8 = 0
    var bgp: UInt8 = 0xFC, obp0: UInt8 = 0xFF, obp1: UInt8 = 0xFF
    var wy: UInt8 = 0, wx: UInt8 = 0

    // CGB palette RAM: 8 palettes × 4 colors × 2 bytes (15-bit BGR555)
    var bgPalRAM = [UInt8](repeating: 0xFF, count: 64)
    var objPalRAM = [UInt8](repeating: 0xFF, count: 64)
    var bcps: UInt8 = 0
    var ocps: UInt8 = 0

    var mode = 2
    var dot = 0
    var winLine = 0

    // 0xAARRGGBB, classic DMG green shades, lightest to darkest
    static let palette: [UInt32] = [0xFF9BBC0F, 0xFF8BAC0F, 0xFF306230, 0xFF0F380F]

    // Double-buffered: the PPU renders scanlines into `renderBuffer`; the completed
    // frame is published to `framebuffer` at VBlank. The host only ever reads
    // `framebuffer`, so it never sees a half-drawn frame (which showed as tearing).
    var framebuffer = [UInt32](repeating: PPU.palette[0], count: 160 * 144)
    var renderBuffer = [UInt32](repeating: PPU.palette[0], count: 160 * 144)
    private var bgLine = [UInt8](repeating: 0, count: 160)   // BG color index per pixel
    private var bgPrio = [Bool](repeating: false, count: 160) // CGB BG attribute bit 7

    // MARK: - CPU access (honors the selected VRAM bank)

    func cpuReadVRAM(_ offset: Int) -> UInt8 { vram[vramBank * 0x2000 + offset] }
    func cpuWriteVRAM(_ offset: Int, _ value: UInt8) { vram[vramBank * 0x2000 + offset] = value }

    // MARK: - CGB palette registers (index port + data port with autoincrement)

    func readBCPD() -> UInt8 { bgPalRAM[Int(bcps & 0x3F)] }
    func writeBCPD(_ value: UInt8) {
        bgPalRAM[Int(bcps & 0x3F)] = value
        if bcps & 0x80 != 0 { bcps = 0x80 | ((bcps &+ 1) & 0x3F) }
    }
    func readOCPD() -> UInt8 { objPalRAM[Int(ocps & 0x3F)] }
    func writeOCPD(_ value: UInt8) {
        objPalRAM[Int(ocps & 0x3F)] = value
        if ocps & 0x80 != 0 { ocps = 0x80 | ((ocps &+ 1) & 0x3F) }
    }

    private func cgbColor(_ palRAM: [UInt8], palette: Int, index: Int) -> UInt32 {
        let o = palette * 8 + index * 2
        let v = UInt16(palRAM[o + 1]) << 8 | UInt16(palRAM[o])
        let r = UInt32(v & 0x1F)
        let g = UInt32((v >> 5) & 0x1F)
        let b = UInt32((v >> 10) & 0x1F)
        // 5-bit → 8-bit
        return 0xFF000000
            | (((r << 3) | (r >> 2)) << 16)
            | (((g << 3) | (g >> 2)) << 8)
            | ((b << 3) | (b >> 2))
    }

    // MARK: - Registers

    func statRead() -> UInt8 {
        let coincidence: UInt8 = ly == lyc ? 0x04 : 0
        return 0x80 | statEnable | coincidence | UInt8(lcdc & 0x80 != 0 ? mode : 0)
    }

    func writeLCDC(_ v: UInt8) {
        let wasOn = lcdc & 0x80 != 0
        lcdc = v
        let isOn = v & 0x80 != 0
        if wasOn && !isOn {
            ly = 0; dot = 0; mode = 0; winLine = 0
        } else if !wasOn && isOn {
            mode = 2; dot = 0
            checkLYC()
        }
    }

    private func requestInterrupt(_ bit: UInt8) {
        mmu?.ifReg |= bit
    }

    private func setMode(_ m: Int) {
        mode = m
        switch m {
        case 0:
            if statEnable & 0x08 != 0 { requestInterrupt(0x02) }
            mmu?.hblankDMA()
        case 1: if statEnable & 0x10 != 0 { requestInterrupt(0x02) }
        case 2: if statEnable & 0x20 != 0 { requestInterrupt(0x02) }
        default: break
        }
    }

    private func checkLYC() {
        if ly == lyc && statEnable & 0x40 != 0 { requestInterrupt(0x02) }
    }

    func step(_ cycles: Int) {
        guard lcdc & 0x80 != 0 else { return }
        dot += cycles
        while dot >= 456 {
            dot -= 456
            ly = ly &+ 1
            if ly == 154 { ly = 0; winLine = 0 }
            checkLYC()
            if ly == 144 {
                setMode(1)
                requestInterrupt(0x01) // VBlank
                framebuffer = renderBuffer // publish the just-completed frame
            }
        }
        if ly < 144 {
            if dot < 80 {
                if mode != 2 { setMode(2) }
            } else if dot < 252 {
                if mode != 3 { mode = 3 }
            } else {
                if mode != 0 {
                    renderScanline()
                    setMode(0)
                }
            }
        }
    }

    // MARK: - Rendering

    private func renderScanline() {
        let line = Int(ly)
        guard line < 144 else { return }
        let base = line * 160

        // On CGB, LCDC bit 0 doesn't blank the BG — it only demotes its priority
        if cgb || lcdc & 0x01 != 0 {
            renderBackground(line: line, base: base)
            if lcdc & 0x20 != 0 && ly >= wy && wx <= 166 {
                renderWindow(line: line, base: base)
            }
        } else {
            for x in 0 ..< 160 {
                renderBuffer[base + x] = PPU.palette[0]
                bgLine[x] = 0
                bgPrio[x] = false
            }
        }

        if lcdc & 0x02 != 0 {
            renderSprites(line: line, base: base)
        }
    }

    private func tileDataAddress(_ tileNum: UInt8) -> Int {
        if lcdc & 0x10 != 0 {
            return Int(tileNum) * 16
        }
        return 0x1000 + Int(Int8(bitPattern: tileNum)) * 16
    }

    // Shared BG/window tile fetch: returns the framebuffer color and records
    // index/priority for sprite compositing
    private func drawTilePixel(x: Int, base: Int, mapIndex: Int, py: Int, px: Int) {
        let tileNum = vram[mapIndex]
        if cgb {
            let attr = vram[0x2000 + mapIndex]
            let row = attr & 0x40 != 0 ? 7 - py : py
            let bit = attr & 0x20 != 0 ? px : 7 - px
            let bank = Int((attr >> 3) & 1)
            let addr = bank * 0x2000 + tileDataAddress(tileNum) + row * 2
            let lo = (vram[addr] >> bit) & 1
            let hi = (vram[addr + 1] >> bit) & 1
            let colorIdx = hi << 1 | lo
            bgLine[x] = colorIdx
            bgPrio[x] = attr & 0x80 != 0
            renderBuffer[base + x] = cgbColor(bgPalRAM, palette: Int(attr & 7), index: Int(colorIdx))
        } else {
            let addr = tileDataAddress(tileNum) + py * 2
            let bit = 7 - px
            let lo = (vram[addr] >> bit) & 1
            let hi = (vram[addr + 1] >> bit) & 1
            let colorIdx = hi << 1 | lo
            bgLine[x] = colorIdx
            bgPrio[x] = false
            renderBuffer[base + x] = PPU.palette[Int((bgp >> (colorIdx * 2)) & 3)]
        }
    }

    private func renderBackground(line: Int, base: Int) {
        let mapBase = lcdc & 0x08 != 0 ? 0x1C00 : 0x1800
        let y = (Int(scy) + line) & 0xFF
        let tileRow = y >> 3
        let py = y & 7
        for x in 0 ..< 160 {
            let xx = (Int(scx) + x) & 0xFF
            drawTilePixel(x: x, base: base,
                          mapIndex: mapBase + tileRow * 32 + (xx >> 3),
                          py: py, px: xx & 7)
        }
    }

    private func renderWindow(line: Int, base: Int) {
        let mapBase = lcdc & 0x40 != 0 ? 0x1C00 : 0x1800
        let startX = max(0, Int(wx) - 7)
        guard startX < 160 else { return }
        let y = winLine
        let tileRow = y >> 3
        let py = y & 7
        for x in startX ..< 160 {
            let wxx = x - (Int(wx) - 7)
            drawTilePixel(x: x, base: base,
                          mapIndex: mapBase + tileRow * 32 + (wxx >> 3),
                          py: py, px: wxx & 7)
        }
        winLine += 1
    }

    private func renderSprites(line: Int, base: Int) {
        let height = lcdc & 0x04 != 0 ? 16 : 8

        // Collect up to 10 sprites covering this line, in OAM order
        var selected: [Int] = []
        for i in 0 ..< 40 {
            let sy = Int(oam[i * 4]) - 16
            if line >= sy && line < sy + height {
                selected.append(i)
                if selected.count == 10 { break }
            }
        }
        // Draw lowest priority first so the highest priority lands on top.
        // DMG: smaller X wins, ties broken by OAM index. CGB: OAM index only.
        let ordered: [Int]
        if cgb {
            ordered = selected.reversed()
        } else {
            ordered = selected.enumerated().sorted {
                let xa = oam[$0.element * 4 + 1], xb = oam[$1.element * 4 + 1]
                return xa != xb ? xa > xb : $0.offset > $1.offset
            }.map { $0.element }
        }

        for i in ordered {
            let sy = Int(oam[i * 4]) - 16
            let sx = Int(oam[i * 4 + 1]) - 8
            var tile = oam[i * 4 + 2]
            let attr = oam[i * 4 + 3]
            if height == 16 { tile &= 0xFE }

            var row = line - sy
            if attr & 0x40 != 0 { row = height - 1 - row } // Y flip
            let bank = cgb ? Int((attr >> 3) & 1) : 0
            let addr = bank * 0x2000 + Int(tile) * 16 + row * 2

            for px in 0 ..< 8 {
                let x = sx + px
                guard x >= 0 && x < 160 else { continue }
                let bit = attr & 0x20 != 0 ? px : 7 - px // X flip
                let lo = (vram[addr] >> bit) & 1
                let hi = (vram[addr + 1] >> bit) & 1
                let colorIdx = hi << 1 | lo
                if colorIdx == 0 { continue } // transparent

                if bgLine[x] != 0 {
                    if cgb {
                        // LCDC bit 0 off = sprites always win; otherwise BG wins
                        // if either the BG tile or the sprite requests it
                        if lcdc & 0x01 != 0 && (bgPrio[x] || attr & 0x80 != 0) { continue }
                    } else if attr & 0x80 != 0 {
                        continue
                    }
                }

                if cgb {
                    renderBuffer[base + x] = cgbColor(
                        objPalRAM, palette: Int(attr & 7), index: Int(colorIdx))
                } else {
                    let pal = attr & 0x10 != 0 ? obp1 : obp0
                    renderBuffer[base + x] = PPU.palette[Int((pal >> (colorIdx * 2)) & 3)]
                }
            }
        }
    }
}
