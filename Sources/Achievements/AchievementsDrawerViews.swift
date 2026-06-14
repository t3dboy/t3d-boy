// T3d Boy — subviews for the achievements drawer: header (title / box art /
// points / progress arc / hardcore badge / rich presence / leaderboard strip),
// the sign-in banner, the empty state, collapsible section headers, and the
// per-achievement card. All adapt to light/dark and match the control kit.

import Cocoa

// MARK: - Small reusable chip

final class Chip: NSView {
    enum Tone { case neutral, accent, warn, good, hot }

    private let label = NSTextField(labelWithString: "")
    private var tone: Tone = .neutral

    init(_ text: String, tone: Tone = .neutral) {
        super.init(frame: .zero)
        self.tone = tone
        wantsLayer = true
        label.font = uiFont(10, .semibold)
        label.stringValue = text
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 18),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 7),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -7),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        refreshColors()
    }
    required init?(coder: NSCoder) { fatalError() }

    func setText(_ t: String) { label.stringValue = t }
    func setTone(_ t: Tone) { tone = t; refreshColors() }

    override func layout() {
        super.layout()
        layer?.cornerRadius = bounds.height / 2
        refreshColors()
    }

    private func color(for tone: Tone) -> NSColor {
        switch tone {
        case .neutral: return .secondaryLabelColor
        case .accent:  return theme.accent
        case .warn:    return theme.warm
        case .good:    return .systemGreen
        case .hot:     return .systemPink
        }
    }

    private func refreshColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            if tone == .neutral {
                layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.08).cgColor
                label.textColor = .secondaryLabelColor
            } else {
                let c = color(for: tone)
                layer?.backgroundColor = c.withAlphaComponent(0.16).cgColor
                label.textColor = c
            }
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshColors()
    }
}

// MARK: - Header

final class AchievementsHeaderView: NSView {
    private let boxArt = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let consoleBadge = Chip("GB", tone: .accent)
    private let modeBadge = Chip("SOFTCORE", tone: .neutral)
    private let pointsLabel = NSTextField(labelWithString: "")
    private let richLabel = NSTextField(wrappingLabelWithString: "")
    private let errorChip = Chip("", tone: .warn)
    private let progressArc = ProgressArcView()
    private let percentLabel = NSTextField(labelWithString: "")
    private let leaderboardStrip = LeaderboardStrip()
    private var currentBoxArtURL: String?
    private let separator = NSBox()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        build()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func build() {
        boxArt.wantsLayer = true
        boxArt.layer?.cornerRadius = 8
        boxArt.layer?.masksToBounds = true
        boxArt.layer?.borderWidth = 1
        boxArt.imageScaling = .scaleProportionallyUpOrDown   // smooth — raster art
        boxArt.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.font = uiFont(15, .bold)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 2
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        pointsLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        pointsLabel.textColor = .secondaryLabelColor
        pointsLabel.translatesAutoresizingMaskIntoConstraints = false

        richLabel.font = uiFont(11)
        richLabel.textColor = .secondaryLabelColor
        richLabel.maximumNumberOfLines = 2
        richLabel.lineBreakMode = .byTruncatingTail
        richLabel.translatesAutoresizingMaskIntoConstraints = false

        percentLabel.font = uiFont(11, .bold)
        percentLabel.alignment = .center
        percentLabel.translatesAutoresizingMaskIntoConstraints = false

        for v in [consoleBadge, modeBadge, errorChip] {
            v.translatesAutoresizingMaskIntoConstraints = false
        }
        progressArc.translatesAutoresizingMaskIntoConstraints = false
        leaderboardStrip.translatesAutoresizingMaskIntoConstraints = false
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false

        let badges = NSStackView(views: [consoleBadge, modeBadge, errorChip])
        badges.orientation = .horizontal
        badges.spacing = 6
        badges.alignment = .centerY
        badges.translatesAutoresizingMaskIntoConstraints = false

        for v in [boxArt, titleLabel, badges, pointsLabel, richLabel,
                  progressArc, percentLabel, leaderboardStrip, separator] as [NSView] {
            addSubview(v)
        }

        NSLayoutConstraint.activate([
            boxArt.topAnchor.constraint(equalTo: topAnchor, constant: 14),
            boxArt.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            boxArt.widthAnchor.constraint(equalToConstant: 56),
            boxArt.heightAnchor.constraint(equalToConstant: 56),

            titleLabel.topAnchor.constraint(equalTo: boxArt.topAnchor, constant: -2),
            titleLabel.leadingAnchor.constraint(equalTo: boxArt.trailingAnchor, constant: 10),
            titleLabel.trailingAnchor.constraint(equalTo: progressArc.leadingAnchor, constant: -8),

            badges.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 5),
            badges.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            badges.trailingAnchor.constraint(lessThanOrEqualTo: progressArc.leadingAnchor, constant: -8),

            pointsLabel.topAnchor.constraint(equalTo: badges.bottomAnchor, constant: 6),
            pointsLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            pointsLabel.trailingAnchor.constraint(lessThanOrEqualTo: progressArc.leadingAnchor, constant: -8),

            progressArc.topAnchor.constraint(equalTo: topAnchor, constant: 14),
            progressArc.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            progressArc.widthAnchor.constraint(equalToConstant: 48),
            progressArc.heightAnchor.constraint(equalToConstant: 48),

            percentLabel.centerXAnchor.constraint(equalTo: progressArc.centerXAnchor),
            percentLabel.centerYAnchor.constraint(equalTo: progressArc.centerYAnchor),

            richLabel.topAnchor.constraint(equalTo: boxArt.bottomAnchor, constant: 8),
            richLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            richLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),

            leaderboardStrip.topAnchor.constraint(equalTo: richLabel.bottomAnchor, constant: 6),
            leaderboardStrip.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            leaderboardStrip.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),

