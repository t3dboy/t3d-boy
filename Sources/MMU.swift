// T3d Boy — memory map, cartridge MBCs, timer, joypad, CGB extras

final class GBTimer {
    var div: UInt8 = 0x18
    var tima: UInt8 = 0, tma: UInt8 = 0, tac: UInt8 = 0
    var divCounter = 0
    var timaCounter = 0

    func resetDiv() { div = 0; divCounter = 0 }

    // Returns true when TIMA overflowed (timer interrupt)
    func step(_ cycles: Int) -> Bool {
        divCounter += cycles
        while divCounter >= 256 {
            divCounter -= 256
            div &+= 1
        }
        guard tac & 0x04 != 0 else { return false }
        let period: Int
        switch tac & 3 {
        case 0: period = 1024
        case 1: period = 16
        case 2: period = 64
        default: period = 256
        }
        var overflow = false
        timaCounter += cycles
        while timaCounter >= period {
            timaCounter -= period
            tima &+= 1
            if tima == 0 {
                tima = tma
                overflow = true
            }
        }
        return overflow
    }
}

final class Joypad {
    weak var mmu: MMU?
    var select: UInt8 = 0x30
    private var buttons: UInt8 = 0x0F // bit0 A, bit1 B, bit2 Select, bit3 Start (0 = pressed)
    private var dpad: UInt8 = 0x0F    // bit0 Right, bit1 Left, bit2 Up, bit3 Down

    enum Button: Int {
        case a = 0, b = 1, selectBtn = 2, start = 3
        case right = 100, left = 101, up = 102, down = 103
    }

    func set(_ button: Button, pressed: Bool) {
        let raw = button.rawValue
        if raw < 100 {
            let mask = UInt8(1) << raw
            if pressed { buttons &= ~mask } else { buttons |= mask }
        } else {
            let mask = UInt8(1) << (raw - 100)
            if pressed { dpad &= ~mask } else { dpad |= mask }
        }
        if pressed { mmu?.ifReg |= 0x10 }
    }

    func read() -> UInt8 {
        var low: UInt8 = 0x0F
        if select & 0x10 == 0 { low &= dpad }
        if select & 0x20 == 0 { low &= buttons }
        return 0xC0 | select | low
    }
}

final class MMU {
    enum MBC { case none, mbc1, mbc2, mbc3, mbc5 }

    let cgbMode: Bool
    var rom: [UInt8]
    let mbc: MBC
    private let romBankCount: Int

    // MBC state (internal so save states can capture it)
    var ramEnabled = false
    var romBankLow = 1
    var mbc1Hi = 0
    var mbc1Mode = 0
    var mbc5Bank = 1
    var ramBank = 0
    var cartRAM: [UInt8]

    // 8 × 4KB WRAM banks (DMG uses the first two)
    var wram = [UInt8](repeating: 0, count: 0x8000)
    var wramBank = 1
    var hram = [UInt8](repeating: 0, count: 0x7F)
    var ioMisc = [UInt8](repeating: 0xFF, count: 0x80)

    var ifReg: UInt8 = 0xE1
    var ieReg: UInt8 = 0x00
    var dmaReg: UInt8 = 0xFF

    // CGB speed switch
    var key1: UInt8 = 0
    var doubleSpeed = false

    // CGB HDMA / GDMA
    var hdmaSrc: UInt16 = 0
    var hdmaDst: UInt16 = 0 // offset within VRAM
    var hdmaRemaining = 0
    var hdmaActive = false

    let ppu = PPU()
    let timer = GBTimer()
    let joypad = Joypad()
    let apu = APU()

