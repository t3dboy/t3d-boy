// T3d Boy — RetroAchievements memory bridge.
//
// rc_client reads emulator memory through a single C callback. RetroAchievements
// defines a *canonical* address space per console (see
// vendor/rcheevos/src/rcheevos/consoleinfo.c, rc_memory_regions_gameboy /
// _gameboy_color). For Game Boy / Game Boy Color that canonical space is, for the
// most part, just the native CPU bus: RA address N (0x0000–0xFFFF) is GB bus
// address N. RA additionally exposes the *paged-out* banks at synthetic addresses
// above 0xFFFF so a memory inspector can always reach them:
//
//   0x00000–0x0FFFF  native GB bus            → MMU.read(addr)
//   0x10000–0x15FFF  WRAM banks 2–7 (CGB)     → wram[bank*0x1000 + ...]
//   0x16000–0x33FFF  cart RAM banks 1–15      → cartRAM[bank*0x2000 + ...]
//
// The MMU read path already resolves the *currently mapped* ROM/RAM/WRAM bank, so
// the 0x0000–0xFFFF window matches exactly what the running game sees. The
// synthetic high banks are read directly out of the MMU's backing arrays (they are
// not reachable through the 16-bit bus). This must be allocation-free and
// lock-free: it is called many times per emulated frame from the do_frame thread.

import Foundation
import rcheevos

enum RAMemory {
    /// The MMU of the active game. The host sets this on game open and clears it on
    /// close. `weak` so the achievement subsystem never keeps a dead core alive.
    static weak var mmu: MMU?

    // Region boundaries (RA canonical addresses).
    private static let nativeTop: UInt32        = 0x0FFFF
    private static let wramHighBase: UInt32      = 0x10000   // CGB WRAM banks 2–7
    private static let wramHighTop: UInt32       = 0x15FFF
    private static let cartHighBase: UInt32      = 0x16000   // cart RAM banks 1–15
    private static let cartHighTop: UInt32       = 0x33FFF

    /// Translate one RA canonical address to a byte value as the running game sees
    /// it. Returns nil if the address is outside any mapped region (RA treats that
    /// as "invalid", which it signals back by reporting fewer bytes read).
    @inline(__always)
    static func readByte(_ address: UInt32) -> UInt8? {
        guard let mmu else { return nil }

        if address <= nativeTop {
            // Direct GB bus read — banked exactly like the CPU sees it.
            return mmu.read(UInt16(address))
        }

        if address >= wramHighBase && address <= wramHighTop {
            // WRAM banks 2–7 live at wram[bank*0x1000 ..]. Bank 0 is 0xC000-window,
            // bank 1 is the 0xD000-window default; RA's high region starts at bank 2.
            let offset = Int(address - wramHighBase)            // 0 ..< 0x6000
            let idx = 2 * 0x1000 + offset
            return idx < mmu.wram.count ? mmu.wram[idx] : nil
        }

        if address >= cartHighBase && address <= cartHighTop {
            // Cart RAM banks 1–15 at cartRAM[bank*0x2000 ..]. High region begins at
            // bank 1, so offset 0 is the first byte of bank 1.
            let offset = Int(address - cartHighBase)            // 0 ..< 0x1E000
            let idx = 0x2000 + offset
            return idx < mmu.cartRAM.count ? mmu.cartRAM[idx] : nil
        }

        return nil
    }

    /// The rc_client read callback. Non-capturing → usable as a C function pointer.
    /// Fills `buffer` with up to `numBytes` and returns the count actually read; a
    /// short/zero return tells rcheevos the address range is (partly) invalid.
    static let callback: rc_client_read_memory_func_t = { address, buffer, numBytes, _ in
        guard let buffer, numBytes > 0 else { return 0 }
        var read: UInt32 = 0
        while read < numBytes {
            guard let byte = RAMemory.readByte(address &+ read) else { break }
            buffer[Int(read)] = byte
            read &+= 1
        }
        return read
    }
}