            separator.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            separator.topAnchor.constraint(equalTo: leaderboardStrip.bottomAnchor, constant: 10),
            separator.heightAnchor.constraint(equalToConstant: 1), // a divider line, not a stretchy spacer
            separator.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        refreshColors()
    }

    func apply(_ state: RAGameState) {
        titleLabel.stringValue = state.title.isEmpty ? "—" : state.title
        consoleBadge.setText(state.consoleBadge)

        if state.hardcore {
            modeBadge.setText("HARDCORE"); modeBadge.setTone(.warn)
            modeBadge.isHidden = false
        } else if state.connection == .loggedIn {
            modeBadge.setText("SOFTCORE"); modeBadge.setTone(.accent)
            modeBadge.isHidden = false
        } else {
            modeBadge.isHidden = true
        }

        pointsLabel.stringValue =
            "\(state.pointsEarned) / \(state.pointsTotal) pts · \(state.unlockedCount)/\(state.totalCount)"

        if let rp = state.richPresence, !rp.isEmpty {
            richLabel.stringValue = rp
            richLabel.isHidden = false
        } else {
            richLabel.stringValue = ""
            richLabel.isHidden = true
        }

        if let err = state.errorMessage, !err.isEmpty {
            errorChip.setText("⚠︎ " + err)
            errorChip.isHidden = false
        } else {
            errorChip.isHidden = true
        }

        let frac = state.totalCount > 0 ? Float(state.unlockedCount) / Float(state.totalCount) : 0
        progressArc.progress = frac
        percentLabel.stringValue = "\(Int((frac * 100).rounded()))%"

        leaderboardStrip.apply(state.leaderboards)

        // Box art (lazy, cancel-safe via URL compare on completion).
        if state.boxArtURL != currentBoxArtURL {
            currentBoxArtURL = state.boxArtURL
            boxArt.image = nil
            let want = state.boxArtURL
            RABadgeCache.shared.image(for: want) { [weak self] img in
                guard let self, self.currentBoxArtURL == want else { return }
                self.boxArt.image = img
            }
        }
        refreshColors()
    }

    private func refreshColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            boxArt.layer?.borderColor = theme.lineHair.cgColor
            boxArt.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.05).cgColor
            percentLabel.textColor = .labelColor
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshColors()
    }
}