    init(rom: [UInt8], cgb: Bool) {
        self.rom = rom
        self.cgbMode = cgb

        let cartType = rom.count > 0x147 ? rom[0x147] : 0
        switch cartType {
        case 0x01...0x03: mbc = .mbc1
        case 0x05, 0x06: mbc = .mbc2
        case 0x0F...0x13: mbc = .mbc3
        case 0x19...0x1E: mbc = .mbc5
        default: mbc = .none
        }
        romBankCount = max(2, rom.count / 0x4000)

        let ramSizes = [0x2000, 0x2000, 0x2000, 0x8000, 0x20000, 0x10000]
        let ramCode = rom.count > 0x149 ? Int(rom[0x149]) : 0
        cartRAM = [UInt8](repeating: 0xFF,
                          count: ramCode < ramSizes.count ? ramSizes[ramCode] : 0x8000)

        ppu.cgb = cgb
        ppu.mmu = self
        joypad.mmu = self
    }

    private func currentROMBank() -> Int {
        let bank: Int
        switch mbc {
        case .mbc1: bank = ((romBankLow == 0 ? 1 : romBankLow) | (mbc1Hi << 5))
        case .mbc2: bank = romBankLow == 0 ? 1 : romBankLow
        case .mbc3: bank = romBankLow == 0 ? 1 : romBankLow
        case .mbc5: bank = mbc5Bank
        case .none: bank = 1
        }
        return bank % romBankCount
    }

    private func currentRAMBank() -> Int {
        switch mbc {
        case .mbc1: return mbc1Mode == 1 ? mbc1Hi : 0
        case .mbc3, .mbc5: return ramBank
        default: return 0
        }
    }

    func read(_ addr: UInt16) -> UInt8 {
        switch addr {
        case 0x0000...0x3FFF:
            return Int(addr) < rom.count ? rom[Int(addr)] : 0xFF
        case 0x4000...0x7FFF:
            let idx = currentROMBank() * 0x4000 + Int(addr - 0x4000)
            return idx < rom.count ? rom[idx] : 0xFF
        case 0x8000...0x9FFF:
            return ppu.cpuReadVRAM(Int(addr - 0x8000))
        case 0xA000...0xBFFF:
            guard ramEnabled else { return 0xFF }
            if mbc == .mbc3 && ramBank >= 8 { return 0x00 } // RTC registers, not emulated
            let idx = currentRAMBank() * 0x2000 + Int(addr - 0xA000)
            return idx < cartRAM.count ? cartRAM[idx] : 0xFF
        case 0xC000...0xCFFF:
            return wram[Int(addr - 0xC000)]
        case 0xD000...0xDFFF:
            return wram[wramBank * 0x1000 + Int(addr - 0xD000)]
        case 0xE000...0xFDFF:
            return read(addr - 0x2000)
        case 0xFE00...0xFE9F:
            return ppu.oam[Int(addr - 0xFE00)]
        case 0xFEA0...0xFEFF:
            return 0xFF
        case 0xFF00...0xFF7F:
            return readIO(addr)
        case 0xFF80...0xFFFE:
            return hram[Int(addr - 0xFF80)]
        default:
            return ieReg
        }
    }

