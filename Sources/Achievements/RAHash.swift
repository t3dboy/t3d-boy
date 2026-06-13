// T3d Boy — RetroAchievements ROM hashing.
//
// RA identifies a game by an MD5 of the ROM. For Game Boy / Game Boy Color that is
// simply the MD5 of the full file as loaded (headerless — the whole .gb/.gbc), so
// we can hash the in-memory buffer directly via rcheevos' rc_hash. We mostly let
// rc_client do the hashing itself during identify+load; this helper exists for the
// test suite and for any pre-flight "do we recognise this?" checks the UI might do.

import Foundation
import rcheevos

enum RAHash {
    /// Compute RA's canonical hash for a GB/GBC ROM buffer. Returns the 32-char
    /// lowercase MD5 hex string, or nil on failure.
    static func hash(rom: [UInt8], cgb: Bool) -> String? {
        guard !rom.isEmpty else { return nil }
        let console = UInt32(cgb ? RC_CONSOLE_GAMEBOY_COLOR : RC_CONSOLE_GAMEBOY)

        // rc_hash writes a NUL-terminated 32-char hex string into a char[33].
        var out = [CChar](repeating: 0, count: 33)
        let ok = rom.withUnsafeBufferPointer { buf -> Int32 in
            rc_hash_generate_from_buffer(&out, console, buf.baseAddress, buf.count)
        }
        guard ok != 0 else { return nil }
        return String(cString: out)
    }
}
