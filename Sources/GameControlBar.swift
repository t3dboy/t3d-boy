// T3d Boy — subtle in-game control bar.
//
// A small translucent pill at the bottom of the focused game view: lighting
// toggles (Hardcore Lighting, Worm Light), full screen, and power-off (exit).
// It's deliberately understated and auto-hides while you play; the host reveals
// it on mouse movement and hides it again after a short idle.

import Cocoa

final class GameControlBar: NSView {
    var onToggleHardcore: (() -> Void)?
    var onToggleWorm: (() -> Void)?
    var onToggleT3dLight: (() -> Void)?
    var onFullScreen: (() -> Void)?
    var onExit: (() -> Void)?
    var onHoverChange: ((Bool) -> Void)?

    private let hardcoreBtn = GameControlBar.button("sun.max", "Hardcore Lighting")
    private let wormBtn = GameControlBar.button("flashlight.on.fill", "Worm Light")
    private let t3dLightBtn = GameControlBar.button("lightbulb.fill", "T3d Boy Light")
    private let fullBtn = GameControlBar.button("arrow.up.left.and.arrow.down.right", "Full Screen")
    private let exitBtn = GameControlBar.button("power", "Exit")

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true

        let blur = NSVisualEffectView()
        blur.material = .hudWindow
        blur.blendingMode = .withinWindow
        blur.state = .active
        blur.wantsLayer = true
        blur.layer?.cornerRadius = 13
        blur.layer?.masksToBounds = true
        blur.translatesAutoresizingMaskIntoConstraints = false
        addSubview(blur)

        let stack = NSStackView(views: [hardcoreBtn, wormBtn, t3dLightBtn, separator(), fullBtn, exitBtn])
        stack.orientation = .horizontal
        stack.spacing = 4
        stack.alignment = .centerY
        stack.edgeInsets = NSEdgeInsets(top: 5, left: 10, bottom: 5, right: 10)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            blur.topAnchor.constraint(equalTo: topAnchor),
            blur.bottomAnchor.constraint(equalTo: bottomAnchor),
            blur.leadingAnchor.constraint(equalTo: leadingAnchor),
            blur.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])

        hardcoreBtn.target = self; hardcoreBtn.action = #selector(tapHardcore)
        wormBtn.target = self;     wormBtn.action = #selector(tapWorm)
        t3dLightBtn.target = self; t3dLightBtn.action = #selector(tapT3dLight)
        fullBtn.target = self;     fullBtn.action = #selector(tapFull)
        exitBtn.target = self;     exitBtn.action = #selector(tapExit)
        refreshStates()
    }
    required init?(coder: NSCoder) { fatalError() }

    private static func button(_ symbol: String, _ tip: String) -> NSButton {
        let b = NSButton()
        b.isBordered = false
        b.bezelStyle = .regularSquare
        b.imagePosition = .imageOnly
        b.image = NSImage(systemSymbolName: symbol, accessibilityDescription: tip)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 14, weight: .medium))
        b.contentTintColor = NSColor.white.withAlphaComponent(0.78)
        b.toolTip = tip
        b.setAccessibilityLabel(tip)
        b.translatesAutoresizingMaskIntoConstraints = false
        b.widthAnchor.constraint(equalToConstant: 30).isActive = true
        b.heightAnchor.constraint(equalToConstant: 28).isActive = true
        return b
    }

    private func separator() -> NSView {
        let v = NSView()
        v.wantsLayer = true
        v.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.18).cgColor
        v.translatesAutoresizingMaskIntoConstraints = false
        v.widthAnchor.constraint(equalToConstant: 1).isActive = true
        v.heightAnchor.constraint(equalToConstant: 16).isActive = true
        return v
    }

    @objc private func tapHardcore() { onToggleHardcore?(); refreshStates() }
    @objc private func tapWorm() { onToggleWorm?(); refreshStates() }
    @objc private func tapT3dLight() { onToggleT3dLight?(); refreshStates() }
    @objc private func tapFull() { onFullScreen?() }
    @objc private func tapExit() { onExit?() }

    /// Tint the lighting toggles when active so their state reads at a glance.
    func refreshStates() {
        // Hardcore Lighting is unavailable on devices with no ambient-light reading.
        hardcoreBtn.isEnabled = HardcoreLighting.isSupported
        hardcoreBtn.alphaValue = HardcoreLighting.isSupported ? 1 : 0.4
        hardcoreBtn.contentTintColor = HardcoreLighting.isEnabled
            ? theme.star : NSColor.white.withAlphaComponent(0.7)
        wormBtn.contentTintColor = WormLight.isEnabled
            ? theme.warm : NSColor.white.withAlphaComponent(0.7)
        t3dLightBtn.contentTintColor = T3dBoyLight.isEnabled
            ? theme.cool : NSColor.white.withAlphaComponent(0.7)
    }

    func setFullScreen(_ on: Bool) {
        let sym = on ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right"
        fullBtn.image = NSImage(systemSymbolName: sym, accessibilityDescription: "Full Screen")?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 14, weight: .medium))
    }

    private var tracking: NSTrackingArea?
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = tracking { removeTrackingArea(t) }
        let t = NSTrackingArea(rect: bounds,
                               options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                               owner: self)
        addTrackingArea(t); tracking = t
    }
    override func mouseEntered(with event: NSEvent) { onHoverChange?(true) }
    override func mouseExited(with event: NSEvent) { onHoverChange?(false) }
}
