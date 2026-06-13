// T3d Boy — RetroAchievements user preferences.
//
// A thin, UserDefaults-backed settings store shared by the Preferences window, the
// onboarding step, the toast controller, and the drawer. Writing any property posts
// `.raSettingsChanged` so live UI (toast corner, drawer visibility) can react without
// the writer knowing who's listening. Hardcore is mirrored straight into rc_client.
//
// Note: the "show drawer by default" preference and the per-window "remembered open
// state" are the same flag (`achievementsDrawerOpen`) — toggling the drawer updates
// it, and new windows restore it, which is exactly the behaviour the setting wants.

import Foundation

enum RASettings {
    private static let defaults = UserDefaults.standard

    private enum Key {
        static let hardcore       = "ra.hardcore"
        static let drawerDefault  = "ra.showDrawerByDefault"
        static let unlockSound    = "ra.unlockSound"
        static let unlockVolume   = "ra.unlockVolume"
        static let toastCorner    = "ra.toastCorner"
        static let showFPS        = "ui.showFPS"
    }

    /// Register sensible defaults once at launch (so first reads aren't all "off").
    static func registerDefaults() {
        defaults.register(defaults: [
            Key.unlockSound: true,
            Key.unlockVolume: 0.7,
            Key.toastCorner: ToastCorner.topRight.rawValue,
        ])
    }

    // MARK: - Properties

    /// RA hardcore mode. Mirrored into rc_client whenever it changes.
    static var hardcore: Bool {
        get { defaults.bool(forKey: Key.hardcore) }
        set { set(Key.hardcore, newValue); Achievements.shared.setHardcore(newValue) }
    }

    /// Whether the achievements drawer opens automatically with each window. Off by
    /// default — the drawer stays tucked away so it isn't distracting while playing,
    /// and the user pops it out via the chevron handle when they want to browse.
    static var showDrawerByDefault: Bool {
        get { defaults.bool(forKey: Key.drawerDefault) }
        set { set(Key.drawerDefault, newValue) }
    }

    /// Play a sound when an achievement unlocks.
    static var unlockSound: Bool {
        get { defaults.bool(forKey: Key.unlockSound) }
        set { set(Key.unlockSound, newValue) }
    }

    /// Unlock-sound volume, 0…1.
    static var unlockVolume: Double {
        get { min(1, max(0, defaults.double(forKey: Key.unlockVolume))) }
        set { set(Key.unlockVolume, min(1, max(0, newValue))) }
    }

    /// Show a small FPS counter (with the T3d mascot) in the game window corner.
    static var showFPS: Bool {
        get { defaults.bool(forKey: Key.showFPS) }
        set { set(Key.showFPS, newValue) }
    }

    /// Screen corner the unlock/leaderboard toasts appear in.
    static var toastCorner: ToastCorner {
        get { ToastCorner(rawValue: defaults.integer(forKey: Key.toastCorner)) ?? .topRight }
        set { set(Key.toastCorner, newValue.rawValue) }
    }

    // MARK: -

    private static func set(_ key: String, _ value: Any) {
        defaults.set(value, forKey: key)
        NotificationCenter.default.post(name: .raSettingsChanged, object: nil)
    }
}