// MARK: - Progress arc (slim ring, drawn with CAShapeLayer)

final class ProgressArcView: NSView {
    private let track = CAShapeLayer()
    private let fill = CAShapeLayer()

    var progress: Float = 0 {  // 0…1
        didSet { updateFill() }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        for l in [track, fill] {
            l.fillColor = NSColor.clear.cgColor
            l.lineCap = .round
            layer?.addSublayer(l)
        }
        track.lineWidth = 4
        fill.lineWidth = 4
        refreshColors()
    }
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        let inset: CGFloat = 3
        let rect = bounds.insetBy(dx: inset, dy: inset)
        let radius = min(rect.width, rect.height) / 2
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        // Start at top (90°), sweep clockwise full circle.
        let path = CGMutablePath()
        path.addArc(center: center, radius: radius,
                    startAngle: .pi / 2, endAngle: .pi / 2 - 2 * .pi, clockwise: true)
        track.path = path
        fill.path = path
        updateFill()
        refreshColors()
    }

    private func updateFill() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fill.strokeEnd = CGFloat(max(0, min(1, progress)))
        CATransaction.commit()
    }

    private func refreshColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            track.strokeColor = NSColor.labelColor.withAlphaComponent(0.12).cgColor
            fill.strokeColor = theme.accent.cgColor
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshColors()
    }
}

// MARK: - Leaderboard tracker strip

final class LeaderboardStrip: NSView {
    private let stack = NSStackView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        stack.orientation = .horizontal
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    func apply(_ trackers: [RALeaderboardTracker]) {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        if trackers.isEmpty {
            isHidden = true
            return
        }
        isHidden = false
        for t in trackers.prefix(4) {
            stack.addArrangedSubview(Chip("\(t.title): \(t.value)", tone: .accent))
        }
    }
}

// MARK: - Sign-in banner (soft, pinned at top of the list when logged out)

final class SignInBanner: NSView {
    var onSignInHintTapped: (() -> Void)?
    private let label = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 9
        label.font = uiFont(11.5, .medium)
        label.stringValue = "Sign in to track your progress  ›"
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 34),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        refreshColors()
    }
    required init?(coder: NSCoder) { fatalError() }

    override func mouseUp(with event: NSEvent) { onSignInHintTapped?() }

    private func refreshColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = theme.accent.withAlphaComponent(0.12).cgColor
            label.textColor = theme.accent
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshColors()
    }
}

// MARK: - Empty / unrecognised state

final class EmptyStateView: NSView {
    private let titleLabel = NSTextField(labelWithString: "")
    private let messageLabel = NSTextField(wrappingLabelWithString: "")
    private let linkButton = NSButton()
    private var linkURL: String?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        titleLabel.font = uiFont(14, .semibold)
        titleLabel.alignment = .center
        titleLabel.textColor = .secondaryLabelColor
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        messageLabel.font = uiFont(12)
        messageLabel.alignment = .center
        messageLabel.textColor = .tertiaryLabelColor
        messageLabel.translatesAutoresizingMaskIntoConstraints = false

        linkButton.isBordered = false
        linkButton.bezelStyle = .inline
        linkButton.target = self
        linkButton.action = #selector(openLink)
        linkButton.contentTintColor = theme.accent
        linkButton.translatesAutoresizingMaskIntoConstraints = false
        linkButton.isHidden = true

