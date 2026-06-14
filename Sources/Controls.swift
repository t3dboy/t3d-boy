// T3d Boy — custom control kit: pill tab bar, capsule dropdown, capsule
// buttons. Replaces stock AppKit segmented controls / popups for a more
// polished look while keeping system light/dark adaptivity.

import Cocoa

// Segmented pill bar with an animated sliding accent highlight
final class PillTabBar: FocusableControl {
    private let titles: [String]
    private var labels: [NSTextField] = []
    private let highlight = NSView()

    var onChange: ((Int) -> Void)?
    var selectedIndex = 0 {
        didSet { updateSelection(animated: true) }
    }

    init(titles: [String]) {
        self.titles = titles
        super.init(frame: .zero)
        wantsLayer = true
        setAccessibilityElement(true)
        setAccessibilityRole(.popUpButton) // one element that cycles consoles — robust for VO
        setAccessibilityLabel("Console")
        highlight.wantsLayer = true
        addSubview(highlight)
        let font: NSFont = theme.skinned ? .rounded(11, .medium) : .systemFont(ofSize: 10.5, weight: .semibold)
        highlight.setAccessibilityElement(false)
        for t in titles {
            let label = NSTextField(labelWithString: theme.cased(t))
            label.font = font
            label.alignment = .center
            label.lineBreakMode = .byClipping
            label.setAccessibilityElement(false) // VoiceOver uses the segment proxies, not these
            addSubview(label)
            labels.append(label)
        }
        heightAnchor.constraint(equalToConstant: 32).isActive = true
    }
    required init?(coder: NSCoder) { fatalError() }

    override func hitTest(_ point: NSPoint) -> NSView? {
        frame.contains(point) ? self : nil
    }

    // MARK: Accessibility — a single element announcing the current console; pressing
    // (or VO arrow keys) cycles to the next. Simpler and more robust for VoiceOver than
    // a synthetic child-element tab group.
    override func accessibilityPerformPress() -> Bool { move(1, wrap: true); return true }

    private func segmentFrame(_ i: Int) -> NSRect {
        let w = bounds.width / CGFloat(titles.count)
        return NSRect(x: CGFloat(i) * w + 3, y: 3, width: w - 6, height: bounds.height - 6)
    }

    override func layout() {
        super.layout()
        layer?.cornerRadius = theme.skinned ? theme.radiusMedium : bounds.height / 2
        highlight.layer?.cornerRadius = theme.skinned ? theme.radiusSmall : (bounds.height - 6) / 2
        let w = bounds.width / CGFloat(titles.count)
        for (i, label) in labels.enumerated() {
            let h = label.intrinsicContentSize.height
            label.frame = NSRect(x: CGFloat(i) * w + 4, y: (bounds.height - h) / 2,
                                 width: w - 8, height: h)
        }
        highlight.frame = segmentFrame(selectedIndex)
        refreshColors()
    }

    override func mouseDown(with event: NSEvent) {
        let x = convert(event.locationInWindow, from: nil).x
        let idx = min(titles.count - 1,
                      max(0, Int(x / (bounds.width / CGFloat(titles.count)))))
        guard idx != selectedIndex else { return }
        selectedIndex = idx
        onChange?(idx)
    }

    // Keyboard: left/right arrows move between segments.
    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 123, 126: move(-1) // left, up
        case 124, 125: move(1)  // right, down
        default: super.keyDown(with: event)
        }
    }
    private func move(_ delta: Int, wrap: Bool = false) {
        let raw = selectedIndex + delta
        let idx = wrap ? (raw % titles.count + titles.count) % titles.count
                       : min(titles.count - 1, max(0, raw))
        guard idx != selectedIndex else { return }
        selectedIndex = idx
        onChange?(idx)
    }

    private func updateSelection(animated: Bool) {
        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = animated && !A11y.reduceMotion ? 0.22 : 0
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                highlight.animator().frame = segmentFrame(selectedIndex)
            }
        } else {
            highlight.frame = segmentFrame(selectedIndex)
        }
        refreshColors()
        if selectedIndex >= 0 && selectedIndex < titles.count {
            setAccessibilityValue(titles[selectedIndex])
        }
    }

    private func refreshColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = theme.surfaceInset.cgColor
            let key = theme.tabAccents?[safe: selectedIndex] ?? theme.accent
            highlight.layer?.backgroundColor = key.cgColor
        }
        for (i, label) in labels.enumerated() {
            label.textColor = i == selectedIndex ? theme.onAccent : theme.textMuted
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshColors()
    }

    func setTooltips(_ tips: [String]) {
        for (label, tip) in zip(labels, tips) { label.toolTip = tip }
    }
}

// Capsule-style dropdown backed by an NSMenu
final class PillDropdown: FocusableControl {
    private let items: [String]
    private let label = NSTextField(labelWithString: "")
    private let chevron = NSTextField(labelWithString: "▾")
    var titlePrefix = ""

    var onChange: ((Int) -> Void)?
    var selectedIndex = 0 {
        didSet { refreshTitle() }
    }

