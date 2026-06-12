// T3d Boy — SM83 (Game Boy CPU) core

final class CPU {
    unowned let mmu: MMU

    // Registers (DMG post-boot-ROM state)
    var a: UInt8 = 0x01, f: UInt8 = 0xB0
    var b: UInt8 = 0x00, c: UInt8 = 0x13
    var d: UInt8 = 0x00, e: UInt8 = 0xD8
    var h: UInt8 = 0x01, l: UInt8 = 0x4D
    var sp: UInt16 = 0xFFFE
    var pc: UInt16 = 0x0100

    var ime = false
    var imeDelay = 0
    var halted = false

    init(mmu: MMU) { self.mmu = mmu }

    // 16-bit register pairs
    var af: UInt16 {
        get { UInt16(a) << 8 | UInt16(f) }
        set { a = UInt8(newValue >> 8); f = UInt8(newValue & 0x00F0) }
    }
    var bc: UInt16 {
        get { UInt16(b) << 8 | UInt16(c) }
        set { b = UInt8(newValue >> 8); c = UInt8(newValue & 0xFF) }
    }
    var de: UInt16 {
        get { UInt16(d) << 8 | UInt16(e) }
        set { d = UInt8(newValue >> 8); e = UInt8(newValue & 0xFF) }
    }
    var hl: UInt16 {
        get { UInt16(h) << 8 | UInt16(l) }
        set { h = UInt8(newValue >> 8); l = UInt8(newValue & 0xFF) }
    }

    // Flags: Z N H C in high nibble of F
    var fz: Bool { f & 0x80 != 0 }
    var fn: Bool { f & 0x40 != 0 }
    var fh: Bool { f & 0x20 != 0 }
    var fc: Bool { f & 0x10 != 0 }
    func setFlags(_ z: Bool, _ n: Bool, _ h: Bool, _ c: Bool) {
        f = (z ? 0x80 : 0) | (n ? 0x40 : 0) | (h ? 0x20 : 0) | (c ? 0x10 : 0)
    }

    func fetch8() -> UInt8 {
        let v = mmu.read(pc)
        pc &+= 1
        return v
    }
    func fetch16() -> UInt16 {
        let lo = fetch8()
        let hi = fetch8()
        return UInt16(hi) << 8 | UInt16(lo)
    }
    func push16(_ v: UInt16) {
        sp &-= 1; mmu.write(sp, UInt8(v >> 8))
        sp &-= 1; mmu.write(sp, UInt8(v & 0xFF))
    }
    func pop16() -> UInt16 {
        let lo = mmu.read(sp); sp &+= 1
        let hi = mmu.read(sp); sp &+= 1
        return UInt16(hi) << 8 | UInt16(lo)
    }

    // r-table: 0=B 1=C 2=D 3=E 4=H 5=L 6=(HL) 7=A
    func getR(_ i: Int) -> UInt8 {
        switch i {
        case 0: return b
        case 1: return c
        case 2: return d
        case 3: return e
        case 4: return h
        case 5: return l
        case 6: return mmu.read(hl)
        default: return a
        }
    }
    func setR(_ i: Int, _ v: UInt8) {
        switch i {
        case 0: b = v
        case 1: c = v
        case 2: d = v
        case 3: e = v
        case 4: h = v
        case 5: l = v
        case 6: mmu.write(hl, v)
        default: a = v
        }
    }

    // Returns T-cycles consumed
    func step() -> Int {
        if imeDelay > 0 {
            imeDelay -= 1
            if imeDelay == 0 { ime = true }
        }
        let pending = mmu.ifReg & mmu.ieReg & 0x1F
        if pending != 0 {
            halted = false
            if ime {
                ime = false
                for bit in 0 ..< 5 where pending & (1 << bit) != 0 {
                    mmu.ifReg &= ~(UInt8(1) << bit)
                    push16(pc)
                    pc = UInt16(0x40 + bit * 8)
                    break
                }
                return 20
            }
        }
        if halted { return 4 }
        return exec(fetch8())
    }

    // MARK: - ALU helpers