    func write(_ addr: UInt16, _ value: UInt8) {
        switch addr {
        case 0x0000...0x1FFF:
            if mbc == .mbc2 {
                if addr & 0x100 == 0 { ramEnabled = value & 0x0F == 0x0A }
            } else {
                ramEnabled = value & 0x0F == 0x0A
            }
        case 0x2000...0x3FFF:
            switch mbc {
            case .mbc1: romBankLow = Int(value & 0x1F)
            case .mbc2: romBankLow = Int(value & 0x0F)
            case .mbc3: romBankLow = Int(value & 0x7F)
            case .mbc5:
                if addr < 0x3000 { mbc5Bank = (mbc5Bank & 0x100) | Int(value) }
                else { mbc5Bank = (mbc5Bank & 0xFF) | (Int(value & 1) << 8) }
            case .none: break
            }
        case 0x4000...0x5FFF:
            switch mbc {
            case .mbc1: mbc1Hi = Int(value & 3)
            case .mbc3: ramBank = Int(value & 0x0F)
            case .mbc5: ramBank = Int(value & 0x0F)
            default: break
            }
        case 0x6000...0x7FFF:
            if mbc == .mbc1 { mbc1Mode = Int(value & 1) }
        case 0x8000...0x9FFF:
            ppu.cpuWriteVRAM(Int(addr - 0x8000), value)
        case 0xA000...0xBFFF:
            guard ramEnabled else { return }
            if mbc == .mbc3 && ramBank >= 8 { return }
            let idx = currentRAMBank() * 0x2000 + Int(addr - 0xA000)
            if idx < cartRAM.count { cartRAM[idx] = value }
        case 0xC000...0xCFFF:
            wram[Int(addr - 0xC000)] = value
        case 0xD000...0xDFFF:
            wram[wramBank * 0x1000 + Int(addr - 0xD000)] = value
        case 0xE000...0xFDFF:
            write(addr - 0x2000, value)
        case 0xFE00...0xFE9F:
            ppu.oam[Int(addr - 0xFE00)] = value
        case 0xFEA0...0xFEFF:
            break
        case 0xFF00...0xFF7F:
            writeIO(addr, value)
        case 0xFF80...0xFFFE:
            hram[Int(addr - 0xFF80)] = value
        default:
            ieReg = value
        }
    }

    private func readIO(_ addr: UInt16) -> UInt8 {
        switch addr {
        case 0xFF00: return joypad.read()
        case 0xFF04: return timer.div
        case 0xFF05: return timer.tima
        case 0xFF06: return timer.tma
        case 0xFF07: return timer.tac | 0xF8
        case 0xFF0F: return ifReg | 0xE0
        case 0xFF40: return ppu.lcdc
        case 0xFF41: return ppu.statRead()
        case 0xFF42: return ppu.scy
        case 0xFF43: return ppu.scx
        case 0xFF44: return ppu.ly
        case 0xFF45: return ppu.lyc
        case 0xFF46: return dmaReg
        case 0xFF47: return ppu.bgp
        case 0xFF48: return ppu.obp0
        case 0xFF49: return ppu.obp1
        case 0xFF4A: return ppu.wy
        case 0xFF4B: return ppu.wx
        case 0xFF4D:
            return cgbMode ? (doubleSpeed ? 0x80 : 0) | (key1 & 1) | 0x7E : 0xFF
        case 0xFF4F:
            return cgbMode ? 0xFE | UInt8(ppu.vramBank) : 0xFF
        case 0xFF55:
            guard cgbMode else { return 0xFF }
            return hdmaActive ? UInt8((hdmaRemaining - 1) & 0x7F) : 0xFF
        case 0xFF68: return cgbMode ? ppu.bcps : 0xFF
        case 0xFF69: return cgbMode ? ppu.readBCPD() : 0xFF
        case 0xFF6A: return cgbMode ? ppu.ocps : 0xFF
        case 0xFF6B: return cgbMode ? ppu.readOCPD() : 0xFF
        case 0xFF10...0xFF3F: return apu.read(addr)
        case 0xFF70: return cgbMode ? 0xF8 | UInt8(wramBank) : 0xFF
        default: return ioMisc[Int(addr - 0xFF00)]
        }
    }

