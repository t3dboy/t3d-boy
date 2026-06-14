// T3d Boy — achievements drawer handle.
//
// A slim, vertically-centred tab the host pins to the right edge of the content it
// sits beside (the emulator viewport, or the library's detail pane). It shows a
// trophy so its purpose — achievements — is obvious, plus a chevron underneath that
// points toward the motion: ">" when collapsed (click to open the drawer, which
// expands rightward) and "<" when expanded (click to collapse it back). The host
// owns the animation; this view only reports intent via `onToggle` and reflects
// state via `isExpanded`.

import Cocoa

final class DrawerHandle: NSView {
    /// Called when the user clicks the handle.
    var onToggle: (() -> Void)?

    /// When true the drawer is open: the chevron points left ("<", click to close).
    /// When false it's closed: the chevron points right (">", click to open).
    var isExpanded = false {
        didSet { updateChevron(animated: true) }
    }

    private let trophy = NSImageView()
    private let chevron = CAShapeLayer()
    private let pill = CALayer()
    private var hovered = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true

        pill.cornerRadius = 8
        layer?.addSublayer(pill)

        let cfg = NSImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
        trophy.image = NSImage(systemSymbolName: "trophy.fill", accessibilityDescription: "Achievements")?
            .withSymbolConfiguration(cfg)
        trophy.image?.isTemplate = true
        trophy.imageScaling = .scaleProportionallyUpOrDown
        addSubview(trophy)

        chevron.fillColor = NSColor.clear.cgColor
        chevron.lineWidth = 2
        chevron.lineCap = .round
        chevron.lineJoin = .round
        layer?.addSublayer(chevron)

        toolTip = "Show achievements"
        refreshColors()
    }
    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: NSSize { NSSize(width: 24, height: 70) }

    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(convert(point, from: superview)) ? self : nil
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        pill.frame = bounds
        // Trophy sits in the upper portion; chevron tucks in below it.
        let icon: CGFloat = 16
        trophy.frame = CGRect(x: (bounds.width - icon) / 2,
                              y: bounds.maxY - icon - 11, width: icon, height: icon)
        updateChevron(animated: false)
        CATransaction.commit()
        refreshColors()
    }

    private func updateChevron(animated: Bool) {
        let midX = bounds.midX
        let cy: CGFloat = 15 // distance up from the bottom edge
        let h: CGFloat = 5   // half-height of the chevron
        let w: CGFloat = 4   // horizontal reach

        // closed → ">" (points right, toward where the drawer opens)
        // open   → "<" (points left, toward collapsing it back)
        let path = CGMutablePath()
        if isExpanded {
            path.move(to: CGPoint(x: midX + w / 2, y: cy + h))
            path.addLine(to: CGPoint(x: midX - w / 2, y: cy))
            path.addLine(to: CGPoint(x: midX + w / 2, y: cy - h))
        } else {
            path.move(to: CGPoint(x: midX - w / 2, y: cy + h))
            path.addLine(to: CGPoint(x: midX + w / 2, y: cy))
            path.addLine(to: CGPoint(x: midX - w / 2, y: cy - h))
        }
        if !animated {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            chevron.path = path
            CATransaction.commit()
        } else {
            chevron.path = path
        }
        toolTip = isExpanded ? "Hide achievements" : "Show achievements"
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self, userInfo: nil))
    }

    /// Reports hover so a host can keep auto-hiding chrome revealed while aimed at.
    var onHoverChange: ((Bool) -> Void)?

    override func mouseEntered(with event: NSEvent) { hovered = true; refreshColors(); onHoverChange?(true) }
    override func mouseExited(with event: NSEvent) { hovered = false; refreshColors(); onHoverChange?(false) }

    override func mouseDown(with event: NSEvent) { /* swallow; act on up */ }

    override func mouseUp(with event: NSEvent) {
        if bounds.contains(convert(event.locationInWindow, from: nil)) {
            onToggle?()
        }
    }

    private func refreshColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let fill = NSColor.labelColor.withAlphaComponent(hovered ? 0.18 : 0.10)
            pill.backgroundColor = fill.cgColor
            let ink = hovered ? NSColor.labelColor : NSColor.secondaryLabelColor
            chevron.strokeColor = ink.cgColor
            trophy.contentTintColor = ink
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshColors()
    }
}