    func add(_ v: UInt8, withCarry: Bool = false) {
        let cIn: UInt16 = (withCarry && fc) ? 1 : 0
        let r = UInt16(a) &+ UInt16(v) &+ cIn
        let hf = UInt16(a & 0xF) + UInt16(v & 0xF) + cIn > 0xF
        setFlags(r & 0xFF == 0, false, hf, r > 0xFF)
        a = UInt8(r & 0xFF)
    }
    func sub(_ v: UInt8, withCarry: Bool = false, store: Bool = true) {
        let cIn = (withCarry && fc) ? 1 : 0
        let r = Int(a) - Int(v) - cIn
        let hf = Int(a & 0xF) - Int(v & 0xF) - cIn < 0
        setFlags(r & 0xFF == 0, true, hf, r < 0)
        if store { a = UInt8(r & 0xFF) }
    }
    func andA(_ v: UInt8) { a &= v; setFlags(a == 0, false, true, false) }
    func xorA(_ v: UInt8) { a ^= v; setFlags(a == 0, false, false, false) }
    func orA(_ v: UInt8)  { a |= v; setFlags(a == 0, false, false, false) }

    func inc8(_ v: UInt8) -> UInt8 {
        let r = v &+ 1
        f = (f & 0x10) | (r == 0 ? 0x80 : 0) | ((v & 0xF) == 0xF ? 0x20 : 0)
        return r
    }
    func dec8(_ v: UInt8) -> UInt8 {
        let r = v &- 1
        f = (f & 0x10) | (r == 0 ? 0x80 : 0) | 0x40 | ((v & 0xF) == 0 ? 0x20 : 0)
        return r
    }
    func addHL(_ v: UInt16) {
        let cur = hl
        let r = UInt32(cur) &+ UInt32(v)
        f = (f & 0x80)
            | ((cur & 0xFFF) + (v & 0xFFF) > 0xFFF ? 0x20 : 0)
            | (r > 0xFFFF ? 0x10 : 0)
        hl = UInt16(r & 0xFFFF)
    }
    // Shared by ADD SP,e8 and LD HL,SP+e8
    func spPlusE8() -> UInt16 {
        let off = UInt16(bitPattern: Int16(Int8(bitPattern: fetch8())))
        let hf = (sp & 0xF) + (off & 0xF) > 0xF
        let cf = (sp & 0xFF) + (off & 0xFF) > 0xFF
        setFlags(false, false, hf, cf)
        return sp &+ off
    }

    func daa() {
        var adjust: UInt8 = 0
        var carry = fc
        if !fn {
            if fh || (a & 0x0F) > 0x09 { adjust |= 0x06 }
            if carry || a > 0x99 { adjust |= 0x60; carry = true }
            a = a &+ adjust
        } else {
            if fh { adjust |= 0x06 }
            if carry { adjust |= 0x60 }
            a = a &- adjust
        }
        setFlags(a == 0, fn, false, carry)
    }

    // MARK: - Rotates / shifts

    func rlc(_ v: UInt8, zFlag: Bool) -> UInt8 {
        let r = (v << 1) | (v >> 7)
        setFlags(zFlag && r == 0, false, false, v & 0x80 != 0)
        return r
    }
    func rrc(_ v: UInt8, zFlag: Bool) -> UInt8 {
        let r = (v >> 1) | (v << 7)
        setFlags(zFlag && r == 0, false, false, v & 1 != 0)
        return r
    }
    func rl(_ v: UInt8, zFlag: Bool) -> UInt8 {
        let r = (v << 1) | (fc ? 1 : 0)
        setFlags(zFlag && r == 0, false, false, v & 0x80 != 0)
        return r
    }
    func rr(_ v: UInt8, zFlag: Bool) -> UInt8 {
        let r = (v >> 1) | (fc ? 0x80 : 0)
        setFlags(zFlag && r == 0, false, false, v & 1 != 0)
        return r
    }
    func sla(_ v: UInt8) -> UInt8 {
        let r = v << 1
        setFlags(r == 0, false, false, v & 0x80 != 0)
        return r
    }
    func sra(_ v: UInt8) -> UInt8 {
        let r = (v >> 1) | (v & 0x80)
        setFlags(r == 0, false, false, v & 1 != 0)
        return r
    }
    func swapNibbles(_ v: UInt8) -> UInt8 {
        let r = (v << 4) | (v >> 4)
        setFlags(r == 0, false, false, false)
        return r
    }
    func srl(_ v: UInt8) -> UInt8 {
        let r = v >> 1
        setFlags(r == 0, false, false, v & 1 != 0)
        return r
    }

    // cc-table: 0=NZ 1=Z 2=NC 3=C
    func cond(_ i: Int) -> Bool {
        switch i {
        case 0: return !fz
        case 1: return fz
        case 2: return !fc
        default: return fc
        }
    }

