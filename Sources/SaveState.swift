// T3d Boy — save states: full machine snapshot, Codable for disk persistence

import Foundation

struct Snapshot: Codable {
    var version = 1

    // CPU
    var a, f, b, c, d, e, h, l: UInt8
    var sp, pc: UInt16
    var ime, halted: Bool
    var imeDelay: Int

    // Interrupts / misc
    var ifReg, ieReg, dmaReg, key1: UInt8
    var doubleSpeed: Bool

    // Memory
    var wram, hram, ioMisc, cartRAM, vram, oam: Data
    var wramBank: Int

    // MBC
    var ramEnabled: Bool
    var romBankLow, mbc1Hi, mbc1Mode, mbc5Bank, ramBank: Int

    // HDMA
    var hdmaSrc, hdmaDst: UInt16
    var hdmaRemaining: Int
    var hdmaActive: Bool

    // PPU
    var lcdc, statEnable, scy, scx, ly, lyc, bgp, obp0, obp1, wy, wx, bcps, ocps: UInt8
    var vramBank, mode, dot, winLine: Int
    var bgPalRAM, objPalRAM, framebuffer: Data

    // Timer
    var div, tima, tma, tac: UInt8
    var divCounter, timaCounter: Int

    // APU
    var apu: APUState
}

extension GameBoy {
    func snapshot() -> Snapshot {
        let p = mmu.ppu
        let t = mmu.timer
        return Snapshot(
            a: cpu.a, f: cpu.f, b: cpu.b, c: cpu.c,
            d: cpu.d, e: cpu.e, h: cpu.h, l: cpu.l,
            sp: cpu.sp, pc: cpu.pc,
            ime: cpu.ime, halted: cpu.halted, imeDelay: cpu.imeDelay,
            ifReg: mmu.ifReg, ieReg: mmu.ieReg, dmaReg: mmu.dmaReg, key1: mmu.key1,
            doubleSpeed: mmu.doubleSpeed,
            wram: Data(mmu.wram), hram: Data(mmu.hram), ioMisc: Data(mmu.ioMisc),
            cartRAM: Data(mmu.cartRAM), vram: Data(p.vram), oam: Data(p.oam),
            wramBank: mmu.wramBank,
            ramEnabled: mmu.ramEnabled,
            romBankLow: mmu.romBankLow, mbc1Hi: mmu.mbc1Hi, mbc1Mode: mmu.mbc1Mode,
            mbc5Bank: mmu.mbc5Bank, ramBank: mmu.ramBank,
            hdmaSrc: mmu.hdmaSrc, hdmaDst: mmu.hdmaDst,
            hdmaRemaining: mmu.hdmaRemaining, hdmaActive: mmu.hdmaActive,
            lcdc: p.lcdc, statEnable: p.statEnable, scy: p.scy, scx: p.scx,
            ly: p.ly, lyc: p.lyc, bgp: p.bgp, obp0: p.obp0, obp1: p.obp1,
            wy: p.wy, wx: p.wx, bcps: p.bcps, ocps: p.ocps,
            vramBank: p.vramBank, mode: p.mode, dot: p.dot, winLine: p.winLine,
            bgPalRAM: Data(p.bgPalRAM), objPalRAM: Data(p.objPalRAM),
            framebuffer: p.framebuffer.withUnsafeBytes { Data($0) },
            div: t.div, tima: t.tima, tma: t.tma, tac: t.tac,
            divCounter: t.divCounter, timaCounter: t.timaCounter,
            apu: mmu.apu.s
        )
    }

    func restore(_ s: Snapshot) {
        cpu.a = s.a; cpu.f = s.f; cpu.b = s.b; cpu.c = s.c
        cpu.d = s.d; cpu.e = s.e; cpu.h = s.h; cpu.l = s.l
        cpu.sp = s.sp; cpu.pc = s.pc
        cpu.ime = s.ime; cpu.halted = s.halted; cpu.imeDelay = s.imeDelay

        mmu.ifReg = s.ifReg; mmu.ieReg = s.ieReg; mmu.dmaReg = s.dmaReg
        mmu.key1 = s.key1; mmu.doubleSpeed = s.doubleSpeed
        mmu.wram = [UInt8](s.wram); mmu.hram = [UInt8](s.hram)
        mmu.ioMisc = [UInt8](s.ioMisc); mmu.cartRAM = [UInt8](s.cartRAM)
        mmu.wramBank = s.wramBank
        mmu.ramEnabled = s.ramEnabled
        mmu.romBankLow = s.romBankLow; mmu.mbc1Hi = s.mbc1Hi; mmu.mbc1Mode = s.mbc1Mode
        mmu.mbc5Bank = s.mbc5Bank; mmu.ramBank = s.ramBank
        mmu.hdmaSrc = s.hdmaSrc; mmu.hdmaDst = s.hdmaDst
        mmu.hdmaRemaining = s.hdmaRemaining; mmu.hdmaActive = s.hdmaActive

        let p = mmu.ppu
        p.vram = [UInt8](s.vram); p.oam = [UInt8](s.oam)
        p.lcdc = s.lcdc; p.statEnable = s.statEnable; p.scy = s.scy; p.scx = s.scx
        p.ly = s.ly; p.lyc = s.lyc; p.bgp = s.bgp; p.obp0 = s.obp0; p.obp1 = s.obp1
        p.wy = s.wy; p.wx = s.wx; p.bcps = s.bcps; p.ocps = s.ocps
        p.vramBank = s.vramBank; p.mode = s.mode; p.dot = s.dot; p.winLine = s.winLine
        p.bgPalRAM = [UInt8](s.bgPalRAM); p.objPalRAM = [UInt8](s.objPalRAM)
        s.framebuffer.withUnsafeBytes { raw in
            p.framebuffer = Array(raw.bindMemory(to: UInt32.self))
        }
        p.renderBuffer = p.framebuffer // seed the back buffer so a mid-frame load doesn't tear

        let t = mmu.timer
        t.div = s.div; t.tima = s.tima; t.tma = s.tma; t.tac = s.tac
        t.divCounter = s.divCounter; t.timaCounter = s.timaCounter

        mmu.apu.s = s.apu
    }
}
