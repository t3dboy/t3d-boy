// T3d Boy — screenshot/demo mode.
//
// When the `T3DBOY_DEMO` environment variable is set, the library is populated with a
// fixed set of made-up, T3d-themed game titles (no real ROMs) and uses the T3d Boy boot
// screen as the box art. This exists purely so marketing screenshots can show the
// interface without any copyrighted game content.

import Cocoa

enum DemoMode {
    static var isActive: Bool { ProcessInfo.processInfo.environment["T3DBOY_DEMO"] != nil }

    struct Game {
        let title: String
        let score: Int    // ♥ review score /100
        let seconds: Int  // play time
        let plays: Int
    }

    // Invented titles — affectionate riffs on famous games, all branded "T3d".
    static let games: [Game] = [
        Game(title: "Super T3d Boy",         score: 99, seconds: 14 * 60,  plays: 23),
        Game(title: "The Legend of T3d",     score: 98, seconds: 47 * 60,  plays: 31),
        Game(title: "T3dtris",               score: 97, seconds: 6 * 60,   plays: 88),
        Game(title: "T3d Kong Country",      score: 95, seconds: 0,        plays: 4),
        Game(title: "Metal Gear T3d",        score: 94, seconds: 24 * 60,  plays: 12),
        Game(title: "Sonic the T3dgehog",    score: 93, seconds: 9 * 60,   plays: 17),
        Game(title: "Final Fantas-T3d VII",  score: 92, seconds: 130 * 60, plays: 9),
        Game(title: "Mega T3d X",            score: 90, seconds: 0,        plays: 2),
        Game(title: "Pokémon T3d Version",   score: 89, seconds: 200 * 60, plays: 41),
        Game(title: "T3do Kart",             score: 88, seconds: 33 * 60,  plays: 26),
        Game(title: "Castlevani-T3d",        score: 86, seconds: 0,        plays: 3),
        Game(title: "Street T3der II",       score: 84, seconds: 15 * 60,  plays: 19),
        Game(title: "Pac-T3d",               score: 82, seconds: 0,        plays: 6),
        Game(title: "T3d Souls",             score: 80, seconds: 51 * 60,  plays: 7),
        Game(title: "Grand Theft T3d",       score: 78, seconds: 0,        plays: 5),
    ]

    /// Fake file URLs whose last path component yields each title via the library's
    /// `displayName()`.
    static let urls: [URL] = games.map { URL(fileURLWithPath: "/T3d Boy Demo/\($0.title).gb") }

    static func game(for url: URL) -> Game? {
        let name = url.deletingPathExtension().lastPathComponent
        return games.first { $0.title == name }
    }

    /// The settled T3d Boy boot screen, used as every game's box art.
    static let art: CGImage? = makeImage(from: BootScreen.frame(140, cgb: false))
}
