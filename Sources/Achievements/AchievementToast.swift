// T3d Boy — in-game achievement / leaderboard toasts.
//
// A borderless, non-activating panel that slides in from a configurable screen
// corner, shows a badge + title + points (or a leaderboard/mastery variant),
// auto-dismisses after a few seconds, and calls a host handler on click. The
// host typically opens the drawer focused on the unlocked achievement.
//
// Install one controller for the lifetime of the app:
//
//     let toasts = AchievementToastController()
//     toasts.corner = .topRight
//     toasts.onActivate = { id in window.openAchievementsDrawer(focusing: id) }
//     toasts.start()   // begins observing .achievementUnlocked / .achievementEvent
//
// Or fire one directly: AchievementToast.show(.unlock(...), from: .topRight).

import Cocoa

// MARK: - Toast content

enum ToastCorner: Int, CaseIterable {
    case topLeft, topRight, bottomLeft, bottomRight

    var label: String {
        switch self {
        case .topLeft:     return "Top Left"
        case .topRight:    return "Top Right"
        case .bottomLeft:  return "Bottom Left"
        case .bottomRight: return "Bottom Right"
        }
    }
}

enum ToastKind {
    /// Standard achievement unlock. `hardcore` tints the accent.
    case unlock(id: UInt32, title: String, points: Int, badgeURL: String?, hardcore: Bool)
    /// Subtle leaderboard lifecycle notices.
    case leaderboardStart(title: String)
    case leaderboardSubmit(title: String, value: String)
    case leaderboardCancel(title: String)
    /// Big celebratory game-mastery / completion banner.
    case mastery(title: String, hardcore: Bool, badgeURL: String?)

    var clickID: UInt32? {
        if case let .unlock(id, _, _, _, _) = self { return id }
        return nil
    }

    var autoDismiss: TimeInterval {
        switch self {
        case .mastery: return 8
        case .leaderboardStart, .leaderboardCancel: return 3
        default: return 5
        }
    }
}

// MARK: - Controller (observes notifications, manages a queue)

final class AchievementToastController {
    var corner: ToastCorner = .topRight
    /// Called when the user clicks an unlock toast; argument is the achievement id.
    var onActivate: ((UInt32) -> Void)?

    private var observers: [NSObjectProtocol] = []
    private var queue: [ToastKind] = []
    private var current: AchievementToast?

    func start() {
        guard observers.isEmpty else { return }
        let nc = NotificationCenter.default
        observers.append(nc.addObserver(
            forName: .achievementUnlocked, object: nil, queue: .main
        ) { [weak self] note in self?.handleUnlock(note) })
        observers.append(nc.addObserver(
            forName: .achievementEvent, object: nil, queue: .main
        ) { [weak self] note in self?.handleEvent(note) })
    }

    func stop() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
    }

    deinit { stop() }

    // Resolve the unlocked achievement from the current game state for its art.
    private func handleUnlock(_ note: Notification) {
        guard let id = note.userInfo?["id"] as? UInt32 else { return }
        let state = Achievements.shared.gameState
        let ach = state.achievements.first { $0.id == id }
        let hardcore = ach?.state == .unlockedHardcore || state.hardcore
        enqueue(.unlock(
            id: id,
            title: ach?.title ?? "Achievement unlocked",
            points: ach?.points ?? 0,
            badgeURL: ach?.badgeURLUnlocked ?? ach?.badgeURLLocked,
            hardcore: hardcore))
    }

    // .achievementEvent carries a free-form userInfo. We read the conventional
    // keys but degrade gracefully if a field is missing.
    private func handleEvent(_ note: Notification) {
        let info = note.userInfo ?? [:]
        let type = (info["type"] as? String) ?? ""
        let title = (info["title"] as? String) ?? ""
        let value = (info["value"] as? String) ?? ""
        switch type {
        case "leaderboardStart":  enqueue(.leaderboardStart(title: title))
        case "leaderboardSubmit": enqueue(.leaderboardSubmit(title: title, value: value))
        case "leaderboardCancel": enqueue(.leaderboardCancel(title: title))
        case "mastery":
            let state = Achievements.shared.gameState
            enqueue(.mastery(
                title: title.isEmpty ? state.title : title,
                hardcore: (info["hardcore"] as? Bool) ?? state.hardcore,
                badgeURL: (info["badgeURL"] as? String) ?? state.boxArtURL))
        default:
            break
        }
    }

    private func enqueue(_ kind: ToastKind) {
        queue.append(kind)
        pump()
    }

    private func pump() {
        guard current == nil, !queue.isEmpty else { return }
        let kind = queue.removeFirst()
        let toast = AchievementToast(kind: kind, corner: corner)
        toast.onClick = { [weak self] id in
            self?.onActivate?(id)
        }
        toast.onClosed = { [weak self] in
            self?.current = nil
            self?.pump()
        }
        current = toast
        toast.present()
        playUnlockSoundIfWanted(for: kind)
    }

    /// Achievement unlocks (and masteries) play a chime when the user enables it.
    private var unlockSound: NSSound?
    private func playUnlockSoundIfWanted(for kind: ToastKind) {
        switch kind {
        case .unlock, .mastery: break
        default: return
        }
        guard RASettings.unlockSound else { return }
        // Glass is a pleasant built-in "success" chime; no asset to ship.
        let sound = unlockSound ?? NSSound(named: "Glass")
        unlockSound = sound
        sound?.volume = Float(RASettings.unlockVolume)
        sound?.stop()
        sound?.play()
    }
}