    private func writeIO(_ addr: UInt16, _ value: UInt8) {
        switch addr {
        case 0xFF00: joypad.select = value & 0x30
        case 0xFF04: timer.resetDiv()
        case 0xFF05: timer.tima = value
        case 0xFF06: timer.tma = value
        case 0xFF07: timer.tac = value & 0x07
        case 0xFF0F: ifReg = value & 0x1F
        case 0xFF10...0xFF3F: apu.write(addr, value)
        case 0xFF40: ppu.writeLCDC(value)
        case 0xFF41: ppu.statEnable = value & 0x78
        case 0xFF42: ppu.scy = value
        case 0xFF43: ppu.scx = value
        case 0xFF44: break // LY is read-only
        case 0xFF45: ppu.lyc = value
        case 0xFF46: // OAM DMA, performed instantly
            dmaReg = value
            let src = UInt16(value) << 8
            for i in 0 ..< 0xA0 {
                ppu.oam[i] = read(src &+ UInt16(i))
            }
        case 0xFF47: ppu.bgp = value
        case 0xFF48: ppu.obp0 = value
        case 0xFF49: ppu.obp1 = value
        case 0xFF4A: ppu.wy = value
        case 0xFF4B: ppu.wx = value
        case 0xFF4D: if cgbMode { key1 = value & 1 }
        case 0xFF4F: if cgbMode { ppu.vramBank = Int(value & 1) }
        case 0xFF51: if cgbMode { hdmaSrc = (hdmaSrc & 0x00FF) | (UInt16(value) << 8) }
        case 0xFF52: if cgbMode { hdmaSrc = (hdmaSrc & 0xFF00) | UInt16(value & 0xF0) }
        case 0xFF53: if cgbMode { hdmaDst = (hdmaDst & 0x00FF) | (UInt16(value & 0x1F) << 8) }
        case 0xFF54: if cgbMode { hdmaDst = (hdmaDst & 0xFF00) | UInt16(value & 0xF0) }
        case 0xFF55: if cgbMode { startVRAMDMA(value) }
        case 0xFF68: if cgbMode { ppu.bcps = value }
        case 0xFF69: if cgbMode { ppu.writeBCPD(value) }
        case 0xFF6A: if cgbMode { ppu.ocps = value }
        case 0xFF6B: if cgbMode { ppu.writeOCPD(value) }
        case 0xFF70: if cgbMode { wramBank = max(1, Int(value & 7)) }
        default: ioMisc[Int(addr - 0xFF00)] = value // sound/serial registers stored, unused
        }
    }

    // MARK: - CGB VRAM DMA

    private func startVRAMDMA(_ value: UInt8) {
        if hdmaActive && value & 0x80 == 0 {
            hdmaActive = false // cancel an in-progress HBlank DMA
            return
        }
        let blocks = Int(value & 0x7F) + 1
        if value & 0x80 != 0 {
            hdmaActive = true
            hdmaRemaining = blocks
        } else {
            for _ in 0 ..< blocks { copyVRAMBlock() } // general-purpose: all at once
        }
    }

    private func copyVRAMBlock() {
        for _ in 0 ..< 16 {
            ppu.cpuWriteVRAM(Int(hdmaDst & 0x1FFF), read(hdmaSrc))
            hdmaSrc &+= 1
            hdmaDst = (hdmaDst &+ 1) & 0x1FFF
        }
    }

    // Called by the PPU at the start of each HBlank
    func hblankDMA() {
        guard hdmaActive else { return }
        copyVRAMBlock()
        hdmaRemaining -= 1
        if hdmaRemaining <= 0 { hdmaActive = false }
    }
}

final class GameBoy {
    let mmu: MMU
    let cpu: CPU
    let cgb: Bool

    static let cyclesPerFrame = 70224

    init(rom: [UInt8]) {
        // CGB flag in the cartridge header: 0x80 = color-enhanced, 0xC0 = color-only
        cgb = rom.count > 0x143 && rom[0x143] & 0x80 != 0
        mmu = MMU(rom: rom, cgb: cgb)
        cpu = CPU(mmu: mmu)
        if cgb { cpu.a = 0x11 } // boot ROM leaves A = 0x11 on CGB hardware
    }

    func runFrame() {
        // The PPU always runs at single speed; in double-speed mode the CPU
        // and timer get two cycles for every PPU dot.
        var dots = 0
        while dots < GameBoy.cyclesPerFrame {
            let c = cpu.step()
            let ppuCycles = mmu.doubleSpeed ? c / 2 : c
            mmu.ppu.step(ppuCycles)
            mmu.apu.step(ppuCycles)
            if mmu.timer.step(c) { mmu.ifReg |= 0x04 }
            dots += ppuCycles
        }
        mmu.apu.flush()
    }
}