    init(items: [String], titlePrefix: String = "") {
        self.items = items
        self.titlePrefix = titlePrefix
        super.init(frame: .zero)
        wantsLayer = true
        setAccessibilityElement(true)
        setAccessibilityRole(.popUpButton)
        setAccessibilityLabel(titlePrefix.isEmpty ? "Options"
            : titlePrefix.replacingOccurrences(of: ":", with: "").trimmingCharacters(in: .whitespaces))

        label.font = theme.skinned ? .rounded(12, .regular) : .systemFont(ofSize: 12, weight: .medium)
        label.textColor = theme.skinned ? theme.textMuted : theme.textPrimary
        label.lineBreakMode = .byTruncatingTail
        chevron.font = .systemFont(ofSize: 10, weight: .bold)
        chevron.textColor = theme.skinned ? theme.keyYellow : theme.textSecondary
        for v in [label, chevron] {
            v.translatesAutoresizingMaskIntoConstraints = false
            v.setAccessibilityElement(false) // the dropdown itself is the AX element
            addSubview(v)
        }
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 28),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.trailingAnchor.constraint(lessThanOrEqualTo: chevron.leadingAnchor, constant: -6),
            chevron.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            chevron.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        refreshTitle()
    }
    required init?(coder: NSCoder) { fatalError() }

    override func hitTest(_ point: NSPoint) -> NSView? {
        frame.contains(point) ? self : nil
    }

    override func layout() {
        super.layout()
        layer?.cornerRadius = theme.skinned ? theme.radiusSmall : bounds.height / 2
        refreshColors()
    }

    private func refreshTitle() {
        guard selectedIndex >= 0 && selectedIndex < items.count else { return }
        label.stringValue = theme.cased(titlePrefix + items[selectedIndex])
        setAccessibilityValue(items[selectedIndex])
    }

    private func refreshColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = theme.surfaceInset.cgColor
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshColors()
    }

    override func mouseDown(with event: NSEvent) { showMenu() }

    private func showMenu() {
        let menu = NSMenu()
        for (i, title) in items.enumerated() {
            let item = NSMenuItem(title: title, action: #selector(pick(_:)), keyEquivalent: "")
            item.target = self
            item.tag = i
            item.state = i == selectedIndex ? .on : .off
            menu.addItem(item)
        }
        menu.font = .systemFont(ofSize: 12)
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: bounds.height + 6), in: self)
    }

    // MARK: Accessibility — element configured via setters (see init / refreshTitle).
    override func accessibilityPerformPress() -> Bool { showMenu(); return true }
    override func activate() { showMenu() }

    @objc private func pick(_ sender: NSMenuItem) {
        guard sender.tag != selectedIndex else { return }
        selectedIndex = sender.tag
        onChange?(sender.tag)
    }
}

// Rounded capsule button: prominent (accent fill) or neutral (subtle fill)
final class CapsuleButton: FocusableControl {
    enum Style { case prominent, neutral }

    private let style: Style
    private let label = NSTextField(labelWithString: "")
    private var hovered = false
    private var pressed = false

    var onClick: (() -> Void)?
    var isEnabled = true {
        didSet { alphaValue = isEnabled ? 1.0 : 0.4 }
    }
    var title: String {
        didSet { label.stringValue = theme.cased(title); setAccessibilityLabel(title) }
    }

    init(title: String, style: Style, fontSize: CGFloat = 13, height: CGFloat = 34) {
        self.style = style
        self.title = title
        super.init(frame: .zero)
        wantsLayer = true
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(title)

        label.stringValue = theme.cased(title)
        label.font = theme.skinned
            ? .rounded(fontSize, .medium)
            : .systemFont(ofSize: fontSize, weight: style == .prominent ? .semibold : .medium)
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        label.setAccessibilityElement(false) // the button itself is the AX element
        addSubview(label)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: height),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    override func hitTest(_ point: NSPoint) -> NSView? {
        frame.contains(point) ? self : nil
    }

    // MARK: Accessibility — element configured via setters in init (reliable on NSView).
    override var acceptsFirstResponder: Bool { isEnabled }
    override func accessibilityPerformPress() -> Bool {
        guard isEnabled else { return false }
        onClick?()
        return true
    }
    override func activate() { if isEnabled { onClick?() } }

    override func layout() {
        super.layout()
        layer?.cornerRadius = theme.skinned ? theme.radiusMedium : bounds.height / 2
        refreshColors()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow],
            owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) { hovered = true; refreshColors() }
    override func mouseExited(with event: NSEvent) { hovered = false; refreshColors() }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        pressed = true
        refreshColors()
    }

    override func mouseUp(with event: NSEvent) {
        let inside = bounds.contains(convert(event.locationInWindow, from: nil))
        pressed = false
        refreshColors()
        if isEnabled && inside { onClick?() }
    }

    private func refreshColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            switch style {
            case .prominent:
                // The one prominent action is Play → "go" green in the skin, accent otherwise.
                let base = theme.skinned ? theme.keyGreen : theme.accent
                let color = pressed ? base.blended(withFraction: 0.2, of: .black) ?? base
                    : hovered ? base.blended(withFraction: 0.1, of: .white) ?? base
                    : base
                layer?.backgroundColor = color.cgColor
                layer?.borderWidth = 0
                label.textColor = theme.skinned ? theme.onGreen : theme.onAccent
            case .neutral:
                if theme.skinned {
                    // Ghost outline: transparent fill, soft edge, brightens on hover.
                    let a: CGFloat = pressed ? 0.10 : hovered ? 0.06 : 0
                    layer?.backgroundColor = theme.textPrimary.withAlphaComponent(a).cgColor
                    layer?.borderWidth = 1
                    layer?.borderColor = theme.controlEdge.cgColor
                    label.textColor = theme.textSecondary
                } else {
                    let alpha: CGFloat = pressed ? 0.18 : hovered ? 0.13 : 0.08
                    layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(alpha).cgColor
                    layer?.borderWidth = 0
                    label.textColor = .labelColor
                }
            }
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshColors()
    }
}
