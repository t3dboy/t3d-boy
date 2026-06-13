// T3d Boy — RetroAchievements data model (the contract).
//
// This is the seam between the core runtime (which fills these in from rc_client)
// and the drawer UI (which renders them). Pure value types — no rcheevos C types
// leak past the Achievements module. The runtime publishes changes by setting
// `Achievements.shared.gameState` and posting `.achievementsChanged`.

import Foundation

enum RAConnection { case offline, loggedOut, loggedIn }

enum RAIdentification {
    case noGame          // no ROM loaded
    case unrecognised    // ROM loaded, hash not in the RA database
    case recognised      // ROM loaded and identified
}

enum RAUnlock { case locked, unlockedSoftcore, unlockedHardcore }

enum RACategory { case core, unofficial }

struct RAAchievement: Identifiable {
    let id: UInt32
    var title: String
    var detail: String
    var points: Int
    var badgeURLLocked: String?
    var badgeURLUnlocked: String?
    var state: RAUnlock
    var category: RACategory
    var isMissable: Bool
    var isProgression: Bool
    var isWinCondition: Bool
    var measuredPercent: Float?   // 0…1, nil when the achievement isn't "measured"
    var measuredProgress: String? // e.g. "12 / 30"
    var isPrimed: Bool            // challenge indicator (close to triggering)
    var unlockTime: Date?
}

struct RALeaderboardTracker: Identifiable {
    let id: UInt32
    var title: String
    var value: String             // current formatted value
}

struct RAGameState {
    var identification: RAIdentification
    var connection: RAConnection
    var hardcore: Bool
    var title: String
    var consoleBadge: String      // "GB" or "GBC"
    var boxArtURL: String?
    var pointsEarned: Int
    var pointsTotal: Int
    var unlockedCount: Int
    var totalCount: Int
    var richPresence: String?
    var achievements: [RAAchievement]
    var leaderboards: [RALeaderboardTracker]
    var errorMessage: String?     // non-blocking error chip in the header

    static let empty = RAGameState(
        identification: .noGame, connection: .offline, hardcore: false,
        title: "", consoleBadge: "GB", boxArtURL: nil, pointsEarned: 0, pointsTotal: 0,
        unlockedCount: 0, totalCount: 0, richPresence: nil,
        achievements: [], leaderboards: [], errorMessage: nil)
}

struct RAAccount {
    var username: String
    var avatarURL: String?
    var points: Int
}

extension Notification.Name {
    /// Posted when `Achievements.shared.gameState` changes (drawer re-renders).
    static let achievementsChanged = Notification.Name("T3dBoyAchievementsChanged")
    /// Posted on an unlock; userInfo["id"] = achievement id (for the toast).
    static let achievementUnlocked = Notification.Name("T3dBoyAchievementUnlocked")
    /// Posted for leaderboard start/submit/cancel and mastery (userInfo describes it).
    static let achievementEvent = Notification.Name("T3dBoyAchievementEvent")
    /// Posted when a RetroAchievements preference changes (toast corner, sound, etc.).
    static let raSettingsChanged = Notification.Name("T3dBoyRASettingsChanged")
}