        for v in [titleLabel, messageLabel, linkButton] as [NSView] { addSubview(v) }
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: topAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor),

            messageLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            messageLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            messageLabel.trailingAnchor.constraint(equalTo: trailingAnchor),

            linkButton.topAnchor.constraint(equalTo: messageLabel.bottomAnchor, constant: 12),
            linkButton.centerXAnchor.constraint(equalTo: centerXAnchor),
            linkButton.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    func configure(title: String, message: String, linkTitle: String?, linkURL: String?) {
        titleLabel.stringValue = title
        messageLabel.stringValue = message
        self.linkURL = linkURL
        if let linkTitle, linkURL != nil {
            let attr = NSAttributedString(string: linkTitle, attributes: [
                .foregroundColor: theme.accent,
                .font: uiFont(12, .medium),
                .underlineStyle: NSUnderlineStyle.single.rawValue,
            ])
            linkButton.attributedTitle = attr
            linkButton.isHidden = false
        } else {
            linkButton.isHidden = true
        }
    }

    @objc private func openLink() {
        guard let s = linkURL, let url = URL(string: s) else { return }
        NSWorkspace.shared.open(url)
    }
}

// MARK: - Collapsible section header

final class SectionHeaderView: NSView {
    var onToggle: (() -> Void)?

    private let disclosure = NSTextField(labelWithString: "▾")
    private let titleLabel = NSTextField(labelWithString: "")
    private let countLabel = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        disclosure.font = uiFont(9, .bold)
        disclosure.textColor = .secondaryLabelColor
        titleLabel.font = uiFont(11, .bold)
        titleLabel.textColor = .secondaryLabelColor
        countLabel.font = .monospacedDigitSystemFont(ofSize: 10.5, weight: .regular)
        countLabel.textColor = .tertiaryLabelColor
        countLabel.alignment = .right

        for v in [disclosure, titleLabel, countLabel] {
            v.translatesAutoresizingMaskIntoConstraints = false
            addSubview(v)
        }
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 22),
            disclosure.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            disclosure.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: disclosure.trailingAnchor, constant: 6),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            countLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            countLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    func configure(title: String, unlocked: Int, total: Int, collapsed: Bool) {
        titleLabel.stringValue = title.uppercased()
        countLabel.stringValue = "\(unlocked)/\(total)"
        disclosure.stringValue = collapsed ? "▸" : "▾"
    }

    override func mouseUp(with event: NSEvent) { onToggle?() }
}

// MARK: - Per-achievement card

final class AchievementCardView: NSView {
    private let badge = NSImageView()
    private let lockOverlay = CALayer()
    private let titleLabel = NSTextField(labelWithString: "")
    private let detailLabel = NSTextField(wrappingLabelWithString: "")
    private let pointsLabel = NSTextField(labelWithString: "")
    private let dateLabel = NSTextField(labelWithString: "")
    private let chipsStack = NSStackView()
    private let progressTrack = NSView()
    private let progressFill = NSView()
    private let progressText = NSTextField(labelWithString: "")
    private var progressFillWidth: NSLayoutConstraint!

    private var state: RAUnlock = .locked
    private var primed = false
    private var currentBadgeURL: String?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 11
        layer?.borderWidth = 1
        build()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func build() {
        badge.wantsLayer = true
        badge.layer?.cornerRadius = 8
        badge.layer?.masksToBounds = true
        badge.imageScaling = .scaleProportionallyUpOrDown   // smooth — raster art
        badge.translatesAutoresizingMaskIntoConstraints = false
        lockOverlay.backgroundColor = NSColor.black.withAlphaComponent(0.45).cgColor
        lockOverlay.cornerRadius = 8
        badge.layer?.addSublayer(lockOverlay)

        titleLabel.font = uiFont(12.5, .semibold)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        detailLabel.font = uiFont(11)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.maximumNumberOfLines = 3
        detailLabel.lineBreakMode = .byTruncatingTail
        detailLabel.translatesAutoresizingMaskIntoConstraints = false

        pointsLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .bold)
        pointsLabel.alignment = .right
        pointsLabel.setContentHuggingPriority(.required, for: .horizontal)
        pointsLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        pointsLabel.translatesAutoresizingMaskIntoConstraints = false

        dateLabel.font = uiFont(9.5)
        dateLabel.textColor = .tertiaryLabelColor
        dateLabel.alignment = .right
        dateLabel.translatesAutoresizingMaskIntoConstraints = false