    func aluOp(_ i: Int, _ v: UInt8) {
        switch i {
        case 0: add(v)
        case 1: add(v, withCarry: true)
        case 2: sub(v)
        case 3: sub(v, withCarry: true)
        case 4: andA(v)
        case 5: xorA(v)
        case 6: orA(v)
        default: sub(v, store: false) // CP
        }
    }

    // MARK: - Dispatch

    func exec(_ op: UInt8) -> Int {
        switch op {
        case 0x00: return 4 // NOP
        case 0x01: bc = fetch16(); return 12
        case 0x02: mmu.write(bc, a); return 8
        case 0x03: bc &+= 1; return 8
        case 0x04: b = inc8(b); return 4
        case 0x05: b = dec8(b); return 4
        case 0x06: b = fetch8(); return 8
        case 0x07: a = rlc(a, zFlag: false); return 4
        case 0x08:
            let addr = fetch16()
            mmu.write(addr, UInt8(sp & 0xFF))
            mmu.write(addr &+ 1, UInt8(sp >> 8))
            return 20
        case 0x09: addHL(bc); return 8
        case 0x0A: a = mmu.read(bc); return 8
        case 0x0B: bc &-= 1; return 8
        case 0x0C: c = inc8(c); return 4
        case 0x0D: c = dec8(c); return 4
        case 0x0E: c = fetch8(); return 8
        case 0x0F: a = rrc(a, zFlag: false); return 4

        case 0x10: // STOP: on CGB this performs the speed switch if armed via KEY1
            _ = fetch8()
            if mmu.cgbMode && mmu.key1 & 1 != 0 {
                mmu.doubleSpeed.toggle()
                mmu.key1 = 0
            }
            return 4
        case 0x11: de = fetch16(); return 12
        case 0x12: mmu.write(de, a); return 8
        case 0x13: de &+= 1; return 8
        case 0x14: d = inc8(d); return 4
        case 0x15: d = dec8(d); return 4
        case 0x16: d = fetch8(); return 8
        case 0x17: a = rl(a, zFlag: false); return 4
        case 0x18:
            let off = Int8(bitPattern: fetch8())
            pc = pc &+ UInt16(bitPattern: Int16(off))
            return 12
        case 0x19: addHL(de); return 8
        case 0x1A: a = mmu.read(de); return 8
        case 0x1B: de &-= 1; return 8
        case 0x1C: e = inc8(e); return 4
        case 0x1D: e = dec8(e); return 4
        case 0x1E: e = fetch8(); return 8
        case 0x1F: a = rr(a, zFlag: false); return 4

        case 0x20, 0x28, 0x30, 0x38: // JR cc,e8
            let off = Int8(bitPattern: fetch8())
            if cond(Int((op >> 3) & 3)) {
                pc = pc &+ UInt16(bitPattern: Int16(off))
                return 12
            }
            return 8
        case 0x21: hl = fetch16(); return 12
        case 0x22: mmu.write(hl, a); hl &+= 1; return 8
        case 0x23: hl &+= 1; return 8
        case 0x24: h = inc8(h); return 4
        case 0x25: h = dec8(h); return 4
        case 0x26: h = fetch8(); return 8
        case 0x27: daa(); return 4
        case 0x29: addHL(hl); return 8
        case 0x2A: a = mmu.read(hl); hl &+= 1; return 8
        case 0x2B: hl &-= 1; return 8
        case 0x2C: l = inc8(l); return 4
        case 0x2D: l = dec8(l); return 4
        case 0x2E: l = fetch8(); return 8
        case 0x2F: a = ~a; f |= 0x60; return 4 // CPL

        case 0x31: sp = fetch16(); return 12
        case 0x32: mmu.write(hl, a); hl &-= 1; return 8
        case 0x33: sp &+= 1; return 8
        case 0x34: mmu.write(hl, inc8(mmu.read(hl))); return 12
        case 0x35: mmu.write(hl, dec8(mmu.read(hl))); return 12
        case 0x36: mmu.write(hl, fetch8()); return 12
        case 0x37: f = (f & 0x80) | 0x10; return 4 // SCF
        case 0x39: addHL(sp); return 8
        case 0x3A: a = mmu.read(hl); hl &-= 1; return 8
        case 0x3B: sp &-= 1; return 8
        case 0x3C: a = inc8(a); return 4
        case 0x3D: a = dec8(a); return 4
        case 0x3E: a = fetch8(); return 8
        case 0x3F: f = (f & 0x80) | ((f & 0x10) ^ 0x10); return 4 // CCF

        case 0x76: halted = true; return 4 // HALT
        case 0x40...0x7F: // LD r,r'
            let dst = Int((op >> 3) & 7), src = Int(op & 7)
            setR(dst, getR(src))
            return (dst == 6 || src == 6) ? 8 : 4

        case 0x80...0xBF: // ALU A,r
            aluOp(Int((op >> 3) & 7), getR(Int(op & 7)))
            return op & 7 == 6 ? 8 : 4

        case 0xC0, 0xC8, 0xD0, 0xD8: // RET cc
            if cond(Int((op >> 3) & 3)) { pc = pop16(); return 20 }
            return 8
        case 0xC1: bc = pop16(); return 12
        case 0xC2, 0xCA, 0xD2, 0xDA: // JP cc,a16
            let addr = fetch16()
            if cond(Int((op >> 3) & 3)) { pc = addr; return 16 }
            return 12
        case 0xC3: pc = fetch16(); return 16
        case 0xC4, 0xCC, 0xD4, 0xDC: // CALL cc,a16
            let addr = fetch16()
            if cond(Int((op >> 3) & 3)) { push16(pc); pc = addr; return 24 }
            return 12
        case 0xC5: push16(bc); return 16
        case 0xC6: add(fetch8()); return 8
        case 0xC7, 0xCF, 0xD7, 0xDF, 0xE7, 0xEF, 0xF7, 0xFF: // RST
            push16(pc)
            pc = UInt16(op & 0x38)
            return 16
        case 0xC9: pc = pop16(); return 16
        case 0xCB: return execCB()
        case 0xCD:
            let addr = fetch16()
            push16(pc)
            pc = addr
            return 24
        case 0xCE: add(fetch8(), withCarry: true); return 8

        case 0xD1: de = pop16(); return 12
        case 0xD5: push16(de); return 16
        case 0xD6: sub(fetch8()); return 8
        case 0xD9: pc = pop16(); ime = true; return 16 // RETI
        case 0xDE: sub(fetch8(), withCarry: true); return 8

        case 0xE0: mmu.write(0xFF00 &+ UInt16(fetch8()), a); return 12
        case 0xE1: hl = pop16(); return 12
        case 0xE2: mmu.write(0xFF00 &+ UInt16(c), a); return 8
        case 0xE5: push16(hl); return 16
        case 0xE6: andA(fetch8()); return 8
        case 0xE8: sp = spPlusE8(); return 16
        case 0xE9: pc = hl; return 4
        case 0xEA: mmu.write(fetch16(), a); return 16
        case 0xEE: xorA(fetch8()); return 8

        case 0xF0: a = mmu.read(0xFF00 &+ UInt16(fetch8())); return 12
        case 0xF1: af = pop16(); return 12
        case 0xF2: a = mmu.read(0xFF00 &+ UInt16(c)); return 8
        case 0xF3: ime = false; imeDelay = 0; return 4 // DI
        case 0xF5: push16(af); return 16
        case 0xF6: orA(fetch8()); return 8
        case 0xF8: hl = spPlusE8(); return 12
        case 0xF9: sp = hl; return 8
        case 0xFA: a = mmu.read(fetch16()); return 16
        case 0xFB: imeDelay = 2; return 4 // EI (takes effect after next instruction)
        case 0xFE: sub(fetch8(), store: false); return 8

        default: return 4 // invalid opcodes act as NOP
        }
    }

    func execCB() -> Int {
        let op = fetch8()
        let r = Int(op & 7)
        let n = Int((op >> 3) & 7)
        switch op >> 6 {
        case 0:
            let v = getR(r)
            let res: UInt8
            switch n {
            case 0: res = rlc(v, zFlag: true)
            case 1: res = rrc(v, zFlag: true)
            case 2: res = rl(v, zFlag: true)
            case 3: res = rr(v, zFlag: true)
            case 4: res = sla(v)
            case 5: res = sra(v)
            case 6: res = swapNibbles(v)
            default: res = srl(v)
            }
            setR(r, res)
            return r == 6 ? 16 : 8
        case 1: // BIT n,r
            let v = getR(r)
            f = (f & 0x10) | 0x20 | ((v & (1 << n)) == 0 ? 0x80 : 0)
            return r == 6 ? 12 : 8
        case 2: // RES n,r
            setR(r, getR(r) & ~(UInt8(1) << n))
            return r == 6 ? 16 : 8
        default: // SET n,r
            setR(r, getR(r) | (UInt8(1) << n))
            return r == 6 ? 16 : 8
        }
    }
}
