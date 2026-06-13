// T3d Boy — RetroAchievements unit tests.
//
// Plain assertion functions runnable from a CLI harness (no XCTest target). Wire
// `RATests.runAll()` into main.swift's argument switch as a "--ratest" case:
//
//     case "--ratest":
//         exit(RATests.runAll() ? 0 : 1)
//
// Covers: (a) hashing a known buffer is stable & correct, (b) memory-map
// translation maps representative RA addresses to the expected GB bus byte against
// a real MMU with known contents, (c) the hardcore-guard helper.

import Foundation
import CryptoKit
import rcheevos

enum RATests {
    private static var failures = 0

    private static func check(_ condition: Bool, _ message: @autoclosure () -> String) {
        if condition {
            print("  ok  — \(message())")
        } else {
            failures += 1
            print("  FAIL — \(message())")
        }
    }

    static func runAll() -> Bool {
        failures = 0
        print("RATests:")
        testHashStability()
        testHashMatchesReferenceMD5()
        testMemoryMapTranslation()
        testHardcoreGuard()
        print(failures == 0 ? "RATests: ALL PASSED" : "RATests: \(failures) FAILURE(S)")
        return failures == 0
    }

    // (a) Hashing is deterministic and console-appropriate.
    private static func testHashStability() {
        let rom = makeSyntheticROM(bankCount: 4)
        let h1 = RAHash.hash(rom: rom, cgb: false)
        let h2 = RAHash.hash(rom: rom, cgb: false)
        check(h1 != nil, "GB hash is produced")
        check(h1 == h2, "GB hash is stable across calls")
        check(h1?.count == 32, "hash is 32 hex chars (got \(h1?.count ?? -1))")

        let hc = RAHash.hash(rom: rom, cgb: true)
        check(hc == h1, "GB and GBC hash agree for the same buffer (full-file MD5)")
    }

    // (a') For GB/GBC, rc_hash is the MD5 of the whole file (verified in
    // hash.c: RC_CONSOLE_GAMEBOY → rc_hash_whole_file). Cross-check rc_hash against
    // an independent MD5 (CryptoKit) of the same bytes so the test pins the exact
    // algorithm without hardcoding a hand-typed constant.
    private static func testHashMatchesReferenceMD5() {
        let rom = makeSyntheticROM(bankCount: 2)
        let h = RAHash.hash(rom: rom, cgb: false)
        let reference = Insecure.MD5.hash(data: Data(rom))
            .map { String(format: "%02x", $0) }.joined()
        check(h == reference,
              "rc_hash GB == whole-file MD5 (rc=\(h ?? "nil"), ref=\(reference))")
    }

    // (b) RA canonical address → MMU byte translation.
    private static func testMemoryMapTranslation() {
        let rom = makeSyntheticROM(bankCount: 4)
        let gb = GameBoy(rom: rom)
        let mmu = gb.mmu

        // Seed known values across the regions we care about.
        // Fixed ROM bank 0: byte 0x0100 is part of the synthetic header marker.
        mmu.write(0xC000, 0x11)            // WRAM bank 0
        mmu.write(0xFF80, 0x22)            // HRAM ("Quick RAM")
        mmu.write(0xFFFF, 0x33)            // Interrupt enable

        // Enable + populate cart RAM bank 0.
        mmu.ramEnabled = true
        mmu.write(0xA000, 0x44)

        // Seed CGB high WRAM (bank 2) and high cart RAM (bank 1) directly in backing
        // store — these are only reachable through RA's synthetic high addresses.
        if mmu.wram.count > 2 * 0x1000 { mmu.wram[2 * 0x1000] = 0x55 }
        if mmu.cartRAM.count > 0x2000 { mmu.cartRAM[0x2000] = 0x66 }

        RAMemory.mmu = mmu
        defer { RAMemory.mmu = nil }

        // Native window: RA addr == GB bus addr.
        check(RAMemory.readByte(0xC000) == mmu.read(0xC000), "RA 0xC000 → WRAM matches bus")
        check(RAMemory.readByte(0xC000) == 0x11, "RA 0xC000 reads seeded WRAM value")
        check(RAMemory.readByte(0xFF80) == 0x22, "RA 0xFF80 reads HRAM value")
        check(RAMemory.readByte(0xFFFF) == 0x33, "RA 0xFFFF reads IE register")
        check(RAMemory.readByte(0xA000) == 0x44, "RA 0xA000 reads cart RAM bank 0")
        check(RAMemory.readByte(0x0100) == mmu.read(0x0100), "RA 0x0100 → ROM header matches bus")

        // Echo RAM (RA exposes it; MMU mirrors it to WRAM).
        check(RAMemory.readByte(0xE000) == mmu.read(0xE000), "RA 0xE000 echo matches bus")

        // Synthetic high banks.
        check(RAMemory.readByte(0x10000) == 0x55, "RA 0x10000 → WRAM bank 2 byte 0")
        check(RAMemory.readByte(0x16000) == 0x66, "RA 0x16000 → cart RAM bank 1 byte 0")

        // Out-of-range: nil (rcheevos treats as invalid).
        check(RAMemory.readByte(0x40000) == nil, "RA address above all regions is nil")

        // Multi-byte callback fills sequentially.
        var buf = [UInt8](repeating: 0xAB, count: 4)
        let n = buf.withUnsafeMutableBufferPointer { p in
            RAMemory.callback(0xC000, p.baseAddress, 4, nil)
        }
        check(n == 4, "callback reads 4 bytes from 0xC000")
        check(buf[0] == 0x11, "callback byte 0 is seeded WRAM value")

        // nil MMU → zero bytes read (subsystem inert without a game).
        RAMemory.mmu = nil
        let zero = buf.withUnsafeMutableBufferPointer { p in
            RAMemory.callback(0xC000, p.baseAddress, 4, nil)
        }
        check(zero == 0, "callback reads 0 bytes when no MMU is set")
    }

    // (c) Hardcore guard helper logic (independent of any live client).
    private static func testHardcoreGuard() {
        check(RAHardcoreAction.loadSaveState.blockedInHardcore, "save-state load blocked")
        check(RAHardcoreAction.rewind.blockedInHardcore, "rewind blocked")
        check(RAHardcoreAction.cheat.blockedInHardcore, "cheats blocked")
        check(RAHardcoreAction.slowMotion.blockedInHardcore, "slow-motion blocked")
        check(!RAHardcoreAction.fastForward.blockedInHardcore, "fast-forward permitted")

        // With no client (subsystem unavailable), nothing is blocked.
        check(!Achievements.shared.hardcoreBlocks(.loadSaveState),
              "no client → hardcore blocks nothing")
    }

    // MARK: - Fixtures

    /// A minimal valid-shape ROM: `bankCount` × 16KB, with a recognisable header
    /// region and per-byte markers so reads are verifiable.
    private static func makeSyntheticROM(bankCount: Int) -> [UInt8] {
        var rom = [UInt8](repeating: 0, count: bankCount * 0x4000)
        // Cartridge header bytes the MMU inspects.
        rom[0x143] = 0x00            // DMG (not CGB)
        rom[0x147] = 0x03            // MBC1 + RAM + battery
        rom[0x149] = 0x03            // 32KB cart RAM (4 banks)
        // Marker in the header window so 0x0100 has a known value.
        rom[0x0100] = 0xC3
        return rom
    }
}
