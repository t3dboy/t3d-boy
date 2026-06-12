// T3d Boy — custom control kit: pill tab bar, capsule dropdown, capsule
// buttons. Replaces stock AppKit segmented controls / popups for a more
// polished look while keeping system light/dark adaptivity.

import Cocoa

// Segmented pill bar with an animated sliding accent highlight
final class PillTabBar: NSView {
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
        highlight.wantsLayer = true
        addSubview(highlight)
        for t in titles {
            let label = NSTextField(labelWithString: t)
            label.font = .systemFont(ofSize: 10.5, weight: .semibold)
            label.alignment = .center
            label.lineBreakMode = .byClipping
            addSubview(label)
            labels.append(label)
        }
        heightAnchor.constraint(equalToConstant: 32).isActive = true
    }
    required init?(coder: NSCoder) { fatalError() }

    override func hitTest(_ point: NSPoint) -> NSView? {
        frame.contains(point) ? self : nil
    }

    private func segmentFrame(_ i: Int) -> NSRect {
        let w = bounds.width / CGFloat(titles.count)
        return NSRect(x: CGFloat(i) * w + 3, y: 3, width: w - 6, height: bounds.height - 6)
    }

    override func layout() {
        super.layout()
        layer?.cornerRadius = bounds.height / 2
        highlight.layer?.cornerRadius = (bounds.height - 6) / 2
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

    private func updateSelection(animated: Bool) {
        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.22
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                highlight.animator().frame = segmentFrame(selectedIndex)
            }
        } else {
            highlight.frame = segmentFrame(selectedIndex)
        }
        refreshColors()
    }

    private func refreshColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.07).cgColor
            highlight.layer?.backgroundColor = NSColor.controlAccentColor.cgColor
        }
        for (i, label) in labels.enumerated() {
            label.textColor = i == selectedIndex ? .white : .secondaryLabelColor
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
final class PillDropdown: NSView {
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

        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.lineBreakMode = .byTruncatingTail
        chevron.font = .systemFont(ofSize: 10, weight: .bold)
        chevron.textColor = .secondaryLabelColor
        for v in [label, chevron] {
            v.translatesAutoresizingMaskIntoConstraints = false
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
        layer?.cornerRadius = bounds.height / 2
        refreshColors()
    }

    private func refreshTitle() {
        guard selectedIndex >= 0 && selectedIndex < items.count else { return }
        label.stringValue = titlePrefix + items[selectedIndex]
    }

    private func refreshColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.07).cgColor
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshColors()
    }

    override func mouseDown(with event: NSEvent) {
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

    @objc private func pick(_ sender: NSMenuItem) {
        guard sender.tag != selectedIndex else { return }
        selectedIndex = sender.tag
        onChange?(sender.tag)
    }
}

// Rounded capsule button: prominent (accent fill) or neutral (subtle fill)
final class CapsuleButton: NSView {
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
        didSet { label.stringValue = title }
    }

    init(title: String, style: Style, fontSize: CGFloat = 13, height: CGFloat = 34) {
        self.style = style
        self.title = title
        super.init(frame: .zero)
        wantsLayer = true

        label.stringValue = title
        label.font = .systemFont(ofSize: fontSize, weight: style == .prominent ? .semibold : .medium)
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
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

    override func layout() {
        super.layout()
        layer?.cornerRadius = bounds.height / 2
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
                let base = NSColor.controlAccentColor
                let color = pressed ? base.blended(withFraction: 0.2, of: .black) ?? base
                    : hovered ? base.blended(withFraction: 0.1, of: .white) ?? base
                    : base
                layer?.backgroundColor = color.cgColor
                label.textColor = .white
            case .neutral:
                let alpha: CGFloat = pressed ? 0.18 : hovered ? 0.13 : 0.08
                layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(alpha).cgColor
                label.textColor = .labelColor
            }
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshColors()
    }
}