// MARK: - The toast window

final class AchievementToast: NSPanel {
    var onClick: ((UInt32) -> Void)?
    var onClosed: (() -> Void)?

    private let kind: ToastKind
    private let corner: ToastCorner
    private var dismissTimer: Timer?

    /// One-shot convenience: build + present a toast without a controller.
    @discardableResult
    static func show(_ kind: ToastKind,
                     from corner: ToastCorner = .topRight,
                     onClick: ((UInt32) -> Void)? = nil) -> AchievementToast {
        let t = AchievementToast(kind: kind, corner: corner)
        t.onClick = onClick
        t.present()
        return t
    }

    init(kind: ToastKind, corner: ToastCorner) {
        self.kind = kind
        self.corner = corner
        let size = AchievementToast.size(for: kind)
        super.init(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false)

        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .floating
        ignoresMouseEvents = false
        isFloatingPanel = true
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]

        contentView = ToastContentView(kind: kind) { [weak self] in
            self?.handleClick()
        }
    }

    private static func size(for kind: ToastKind) -> NSSize {
        switch kind {
        case .mastery: return NSSize(width: 360, height: 96)
        case .leaderboardStart, .leaderboardSubmit, .leaderboardCancel:
            return NSSize(width: 300, height: 56)
        case .unlock: return NSSize(width: 330, height: 76)
        }
    }

    // MARK: - Present / dismiss with a slide-in from the chosen corner

    func present() {
        guard let screen = NSScreen.main else { onClosed?(); return }
        let vf = screen.visibleFrame
        let margin: CGFloat = 18
        let size = frame.size

        let onX: CGFloat
        let offX: CGFloat
        let y: CGFloat
        switch corner {
        case .topLeft:
            onX = vf.minX + margin; offX = vf.minX - size.width
            y = vf.maxY - margin - size.height
        case .topRight:
            onX = vf.maxX - margin - size.width; offX = vf.maxX
            y = vf.maxY - margin - size.height
        case .bottomLeft:
            onX = vf.minX + margin; offX = vf.minX - size.width
            y = vf.minY + margin
        case .bottomRight:
            onX = vf.maxX - margin - size.width; offX = vf.maxX
            y = vf.minY + margin
        }

        setFrameOrigin(NSPoint(x: offX, y: y))
        alphaValue = 0
        orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.28
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animator().setFrameOrigin(NSPoint(x: onX, y: y))
            animator().alphaValue = 1
        }

        let timer = Timer.scheduledTimer(withTimeInterval: kind.autoDismiss, repeats: false) {
            [weak self] _ in self?.dismiss()
        }
        RunLoop.main.add(timer, forMode: .common)
        dismissTimer = timer
    }

    func dismiss() {
        dismissTimer?.invalidate()
        dismissTimer = nil
        guard let screen = NSScreen.main else { close(); onClosed?(); return }
        let vf = screen.visibleFrame
        let offX: CGFloat
        switch corner {
        case .topLeft, .bottomLeft: offX = vf.minX - frame.width
        case .topRight, .bottomRight: offX = vf.maxX
        }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.22
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            animator().setFrameOrigin(NSPoint(x: offX, y: frame.origin.y))
            animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.close()
            self?.onClosed?()
        })
    }

    private func handleClick() {
        if let id = kind.clickID { onClick?(id) }
        dismiss()
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

// MARK: - Toast body (rounded card matching the control kit)

private final class ToastContentView: NSView {
    private let kind: ToastKind
    private let onClick: () -> Void
    private let badge = NSImageView()
    private var hovered = false

    init(kind: ToastKind, onClick: @escaping () -> Void) {
        self.kind = kind
        self.onClick = onClick
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 14
        layer?.masksToBounds = true
        layer?.borderWidth = 1
        build()
        refreshColors()
    }
    required init?(coder: NSCoder) { fatalError() }

    private var accent: NSColor {
        switch kind {
        case let .unlock(_, _, _, _, hardcore):
            return hardcore ? NSColor.systemOrange : NSColor.controlAccentColor
        case let .mastery(_, hardcore, _):
            return hardcore ? NSColor.systemOrange : NSColor.systemYellow
        case .leaderboardStart, .leaderboardSubmit:
            return NSColor.systemTeal
        case .leaderboardCancel:
            return NSColor.systemGray
        }
    }

    private func build() {
        // Accent rail on the leading edge.
        let rail = NSView()
        rail.wantsLayer = true
        rail.translatesAutoresizingMaskIntoConstraints = false
        addSubview(rail)

        let kicker = NSTextField(labelWithString: kickerText())
        kicker.font = .systemFont(ofSize: 10, weight: .bold)
        kicker.textColor = accent
        kicker.translatesAutoresizingMaskIntoConstraints = false

        let titleField = NSTextField(labelWithString: titleText())
        titleField.font = .systemFont(ofSize: isMastery ? 15 : 13,
                                      weight: isMastery ? .bold : .semibold)
        titleField.lineBreakMode = .byTruncatingTail
        titleField.translatesAutoresizingMaskIntoConstraints = false

        let subtitle = NSTextField(labelWithString: subtitleText())
        subtitle.font = .systemFont(ofSize: 11)
        subtitle.textColor = .secondaryLabelColor
        subtitle.lineBreakMode = .byTruncatingTail
        subtitle.translatesAutoresizingMaskIntoConstraints = false

        badge.wantsLayer = true
        badge.layer?.cornerRadius = 8
        badge.layer?.masksToBounds = true
        badge.imageScaling = .scaleProportionallyUpOrDown   // smooth — raster art
        badge.translatesAutoresizingMaskIntoConstraints = false
        addSubview(badge)

        let text = NSStackView(views: [kicker, titleField, subtitle])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 1
        text.translatesAutoresizingMaskIntoConstraints = false
        addSubview(text)

        let hasBadge = badgeURL != nil
        let badgeSize: CGFloat = isMastery ? 64 : 48

        NSLayoutConstraint.activate([
            rail.leadingAnchor.constraint(equalTo: leadingAnchor),
            rail.topAnchor.constraint(equalTo: topAnchor),
            rail.bottomAnchor.constraint(equalTo: bottomAnchor),
            rail.widthAnchor.constraint(equalToConstant: 4),

            badge.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            badge.centerYAnchor.constraint(equalTo: centerYAnchor),
            badge.widthAnchor.constraint(equalToConstant: hasBadge ? badgeSize : 0),
            badge.heightAnchor.constraint(equalToConstant: hasBadge ? badgeSize : 0),

            text.leadingAnchor.constraint(
                equalTo: hasBadge ? badge.trailingAnchor : leadingAnchor,
                constant: hasBadge ? 12 : 18),
            text.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            text.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        if let url = badgeURL {
            RABadgeCache.shared.image(for: url) { [weak self] img in self?.badge.image = img }
        }

        loadAccentRail(rail)
        if isPrimedGlow { addCelebrationGlow() }
    }

    private func loadAccentRail(_ rail: NSView) {
        rail.layer?.backgroundColor = accent.cgColor
    }

    private var isMastery: Bool { if case .mastery = kind { return true }; return false }
    private var isPrimedGlow: Bool { isMastery }

    private func addCelebrationGlow() {
        layer?.shadowColor = accent.cgColor
        layer?.shadowRadius = 12
        layer?.shadowOpacity = 0.5
        layer?.shadowOffset = .zero
        layer?.masksToBounds = false
    }

    private var badgeURL: String? {
        switch kind {
        case let .unlock(_, _, _, url, _): return url
        case let .mastery(_, _, url): return url
        default: return nil
        }
    }

    private func kickerText() -> String {
        switch kind {
        case let .unlock(_, _, _, _, hardcore):
            return hardcore ? "ACHIEVEMENT UNLOCKED · HARDCORE" : "ACHIEVEMENT UNLOCKED"
        case .leaderboardStart: return "LEADERBOARD STARTED"
        case .leaderboardSubmit: return "LEADERBOARD SUBMITTED"
        case .leaderboardCancel: return "LEADERBOARD CANCELLED"
        case let .mastery(_, hardcore, _):
            return hardcore ? "MASTERED · HARDCORE" : "GAME COMPLETED"
        }
    }

    private func titleText() -> String {
        switch kind {
        case let .unlock(_, title, _, _, _): return title
        case let .leaderboardStart(title): return title
        case let .leaderboardSubmit(title, _): return title
        case let .leaderboardCancel(title): return title
        case let .mastery(title, _, _): return title
        }
    }

    private func subtitleText() -> String {
        switch kind {
        case let .unlock(_, _, points, _, _):
            return "\(points) point\(points == 1 ? "" : "s")"
        case .leaderboardStart: return "Tracking your run…"
        case let .leaderboardSubmit(_, value): return "Result: \(value)"
        case .leaderboardCancel: return "Run no longer eligible"
        case let .mastery(_, hardcore, _):
            return hardcore ? "Every achievement earned in hardcore!" : "All achievements earned!"
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) { hovered = true; refreshColors() }
    override func mouseExited(with event: NSEvent) { hovered = false; refreshColors() }
    override func mouseUp(with event: NSEvent) { onClick() }

    private func refreshColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let base = NSColor.windowBackgroundColor
            let bg = hovered ? (base.blended(withFraction: 0.06, of: accent) ?? base) : base
            layer?.backgroundColor = bg.cgColor
            layer?.borderColor = NSColor.labelColor.withAlphaComponent(0.10).cgColor
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshColors()
    }
}