        chipsStack.orientation = .horizontal
        chipsStack.spacing = 5
        chipsStack.translatesAutoresizingMaskIntoConstraints = false

        progressTrack.wantsLayer = true
        progressTrack.layer?.cornerRadius = 2.5
        progressTrack.translatesAutoresizingMaskIntoConstraints = false
        progressFill.wantsLayer = true
        progressFill.layer?.cornerRadius = 2.5
        progressFill.translatesAutoresizingMaskIntoConstraints = false
        progressTrack.addSubview(progressFill)
        progressText.font = .monospacedDigitSystemFont(ofSize: 9.5, weight: .medium)
        progressText.textColor = .secondaryLabelColor
        progressText.translatesAutoresizingMaskIntoConstraints = false

        for v in [badge, titleLabel, detailLabel, pointsLabel, dateLabel,
                  chipsStack, progressTrack, progressText] as [NSView] {
            addSubview(v)
        }

        progressFillWidth = progressFill.widthAnchor.constraint(equalToConstant: 0)

        NSLayoutConstraint.activate([
            badge.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            badge.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            badge.widthAnchor.constraint(equalToConstant: 48),
            badge.heightAnchor.constraint(equalToConstant: 48),

            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            titleLabel.leadingAnchor.constraint(equalTo: badge.trailingAnchor, constant: 10),
            titleLabel.trailingAnchor.constraint(equalTo: pointsLabel.leadingAnchor, constant: -6),

            pointsLabel.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            pointsLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),

            dateLabel.topAnchor.constraint(equalTo: pointsLabel.bottomAnchor, constant: 2),
            dateLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),

            detailLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 3),
            detailLabel.leadingAnchor.constraint(equalTo: badge.trailingAnchor, constant: 10),
            detailLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),

            chipsStack.topAnchor.constraint(equalTo: detailLabel.bottomAnchor, constant: 6),
            chipsStack.leadingAnchor.constraint(equalTo: badge.trailingAnchor, constant: 10),
            chipsStack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -10),

            progressTrack.topAnchor.constraint(equalTo: chipsStack.bottomAnchor, constant: 7),
            progressTrack.leadingAnchor.constraint(equalTo: badge.trailingAnchor, constant: 10),
            progressTrack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            progressTrack.heightAnchor.constraint(equalToConstant: 5),

            progressFill.leadingAnchor.constraint(equalTo: progressTrack.leadingAnchor),
            progressFill.topAnchor.constraint(equalTo: progressTrack.topAnchor),
            progressFill.bottomAnchor.constraint(equalTo: progressTrack.bottomAnchor),
            progressFillWidth,

            progressText.topAnchor.constraint(equalTo: progressTrack.bottomAnchor, constant: 2),
            progressText.leadingAnchor.constraint(equalTo: badge.trailingAnchor, constant: 10),

            // Bottom anchor flexes onto the progress block or chips depending on
            // what's visible; the lowest visible element pins the card height.
            progressText.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
        ])
    }

    func configure(_ a: RAAchievement, readOnly: Bool) {
        state = a.state
        primed = a.isPrimed

        titleLabel.stringValue = a.title
        detailLabel.stringValue = a.detail
        pointsLabel.stringValue = "\(a.points)"

        // Category / type chips.
        chipsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        if a.category == .unofficial {
            chipsStack.addArrangedSubview(Chip("UNOFFICIAL", tone: .neutral))
        }
        if a.isProgression { chipsStack.addArrangedSubview(Chip("PROGRESSION", tone: .accent)) }
        if a.isWinCondition { chipsStack.addArrangedSubview(Chip("WIN", tone: .good)) }
        if a.isMissable { chipsStack.addArrangedSubview(Chip("MISSABLE", tone: .hot)) }
        chipsStack.isHidden = chipsStack.arrangedSubviews.isEmpty

        // Unlock date.
        if let t = a.unlockTime {
            let df = DateFormatter()
            df.dateStyle = .short; df.timeStyle = .short
            dateLabel.stringValue = "Unlocked " + df.string(from: t)
            dateLabel.isHidden = false
        } else {
            dateLabel.stringValue = ""
            dateLabel.isHidden = true
        }

        // Measured progress bar (animated when value changes).
        if let pct = a.measuredPercent {
            progressTrack.isHidden = false
            progressText.isHidden = (a.measuredProgress == nil)
            progressText.stringValue = a.measuredProgress ?? ""
            layoutProgress(to: CGFloat(max(0, min(1, pct))), animated: true)
        } else {
            progressTrack.isHidden = true
            progressText.isHidden = true
            progressFillWidth.constant = 0
        }

        // Badge art: locked uses the locked URL when present; unlocked the unlocked one.
        let url = (a.state == .locked ? a.badgeURLLocked : a.badgeURLUnlocked)
            ?? a.badgeURLUnlocked ?? a.badgeURLLocked
        if url != currentBadgeURL {
            currentBadgeURL = url
            badge.image = nil
            RABadgeCache.shared.image(for: url) { [weak self] img in
                guard let self, self.currentBadgeURL == url else { return }
                self.badge.image = img
            }
        }

        refreshColors()
        _ = readOnly  // read-only changes nothing visually here; cards are non-interactive.
    }

    private func layoutProgress(to fraction: CGFloat, animated: Bool) {
        layoutSubtreeIfNeeded()
        let target = progressTrack.bounds.width * fraction
        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.35
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                progressFillWidth.animator().constant = target
            }
        } else {
            progressFillWidth.constant = target
        }
    }

    // Briefly pulse the card border (toast click-through target).
    func flashHighlight() {
        guard let layer else { return }
        let anim = CABasicAnimation(keyPath: "borderColor")
        effectiveAppearance.performAsCurrentDrawingAppearance {
            anim.fromValue = theme.accent.cgColor
            anim.toValue = layer.borderColor
        }
        anim.duration = 1.1
        layer.add(anim, forKey: "flash")
    }

    private func refreshColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            // State-distinct fills + borders.
            switch state {
            case .locked:
                layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.04).cgColor
                titleLabel.textColor = .labelColor
                badge.alphaValue = 0.85
                lockOverlay.isHidden = false
                pointsLabel.textColor = .secondaryLabelColor
            case .unlockedSoftcore:
                layer?.backgroundColor = theme.accent.withAlphaComponent(0.07).cgColor
                titleLabel.textColor = .labelColor
                badge.alphaValue = 1
                lockOverlay.isHidden = true
                pointsLabel.textColor = theme.accent
            case .unlockedHardcore:
                layer?.backgroundColor = theme.warm.withAlphaComponent(0.09).cgColor
                titleLabel.textColor = .labelColor
                badge.alphaValue = 1
                lockOverlay.isHidden = true
                pointsLabel.textColor = theme.warm
            }

            // Primed accent border (challenge close to triggering).
            if primed {
                layer?.borderColor = theme.star.withAlphaComponent(0.9).cgColor
                layer?.borderWidth = 1.5
            } else {
                switch state {
                case .unlockedHardcore:
                    layer?.borderColor = theme.warm.withAlphaComponent(0.4).cgColor
                case .unlockedSoftcore:
                    layer?.borderColor = theme.accent.withAlphaComponent(0.35).cgColor
                case .locked:
                    layer?.borderColor = NSColor.labelColor.withAlphaComponent(0.08).cgColor
                }
                layer?.borderWidth = 1
            }

            progressTrack.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.10).cgColor
            progressFill.layer?.backgroundColor = theme.accent.cgColor
        }
    }

    override func layout() {
        super.layout()
        lockOverlay.frame = badge.bounds
        // Keep the fill width in sync if the bar is showing a measured value.
        if !progressTrack.isHidden, progressFillWidth.constant > 0 {
            // No re-animate on relayout; just clamp to current track width.
            progressFillWidth.constant = min(progressFillWidth.constant, progressTrack.bounds.width)
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshColors()
    }
}
