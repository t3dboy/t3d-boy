// T3d Boy — T3d Tunes drawer: a boutique-synth-style looping soundboard.
//
// Slides out of the top of the library (growing the window taller). Four lanes — the GB's
// four channels — each a 16-step loop you lay sounds into. A playable keyboard at the bottom
// lets you audition any harvested (or built-in) sound across the octaves, optionally through
// the FX knobs. Knobs set per-lane pitch + global FX. Transport runs the loop. Everything
// reads the active theme's tokens, so it re-skins as Classic / Pistachio / Engineer / Liquid Glass.

import Cocoa

// MARK: - Voice palette (themed)

/// A top-down document view for the drawer's scroll view (NSView is bottom-up by default).
final class FlippedView: NSView { override var isFlipped: Bool { true } }

/// A live oscilloscope panel — a framed screen showing the output waveform, refreshed ~30fps.
/// Persistent on the right of the feature-panel area, so it's always visible.
final class LiveScope: NSView {
    weak var engine: ChiptuneEngine?
    private var timer: Timer?
    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = true
    }
    required init?(coder: NSCoder) { fatalError() }

    func start() {
        guard timer == nil else { return }
        let t = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            guard let self, self.window != nil else { return }
            self.needsDisplay = true
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }
    func stop() { timer?.invalidate(); timer = nil; needsDisplay = true }

    override func draw(_ dirtyRect: NSRect) {
        let frame = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5),
                                 xRadius: theme.radiusMedium, yRadius: theme.radiusMedium)
        theme.surfaceScreen.setFill(); frame.fill()
        // centre line
        theme.lineHair.setStroke()
        let mid = NSBezierPath()
        mid.move(to: NSPoint(x: 6, y: bounds.midY)); mid.line(to: NSPoint(x: bounds.maxX - 6, y: bounds.midY))
        mid.lineWidth = 1; mid.stroke()

        if let s = engine?.snapshotScope(), s.count > 1, bounds.width > 1 {
            NSGraphicsContext.current?.saveGraphicsState()
            frame.addClip()
            let cy = bounds.midY, amp = bounds.height * 0.42, gain: CGFloat = 2.4, n = s.count
            let wave = NSBezierPath()
            wave.lineWidth = 1.5; wave.lineCapStyle = .round; wave.lineJoinStyle = .round
            for i in 0 ..< n {
                let x = bounds.width * CGFloat(i) / CGFloat(n - 1)
                let y = cy + max(-1, min(1, CGFloat(s[i]) * gain)) * amp
                if i == 0 { wave.move(to: NSPoint(x: x, y: y)) } else { wave.line(to: NSPoint(x: x, y: y)) }
            }
            theme.accent.setStroke(); wave.stroke()
            NSGraphicsContext.current?.restoreGraphicsState()
        }
        theme.controlEdge.setStroke(); frame.lineWidth = 1; frame.stroke()
    }
}

func voiceColor(_ v: ChipVoice) -> NSColor {
    switch v {
    case .pulse1: return theme.keyCoral
    case .pulse2: return theme.keyBlue
    case .wave:   return theme.keyGreen
    case .noise:  return theme.keyYellow
    }
}

// MARK: - LED step cell

final class ChipStep: NSView {
    var on = false { didSet { needsDisplay = true; if on && !oldValue { pulse() } } }
    var playing = false { didSet { needsDisplay = true } }
    var tint: NSColor = .systemBlue
    var onToggle: (() -> Void)?
    private let pulseLayer = CALayer()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        pulseLayer.opacity = 0
        layer?.addSublayer(pulseLayer)
    }
    required init?(coder: NSCoder) { fatalError() }
    override func mouseDown(with event: NSEvent) { onToggle?() }

    /// A quick expanding glow when a step is switched on — the "layering in" feedback.
    private func pulse() {
        let r = bounds.insetBy(dx: 1.5, dy: 1.5)
        pulseLayer.frame = r
        pulseLayer.cornerRadius = theme.toggleSquared ? 2 : 5
        pulseLayer.backgroundColor = tint.cgColor
        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = 1.0; scale.toValue = 1.9
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0.6; fade.toValue = 0
        let group = CAAnimationGroup()
        group.animations = [scale, fade]
        group.duration = 0.4
        group.timingFunction = CAMediaTimingFunction(name: .easeOut)
        pulseLayer.add(group, forKey: "pulse")
    }

    override func draw(_ dirtyRect: NSRect) {
        let r = bounds.insetBy(dx: 1.5, dy: 1.5)
        let radius = theme.toggleSquared ? 2.0 : 5.0
        let path = NSBezierPath(roundedRect: r, xRadius: radius, yRadius: radius)
        if on {
            (playing ? NSColor.white : tint).setFill(); path.fill()
            tint.setStroke()
        } else {
            (playing ? tint.withAlphaComponent(0.35) : theme.textPrimary.withAlphaComponent(0.07)).setFill()
            path.fill()
            theme.lineHair.setStroke()
        }
        path.lineWidth = 1; path.stroke()
    }
}

// MARK: - Playable keyboard

/// A single piano key. White and black keys differ only in colour/size (set by the host).
final class ChipKey: NSView {
    // Cached once and retained for the app's lifetime. Creating a system font on every
    // draw (30+×/s while playing) can hand back an autoreleased font that's freed before
    // CoreText finishes sizing it — an intermittent "nil object in ApplyFont" crash.
    private static let octaveFont = NSFont.monospacedSystemFont(ofSize: 8, weight: .medium)
    private static let typeFont = NSFont.monospacedSystemFont(ofSize: 9, weight: .semibold)

    let note: Int
    let isBlack: Bool
    var onDown: ((Int) -> Void)?
    var typeLabel: String?                                  // the QWERTY key bound to this note
    private var pressed = false { didSet { needsDisplay = true } }
    func setPressed(_ p: Bool) { pressed = p }              // driven by the typing keyboard too

    init(note: Int, isBlack: Bool) {
        self.note = note
        self.isBlack = isBlack
        super.init(frame: .zero)
        wantsLayer = true
    }
    required init?(coder: NSCoder) { fatalError() }

    override func mouseDown(with event: NSEvent) { pressed = true; onDown?(note) }
    override func mouseDragged(with event: NSEvent) {} // swallow so the key stays pressed
    override func mouseUp(with event: NSEvent) { pressed = false }

    override func draw(_ dirtyRect: NSRect) {
        let r = bounds.insetBy(dx: 0.5, dy: 0.5)
        let radius: CGFloat = theme.toggleSquared ? 2 : 4
        // Round only the bottom corners for a key-cap look.
        let path = NSBezierPath()
        path.move(to: NSPoint(x: r.minX, y: r.maxY))
        path.line(to: NSPoint(x: r.minX, y: r.minY + radius))
        path.appendArc(withCenter: NSPoint(x: r.minX + radius, y: r.minY + radius),
                       radius: radius, startAngle: 180, endAngle: 270)
        path.line(to: NSPoint(x: r.maxX - radius, y: r.minY))
        path.appendArc(withCenter: NSPoint(x: r.maxX - radius, y: r.minY + radius),
                       radius: radius, startAngle: 270, endAngle: 360)
        path.line(to: NSPoint(x: r.maxX, y: r.maxY))
        path.close()

        let base: NSColor = isBlack ? NSColor(white: 0.12, alpha: 1) : NSColor(white: 0.93, alpha: 1)
        (pressed ? theme.accent : base).setFill()
        path.fill()
        (isBlack ? NSColor(white: 0.04, alpha: 1) : NSColor(white: 0.62, alpha: 1)).setStroke()
        path.lineWidth = 1; path.stroke()

        // Label the C keys with their octave so you can find your place.
        if !isBlack, note % 12 == 0 {
            let name = "C\(note / 12 - 1)"
            let attrs: [NSAttributedString.Key: Any] = [
                .font: Self.octaveFont,
                .foregroundColor: pressed ? theme.onAccent : NSColor(white: 0.45, alpha: 1),
            ]
            let s = NSAttributedString(string: name, attributes: attrs)
            s.draw(at: NSPoint(x: r.midX - s.size().width / 2, y: r.minY + 4))
        }
        // Show the bound QWERTY key near the top of mapped keys.
        if let t = typeLabel {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: Self.typeFont,
                .foregroundColor: pressed ? theme.onAccent : NSColor(white: isBlack ? 0.72 : 0.40, alpha: 1),
            ]
            let s = NSAttributedString(string: t, attributes: attrs)
            s.draw(at: NSPoint(x: r.midX - s.size().width / 2, y: r.maxY - 16))
        }
    }
}

/// A clickable piano keyboard spanning `low…high` (MIDI). Lays out white keys edge-to-edge
/// and overlays black keys on the boundaries, doing its own frame math in `layout()`.
final class ChipKeyboard: NSView {
    var onNote: ((Int) -> Void)?
    private var whiteKeys: [ChipKey] = []
    private var blackKeys: [ChipKey] = []
    private var charToKey: [Character: ChipKey] = [:]   // QWERTY → key
    private var noteToKey: [Int: ChipKey] = [:]
    private static let whiteSemis: Set<Int> = [0, 2, 4, 5, 7, 9, 11]
    /// Computer keys laid across the piano left-to-right (chromatically): the QWERTY row first,
    /// then the home row, then the bottom row — enough to give every key a shortcut.
    static let typingRow = Array("qwertyuiopasdfghjklzxcvbnm")

    init(low: Int, high: Int) {
        super.init(frame: .zero)
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        // White keys first (so the later black keys sit on top and win hit-testing).
        for n in low ... high where Self.whiteSemis.contains(n % 12) { whiteKeys.append(makeKey(n, black: false)) }
        for n in low ... high where !Self.whiteSemis.contains(n % 12) { blackKeys.append(makeKey(n, black: true)) }
        (whiteKeys + blackKeys).forEach(addSubview)
        for k in whiteKeys + blackKeys { noteToKey[k.note] = k }
        // Bind computer keys to every piano key, chromatically from the lowest note up.
        var li = 0
        for n in low ... high {
            guard li < Self.typingRow.count, let key = noteToKey[n] else { continue }
            let ch = Self.typingRow[li]; li += 1
            key.typeLabel = String(ch).uppercased()
            charToKey[ch] = key
        }
    }
    required init?(coder: NSCoder) { fatalError() }

    /// MIDI note bound to a typed character, if any.
    func note(for char: Character) -> Int? { charToKey[char]?.note }
    /// Light/unlight a key by note (used when played from the computer keyboard).
    func setPressed(_ pressed: Bool, note: Int) { noteToKey[note]?.setPressed(pressed) }

    private func makeKey(_ note: Int, black: Bool) -> ChipKey {
        let k = ChipKey(note: note, isBlack: black)
        k.onDown = { [weak self] in self?.onNote?($0) }
        return k
    }

    override func layout() {
        super.layout()
        guard !whiteKeys.isEmpty else { return }
        let ww = bounds.width / CGFloat(whiteKeys.count)
        for (i, k) in whiteKeys.enumerated() {
            k.frame = NSRect(x: CGFloat(i) * ww, y: 0, width: ww, height: bounds.height)
        }
        let bw = ww * 0.62, bh = bounds.height * 0.62
        for k in blackKeys {
            // The black key sits on the boundary just right of the natural a semitone below it.
            guard let idx = whiteKeys.firstIndex(where: { $0.note == k.note - 1 }) else { continue }
            let boundary = CGFloat(idx + 1) * ww
            k.frame = NSRect(x: boundary - bw / 2, y: bounds.height - bh, width: bw, height: bh)
        }
    }
}

// MARK: - Rotary knob (pitch)

final class ChipKnob: NSView {
    var value: Double { didSet { needsDisplay = true; onChange?(value) } }
    private let range: ClosedRange<Double>
    var onChange: ((Double) -> Void)?
    private var lastY: CGFloat = 0
    /// Set without firing onChange (used by the Reset button).
    func setValueSilently(_ v: Double) {
        let old = onChange; onChange = nil
        value = min(max(v, range.lowerBound), range.upperBound)
        onChange = old
    }
    private func nudge(_ delta: Double) {
        value = min(max(value + delta * (range.upperBound - range.lowerBound), range.lowerBound), range.upperBound)
    }

    init(value: Double, in range: ClosedRange<Double>) {
        self.range = range
        self.value = min(max(value, range.lowerBound), range.upperBound)
        super.init(frame: .zero)
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: 40).isActive = true
        heightAnchor.constraint(equalToConstant: 40).isActive = true
    }
    required init?(coder: NSCoder) { fatalError() }

    override func mouseDown(with event: NSEvent) { lastY = event.locationInWindow.y }
    override func mouseDragged(with event: NSEvent) {
        // Vertical OR horizontal drag, whichever moved more — and ~70 px = full sweep,
        // so it's quick to turn with a mouse.
        let dy = event.locationInWindow.y - lastY
        lastY = event.locationInWindow.y
        nudge(Double(dy) / 70)
    }
    override func scrollWheel(with event: NSEvent) {
        nudge(Double(event.scrollingDeltaY) * (event.hasPreciseScrollingDeltas ? 0.004 : 0.04))
    }

    override func draw(_ dirtyRect: NSRect) {
        let c = bounds.insetBy(dx: 5, dy: 5)
        let dial = NSBezierPath(ovalIn: c)
        theme.surfaceInset.setFill(); dial.fill()
        theme.controlEdge.setStroke(); dial.lineWidth = 1.5; dial.stroke()
        // indicator sweeps the bottom-gapped 270° arc real knobs use:
        // min at 7:30 (lower-left), straight up at mid, max at 4:30 (lower-right).
        let t = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
        let ang = (225 - t * 270) * .pi / 180
        let cx = bounds.midX, cy = bounds.midY, rad = c.width / 2
        let p = NSBezierPath()
        p.move(to: NSPoint(x: cx, y: cy))
        p.line(to: NSPoint(x: cx + cos(ang) * rad, y: cy + sin(ang) * rad))
        theme.accent.setStroke(); p.lineWidth = 2.5; p.stroke()
    }
}

// MARK: - Top handle (pull the drawer down)

/// The full-width "T3d Tunes" bar that sits along the bottom of the library — always
/// visible so the instrument is discoverable, and the thing you click to open/close the
/// drawer. Music note + name + a chevron (up to open, down to close). Themed.
final class ChiptunesBar: FocusableControl {
    var onToggle: (() -> Void)?
    override var focusRingCornerRadius: CGFloat { 0 }
    override func activate() { onToggle?() }

    var isExpanded = false {
        didSet {
            updateChevron()
            setAccessibilityLabel(isExpanded ? "Hide T3d Tunes" : "Show T3d Tunes")
            toolTip = accessibilityLabel()
        }
    }

    private let note = NSImageView()
    private let title = NSTextField(labelWithString: "T3d Tunes")
    private let chevron = CAShapeLayer()
    private let topLine = CALayer()
    private var hovered = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.addSublayer(topLine)

        let cfg = NSImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
        note.image = NSImage(systemSymbolName: "music.note", accessibilityDescription: nil)?
            .withSymbolConfiguration(cfg)
        note.image?.isTemplate = true
        note.imageScaling = .scaleProportionallyUpOrDown
        note.setAccessibilityElement(false)
        addSubview(note)

        title.font = theme.skinned ? .rounded(12, .medium) : .systemFont(ofSize: 12, weight: .semibold)
        title.setAccessibilityElement(false)
        title.alignment = .center
        addSubview(title)

        chevron.fillColor = NSColor.clear.cgColor
        chevron.lineWidth = 2; chevron.lineCap = .round; chevron.lineJoin = .round
        layer?.addSublayer(chevron)

        toolTip = "Show T3d Tunes"
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel("Show T3d Tunes")
        refreshColors()
    }
    required init?(coder: NSCoder) { fatalError() }

    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(convert(point, from: superview)) ? self : nil
    }

    override func layout() {
        super.layout()
        title.sizeToFit()
        let tw = title.frame.width, icon: CGFloat = 14, gap: CGFloat = 6
        let groupW = icon + gap + tw
        let startX = (bounds.width - groupW) / 2
        note.frame = CGRect(x: startX, y: (bounds.height - icon) / 2, width: icon, height: icon)
        title.frame = CGRect(x: startX + icon + gap, y: (bounds.height - title.frame.height) / 2,
                             width: tw, height: title.frame.height)
        CATransaction.begin(); CATransaction.setDisableActions(true)
        topLine.frame = CGRect(x: 0, y: bounds.maxY - 1, width: bounds.width, height: 1)
        updateChevron()
        CATransaction.commit()
        refreshColors()
    }

    private func updateChevron() {
        let cx = bounds.maxX - 24, cy = bounds.midY
        let w: CGFloat = 5, h: CGFloat = 4
        let path = CGMutablePath()
        if isExpanded { // open → chevron points down (collapse)
            path.move(to: CGPoint(x: cx - w, y: cy - h / 2))
            path.addLine(to: CGPoint(x: cx, y: cy + h / 2))
            path.addLine(to: CGPoint(x: cx + w, y: cy - h / 2))
        } else {        // closed → chevron points up (expand)
            path.move(to: CGPoint(x: cx - w, y: cy + h / 2))
            path.addLine(to: CGPoint(x: cx, y: cy - h / 2))
            path.addLine(to: CGPoint(x: cx + w, y: cy + h / 2))
        }
        chevron.path = path
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self, userInfo: nil))
    }
    override func mouseEntered(with event: NSEvent) { hovered = true; refreshColors() }
    override func mouseExited(with event: NSEvent) { hovered = false; refreshColors() }
    override func mouseUp(with event: NSEvent) {
        if bounds.contains(convert(event.locationInWindow, from: nil)) { onToggle?() }
    }
    override func accessibilityPerformPress() -> Bool { onToggle?(); return true }

    private func refreshColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = (hovered ? theme.surfaceInset : theme.surfaceFooter).cgColor
            topLine.backgroundColor = theme.lineHair.cgColor
            let ink = hovered ? theme.textPrimary : theme.textSecondary
            chevron.strokeColor = ink.cgColor
            note.contentTintColor = ink
            title.textColor = ink
        }
    }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); refreshColors() }
}

// MARK: - The drawer

final class ChiptunesDrawer: NSView {
    let engine = ChiptuneEngine()
    /// The selected ROM. While the drawer is open, changing it kills the current sound and
    /// auto-samples the new game's sounds (debounced), so browsing the library feels live.
    var selectedROM: URL? {
        didSet {
            guard selectedROM != oldValue else { return }
            if active {
                // Kill any lingering audition drone, but keep a running loop grooving — its
                // sounds swap to the new game's as soon as the sample lands.
                if !engine.isPlaying { engine.panic() }
                autoSample(selectedROM, debounce: true)
            } else {
                updateStatus()
            }
        }
    }

    /// Height of the always-visible "T3d Tunes" bar at the bottom of the library.
    static let barHeight: CGFloat = 30
    /// Click on the bar → the library opens/closes the drawer.
    var onToggle: (() -> Void)?
    func setExpanded(_ open: Bool) { bar.isExpanded = open }

    private var active = false // drawer open / audio running
    private let harvestQueue = DispatchQueue(label: "t3dboy.harvest")
    private var harvestGen = 0
    private var pendingHarvest: DispatchWorkItem?

    private let bar = ChiptunesBar()
    private var laneSteps: [[ChipStep]] = []        // [lane][step]
    private var laneMenus: [NSPopUpButton] = []      // per-lane sound picker
    private var laneVoicePatches: [[ChiptunePatch]] = [] // patches offered in each lane's menu
    private let keyboard = ChipKeyboard(low: 48, high: 72)   // C3…C5 (every key gets a QWERTY shortcut)
    private let kbMenu = NSPopUpButton(frame: .zero, pullsDown: false) // which library sound the keys play
    private var kbPatches: [ChiptunePatch] = []
    private var kbPatch: ChiptunePatch?
    private let kbFXToggle = SettingToggle()                 // play the keyboard through the FX knobs
    private var kbUseFX = false
    private let playButton = CapsuleButton(title: "▶  Play Sequencer", style: .prominent)
    private let bpmLabel = NSTextField(labelWithString: "120 BPM")
    private let status = NSTextField(labelWithString: "")
    private var laneGlides: [SettingToggle?] = []   // per-lane glide (nil for the noise lane — no pitch)
    private var glideColumns: [NSView] = []          // per-lane glide cell, used to align the column header
    private var fxKnobs: [(knob: ChipKnob, def: Double)] = [] // for the Reset button
    private var pitchKnobs: [(knob: ChipKnob, def: Double)] = [] // per-lane pitch, also restored by Reset
    private var keyMonitor: Any?                             // QWERTY → keyboard, while the drawer is open

    // Advanced feature panels (built by their own files; the drawer just mounts them).
    private var featurePanels: [NSView] = []
    private var panelTabs: NSSegmentedControl?
    private weak var contentScroll: NSScrollView?
    private let liveScope = LiveScope()   // persistent oscilloscope, right of the feature panels

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        layer?.masksToBounds = true // clip cleanly when collapsed to 0 height
        build()
        engine.onStep = { [weak self] step in self?.highlight(step) }
        // Pattern data changed by a panel (mutate / euclidean / auto-compose / morph) → redraw grid.
        engine.onPatternChanged = { [weak self] in self?.refreshSteps() }
        // Palette changed (ROM mashup) → refresh the lane menus + keyboard list.
        engine.onPaletteChanged = { [weak self] in
            guard let self else { return }
            self.loadKeyboardSounds(self.engine.palette)
            self.populateMenus(self.engine.palette)
        }
        loadKeyboardSounds(ChiptunePatch.builtIns)
        populateMenus(ChiptunePatch.builtIns)
    }
    required init?(coder: NSCoder) { fatalError() }

    @objc private func panelTabChanged(_ sender: NSSegmentedControl) {
        for (i, p) in featurePanels.enumerated() { p.isHidden = (i != sender.selectedSegment) }
    }

    // MARK: Build

    private func build() {
        layer?.backgroundColor = theme.surfacePanel.cgColor

        // --- Full-width "T3d Tunes" bar (always visible; opens/closes the drawer) ---
        bar.translatesAutoresizingMaskIntoConstraints = false
        bar.onToggle = { [weak self] in self?.onToggle?() }
        addSubview(bar)
        NSLayoutConstraint.activate([
            bar.topAnchor.constraint(equalTo: topAnchor),
            bar.leadingAnchor.constraint(equalTo: leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: trailingAnchor),
            bar.heightAnchor.constraint(equalToConstant: Self.barHeight),
        ])

        // The looper content can be taller than the window on small displays (the feature
        // panels add a lot), so host it in a vertical scroll view below the bar.
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scroll)
        contentScroll = scroll
        let doc = FlippedView()   // flipped so content lays out top-down and scrolling starts at the top
        doc.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = doc
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: bar.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
            doc.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            doc.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            doc.trailingAnchor.constraint(equalTo: scroll.contentView.trailingAnchor),
            doc.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
        ])

        // --- Transport row ---
        playButton.onClick = { [weak self] in self?.togglePlay() }
        let minus = CapsuleButton(title: "–", style: .neutral, fontSize: 14, height: 28)
        let plus = CapsuleButton(title: "+", style: .neutral, fontSize: 14, height: 28)
        minus.onClick = { [weak self] in self?.nudgeBPM(-5) }
        plus.onClick = { [weak self] in self?.nudgeBPM(5) }
        bpmLabel.font = theme.fontMonoSmall
        bpmLabel.textColor = theme.textSecondary
        bpmLabel.alignment = .center
        // No "Sample ROM" button — selecting a game in the library samples it automatically.
        let clear = CapsuleButton(title: "Clear", style: .neutral, fontSize: 12, height: 28)
        clear.onClick = { [weak self] in self?.clearAll() }

        // Synth FX + groove controls, right of Clear. (Glide lives per-lane, in the grid.)
        let dice = ChipIconButton(symbols: ["die.face.5.fill", "die.face.5", "dice.fill", "dice"],
                                  label: "Randomise pattern")
        dice.onClick = { [weak self] in self?.engine.randomize(); self?.refreshSteps() }
        let reset = ChipIconButton(symbols: ["arrow.counterclockwise"], label: "Reset FX & knobs")
        reset.onClick = { [weak self] in self?.resetFX() }

        let fx = NSStackView(views: [
            fxKnob("Cutoff", initial: 1) { [weak self] in self?.engine.setCutoff($0) },
            fxKnob("Res",    initial: 0) { [weak self] in self?.engine.setResonance($0) },
            fxKnob("Drive",  initial: 0) { [weak self] in self?.engine.setDrive($0) },
            fxKnob("Delay",  initial: 0) { [weak self] in self?.engine.setDelayMix($0) },
            fxKnob("Reverb", initial: 0) { [weak self] in self?.engine.setReverbMix($0) },
            fxKnob("Swing",  initial: 0) { [weak self] in self?.engine.swing = $0 * 0.6 },
            reset,
            dice,
        ])
        fx.orientation = .horizontal
        fx.alignment = .centerY
        fx.spacing = 8

        let transport = NSStackView(views: [playButton, spacer(14), minus, bpmLabel, plus,
                                            spacer(16), clear, spacer(14), fx])
        transport.orientation = .horizontal
        transport.alignment = .centerY
        transport.spacing = 6
        transport.translatesAutoresizingMaskIntoConstraints = false

        // --- Lane grid ---
        let grid = NSStackView()
        grid.orientation = .vertical
        grid.alignment = .leading
        grid.spacing = 6
        grid.translatesAutoresizingMaskIntoConstraints = false
        grid.setHuggingPriority(.defaultLow, for: .horizontal)
        for (i, voice) in ChipVoice.allCases.enumerated() {
            grid.addArrangedSubview(laneRow(lane: i, voice: voice))
        }

        // --- Keyboard (a playable soundboard) ---
        let kbCaption = NSTextField(labelWithString: theme.cased("Keyboard"))
        kbCaption.font = theme.fontMonoSmall
        kbCaption.textColor = theme.textSecondary
        kbCaption.setAccessibilityElement(false)

        kbMenu.translatesAutoresizingMaskIntoConstraints = false
        kbMenu.controlSize = .small
        kbMenu.font = theme.fontCaption
        kbMenu.target = self
        kbMenu.action = #selector(kbMenuChanged(_:))
        kbMenu.setAccessibilityLabel("Keyboard sound")
        kbMenu.widthAnchor.constraint(equalToConstant: 170).isActive = true

        kbFXToggle.setAccessibilityName("Use FX. Play the keyboard through the Cutoff, Resonance, Drive, Delay and Reverb knobs")
        kbFXToggle.isOn = kbUseFX
        kbFXToggle.onToggle = { [weak self] on in self?.kbUseFX = on }

        keyboard.translatesAutoresizingMaskIntoConstraints = false
        keyboard.onNote = { [weak self] note in
            guard let self else { return }
            // If a loop track is armed (Perform tab), the keyboard records into it, quantised
            // to the playhead; otherwise it plays the selected keyboard sound.
            if self.engine.armedLane != nil {
                self.engine.liveRecord(note)
            } else if let patch = self.kbPatch {
                self.engine.playKey(patch, note: note, throughFX: self.kbUseFX)
            }
        }

        let kbControls = NSStackView(views: [kbCaption, kbMenu, spacer(20),
                                             labeledControl(kbFXToggle, "Use FX")])
        kbControls.orientation = .horizontal
        kbControls.alignment = .centerY
        kbControls.spacing = 8
        kbControls.translatesAutoresizingMaskIntoConstraints = false

        // --- Advanced feature panels (each built in its own file; the drawer mounts them) ---
        let onChange: () -> Void = { [weak self] in self?.refreshSteps() }
        let panels: [(String, NSView)] = [
            ("Rhythm",  RhythmPanel(engine: engine, onChange: onChange)),
            ("Timbre",  TimbrePanel(engine: engine, onChange: onChange)),
            ("Perform", PerformancePanel(engine: engine, onChange: onChange)),
            ("Visual",  OutputPanel(engine: engine, onChange: onChange)),
            ("ROM",     ROMToolsPanel(engine: engine, onChange: onChange)),
        ]
        featurePanels = panels.map { $0.1 }
        let tabs = NSSegmentedControl(labels: panels.map { $0.0 }, trackingMode: .selectOne,
                                      target: self, action: #selector(panelTabChanged(_:)))
        tabs.selectedSegment = 0
        tabs.translatesAutoresizingMaskIntoConstraints = false
        panelTabs = tabs
        let host = NSView()
        host.translatesAutoresizingMaskIntoConstraints = false
        for (i, p) in panels.enumerated() {
            p.1.translatesAutoresizingMaskIntoConstraints = false
            p.1.isHidden = (i != 0)
            host.addSubview(p.1)
            NSLayoutConstraint.activate([
                p.1.topAnchor.constraint(equalTo: host.topAnchor),
                p.1.bottomAnchor.constraint(equalTo: host.bottomAnchor),
                p.1.leadingAnchor.constraint(equalTo: host.leadingAnchor),
                p.1.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            ])
        }

        status.font = theme.fontCaption
        status.textColor = theme.textFaint
        status.translatesAutoresizingMaskIntoConstraints = false

        // Persistent oscilloscope on the right ~30% of the feature-panel row, with its caption
        // sitting in the tab row.
        liveScope.engine = engine
        liveScope.translatesAutoresizingMaskIntoConstraints = false
        let scopeCaption = NSTextField(labelWithString: theme.cased("Scope"))
        scopeCaption.font = theme.fontMonoSmall
        scopeCaption.textColor = theme.textSecondary
        scopeCaption.alignment = .center
        scopeCaption.setAccessibilityElement(false)
        scopeCaption.translatesAutoresizingMaskIntoConstraints = false

        for v in [transport, grid, kbControls, keyboard, tabs, host, liveScope, scopeCaption, status] { doc.addSubview(v) }
        NSLayoutConstraint.activate([
            transport.topAnchor.constraint(equalTo: doc.topAnchor, constant: 14),
            transport.leadingAnchor.constraint(equalTo: doc.leadingAnchor, constant: 18),

            grid.topAnchor.constraint(equalTo: transport.bottomAnchor, constant: 14),
            grid.leadingAnchor.constraint(equalTo: doc.leadingAnchor, constant: 18),
            grid.trailingAnchor.constraint(equalTo: doc.trailingAnchor, constant: -18),

            // Right column: scope spans the panel-host height; its caption sits over the tab row.
            // Fixed width (not a proportion) so the panels' intrinsic size can't feed back and
            // blow up the window.
            liveScope.trailingAnchor.constraint(equalTo: doc.trailingAnchor, constant: -18),
            liveScope.widthAnchor.constraint(equalToConstant: 300),
            liveScope.topAnchor.constraint(equalTo: host.topAnchor),
            liveScope.bottomAnchor.constraint(equalTo: host.bottomAnchor),
            scopeCaption.centerXAnchor.constraint(equalTo: liveScope.centerXAnchor),
            scopeCaption.centerYAnchor.constraint(equalTo: tabs.centerYAnchor),

            kbControls.topAnchor.constraint(equalTo: grid.bottomAnchor, constant: 14),
            kbControls.leadingAnchor.constraint(equalTo: doc.leadingAnchor, constant: 18),

            keyboard.topAnchor.constraint(equalTo: kbControls.bottomAnchor, constant: 8),
            keyboard.leadingAnchor.constraint(equalTo: doc.leadingAnchor, constant: 18),
            keyboard.trailingAnchor.constraint(equalTo: doc.trailingAnchor, constant: -18),
            keyboard.heightAnchor.constraint(equalToConstant: 58),

            tabs.topAnchor.constraint(equalTo: keyboard.bottomAnchor, constant: 12),
            tabs.leadingAnchor.constraint(equalTo: doc.leadingAnchor, constant: 18),

            host.topAnchor.constraint(equalTo: tabs.bottomAnchor, constant: 10),
            host.leadingAnchor.constraint(equalTo: doc.leadingAnchor, constant: 18),
            host.trailingAnchor.constraint(equalTo: liveScope.leadingAnchor, constant: -14),
            host.heightAnchor.constraint(equalToConstant: 210),

            status.topAnchor.constraint(equalTo: host.bottomAnchor, constant: 8),
            status.leadingAnchor.constraint(equalTo: doc.leadingAnchor, constant: 18),
            status.bottomAnchor.constraint(equalTo: doc.bottomAnchor, constant: -10),
        ])

        // "Pitch" label over the per-lane knob column (the knobs at each lane's right edge).
        let pitchHeader = NSTextField(labelWithString: theme.cased("Pitch"))
        pitchHeader.font = .monospacedSystemFont(ofSize: 8, weight: .medium)
        pitchHeader.textColor = theme.textMuted
        pitchHeader.translatesAutoresizingMaskIntoConstraints = false
        pitchHeader.setAccessibilityElement(false)
        doc.addSubview(pitchHeader)
        NSLayoutConstraint.activate([
            pitchHeader.centerXAnchor.constraint(equalTo: doc.trailingAnchor, constant: -37),
            pitchHeader.bottomAnchor.constraint(equalTo: grid.topAnchor, constant: -1),
        ])

        // "Glide" label over the per-lane glide-switch column.
        if let glideCol = glideColumns.first {
            let glideHeader = NSTextField(labelWithString: theme.cased("Glide"))
            glideHeader.font = .monospacedSystemFont(ofSize: 8, weight: .medium)
            glideHeader.textColor = theme.textMuted
            glideHeader.translatesAutoresizingMaskIntoConstraints = false
            glideHeader.setAccessibilityElement(false)
            doc.addSubview(glideHeader)
            NSLayoutConstraint.activate([
                glideHeader.centerXAnchor.constraint(equalTo: glideCol.centerXAnchor),
                glideHeader.bottomAnchor.constraint(equalTo: grid.topAnchor, constant: -1),
            ])
        }

        refreshSteps()
        updateStatus()
    }

    private func spacer(_ w: CGFloat) -> NSView {
        let v = NSView(); v.translatesAutoresizingMaskIntoConstraints = false
        v.widthAnchor.constraint(equalToConstant: w).isActive = true
        return v
    }

    /// A control with a tiny synth-style label beneath it.
    private func labeledControl(_ control: NSView, _ title: String) -> NSView {
        let cap = NSTextField(labelWithString: theme.cased(title))
        cap.font = .monospacedSystemFont(ofSize: 8, weight: .medium)
        cap.textColor = theme.textMuted
        cap.alignment = .center
        cap.setAccessibilityElement(false)
        let v = NSStackView(views: [control, cap])
        v.orientation = .vertical
        v.alignment = .centerX
        v.spacing = 2
        return v
    }

    private func labeledKnob(_ title: String, initial: Double, _ onChange: @escaping (Double) -> Void) -> NSView {
        let knob = ChipKnob(value: initial, in: 0 ... 1)
        knob.onChange = onChange
        knob.setAccessibilityLabel(title)
        return labeledControl(knob, title)
    }

    /// An FX knob that's also registered so the Reset button can restore its default.
    private func fxKnob(_ title: String, initial: Double, _ onChange: @escaping (Double) -> Void) -> NSView {
        let knob = ChipKnob(value: initial, in: 0 ... 1)
        knob.onChange = onChange
        knob.setAccessibilityLabel(title)
        fxKnobs.append((knob, initial))
        return labeledControl(knob, title)
    }

    /// Reset every FX/groove knob and per-lane pitch to default, turn all lane Glides off,
    /// and flush any FX tails.
    private func resetFX() {
        for (knob, def) in fxKnobs { knob.value = def }    // fires onChange → engine FX setters
        for (knob, def) in pitchKnobs { knob.value = def } // fires onChange → engine.setRoot
        for case let toggle? in laneGlides { toggle.isOn = false }
        engine.glideEnabled = [Bool](repeating: false, count: 4)
        engine.panic()
    }

    private func laneRow(lane: Int, voice: ChipVoice) -> NSView {
        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false

        let mute = ChipMute(); mute.onToggle = { [weak self] on in self?.engine.setMuted(on, lane: lane) }
        let label = NSTextField(labelWithString: theme.cased(voice.short))
        label.font = theme.fontMonoSmall
        label.textColor = voiceColor(voice)

        // Sound picker: choose which of the ROM's captured sounds (for this channel) the
        // lane plays. Repopulated whenever a ROM is sampled.
        let menu = NSPopUpButton(frame: .zero, pullsDown: false)
        menu.translatesAutoresizingMaskIntoConstraints = false
        menu.controlSize = .small
        menu.font = theme.fontCaption
        menu.target = self
        menu.action = #selector(laneMenuChanged(_:))
        menu.tag = lane
        laneMenus.append(menu)
        laneVoicePatches.append([engine.patch(lane: lane)])
        menu.addItem(withTitle: engine.patch(lane: lane).name)

        let head = NSStackView(views: [mute, label])
        head.spacing = 6; head.alignment = .centerY
        head.translatesAutoresizingMaskIntoConstraints = false

        // 16 step cells, equal width, stretching with the window
        let cellStack = NSStackView()
        cellStack.orientation = .horizontal
        cellStack.distribution = .fillEqually
        cellStack.spacing = 3
        cellStack.translatesAutoresizingMaskIntoConstraints = false
        var cells: [ChipStep] = []
        for s in 0 ..< engine.stepCount {
            let cell = ChipStep()
            cell.tint = voiceColor(voice)
            cell.translatesAutoresizingMaskIntoConstraints = false
            cell.heightAnchor.constraint(equalToConstant: 24).isActive = true
            cell.onToggle = { [weak self] in self?.engine.toggleStep(lane: lane, step: s); self?.refreshSteps() }
            // every 4th step a touch brighter happens via playhead; group gap via spacing
            cells.append(cell)
            cellStack.addArrangedSubview(cell)
        }
        laneSteps.append(cells)

        // Per-lane Glide (portamento). The noise lane has no pitch, so it gets a same-width
        // blank cell to keep the step columns aligned across lanes.
        let glideCell = NSView()
        glideCell.translatesAutoresizingMaskIntoConstraints = false
        if voice != .noise {
            let toggle = SettingToggle()
            toggle.setAccessibilityName("\(voice.short) Glide. Slide pitch between consecutive notes on this lane")
            toggle.onToggle = { [weak self] on in self?.engine.glideEnabled[lane] = on }
            toggle.translatesAutoresizingMaskIntoConstraints = false
            glideCell.addSubview(toggle)
            NSLayoutConstraint.activate([
                toggle.centerXAnchor.constraint(equalTo: glideCell.centerXAnchor),
                toggle.centerYAnchor.constraint(equalTo: glideCell.centerYAnchor),
            ])
            laneGlides.append(toggle)
        } else {
            laneGlides.append(nil)
        }
        glideColumns.append(glideCell)

        let knob = ChipKnob(value: Double(engine.root(lane: lane)), in: 24 ... 84)
        knob.onChange = { [weak self] v in self?.engine.setRoot(Int(v.rounded()), lane: lane) }
        pitchKnobs.append((knob, Double(engine.root(lane: lane)))) // default root, for Reset

        for v in [head, menu, glideCell, cellStack, knob] {
            v.translatesAutoresizingMaskIntoConstraints = false
            row.addSubview(v)
        }
        NSLayoutConstraint.activate([
            row.heightAnchor.constraint(equalToConstant: 30),
            head.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            head.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            head.widthAnchor.constraint(equalToConstant: 70),

            menu.leadingAnchor.constraint(equalTo: head.trailingAnchor, constant: 8),
            menu.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            menu.widthAnchor.constraint(equalToConstant: 120),

            glideCell.leadingAnchor.constraint(equalTo: menu.trailingAnchor, constant: 8),
            glideCell.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            glideCell.widthAnchor.constraint(equalToConstant: 38),
            glideCell.heightAnchor.constraint(equalToConstant: 24),

            cellStack.leadingAnchor.constraint(equalTo: glideCell.trailingAnchor, constant: 10),
            cellStack.trailingAnchor.constraint(equalTo: knob.leadingAnchor, constant: -12),
            cellStack.centerYAnchor.constraint(equalTo: row.centerYAnchor),

            knob.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            knob.centerYAnchor.constraint(equalTo: row.centerYAnchor),
        ])
        // Make the row stretch to the grid width.
        row.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return row
    }

    // MARK: Keyboard

    /// Fill the keyboard's sound picker with the whole sampled library (every channel's sounds).
    private func loadKeyboardSounds(_ patches: [ChiptunePatch]) {
        kbPatches = patches.isEmpty ? ChiptunePatch.builtIns : patches
        engine.palette = kbPatches   // keep the engine's palette (locks/shuffle/auto-compose) in sync
        kbMenu.removeAllItems()
        kbMenu.addItems(withTitles: kbPatches.map { theme.cased("\($0.name) · \($0.voice.short)") })
        kbMenu.selectItem(at: 0)
        kbPatch = kbPatches.first
    }

    @objc private func kbMenuChanged(_ sender: NSPopUpButton) {
        guard kbPatches.indices.contains(sender.indexOfSelectedItem) else { return }
        kbPatch = kbPatches[sender.indexOfSelectedItem]
        if let p = kbPatch { engine.playKey(p, note: 60, throughFX: kbUseFX) } // preview at middle C
    }

    // MARK: Computer keyboard → notes (QWERTYUIOP)

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            // NB: optional-chaining flattens, so don't write `self?.handleTypedKey(event) ?? event`
            // — that would coalesce an intentional consume (nil) back into the event and beep.
            guard let self else { return event }
            return self.handleTypedKey(event)
        }
    }
    private func removeKeyMonitor() {
        if let m = keyMonitor { NSEvent.removeMonitor(m); keyMonitor = nil }
    }

    /// Returns nil to consume the event (a mapped key), or the event to pass it through.
    private func handleTypedKey(_ event: NSEvent) -> NSEvent? {
        guard active, let win = window, event.window === win else { return event }
        // Don't hijack typing in a text field, and let any shortcut (⌘/⌃/⌥) through.
        if win.firstResponder is NSText { return event }
        if !event.modifierFlags.intersection([.command, .control, .option]).isEmpty { return event }
        guard let ch = event.charactersIgnoringModifiers?.lowercased().first,
              let note = keyboard.note(for: ch) else { return event }
        switch event.type {
        case .keyDown:
            if !event.isARepeat, let patch = kbPatch {
                engine.playKey(patch, note: note, throughFX: kbUseFX)
                keyboard.setPressed(true, note: note)
            }
            return nil
        case .keyUp:
            keyboard.setPressed(false, note: note)
            return nil
        default:
            return event
        }
    }

    /// Populate each lane's dropdown with the captured sounds for that channel.
    private func populateMenus(_ palette: [ChiptunePatch]) {
        for voice in ChipVoice.allCases {
            let lane = voice.rawValue
            let patches = palette.filter { $0.voice == voice }
            let list = patches.isEmpty ? [ChiptunePatch.defaults(for: voice)] : patches
            laneVoicePatches[lane] = list
            let menu = laneMenus[lane]
            menu.removeAllItems()
            menu.addItems(withTitles: list.map { theme.cased($0.name) })
            menu.selectItem(at: 0)
            engine.setPatch(list[0], lane: lane)
        }
    }

    @objc private func laneMenuChanged(_ sender: NSPopUpButton) {
        let lane = sender.tag
        guard laneVoicePatches.indices.contains(lane),
              laneVoicePatches[lane].indices.contains(sender.indexOfSelectedItem) else { return }
        let patch = laneVoicePatches[lane][sender.indexOfSelectedItem]
        engine.setPatch(patch, lane: lane)
        engine.startAudioIfNeeded()
        engine.audition(patch, note: engine.root(lane: lane)) // preview the choice
    }

    // MARK: Transport / actions

    private func togglePlay() {
        engine.togglePlay()
        playButton.title = engine.isPlaying ? "■  Stop Sequencer" : "▶  Play Sequencer"
        if !engine.isPlaying { highlight(-1) }
    }

    private func nudgeBPM(_ d: Int) {
        engine.bpm = max(40, min(240, engine.bpm + d))
        bpmLabel.stringValue = "\(engine.bpm) BPM"
    }

    private func refreshSteps() {
        for (lane, cells) in laneSteps.enumerated() {
            for (s, cell) in cells.enumerated() { cell.on = engine.isStepOn(lane: lane, step: s) }
        }
    }

    private func highlight(_ step: Int) {
        for cells in laneSteps {
            for (s, cell) in cells.enumerated() { cell.playing = (s == step) }
        }
    }

    /// Open the drawer: start the chip and load the current game's sounds straight away.
    func activate(rom: URL?) {
        active = true
        engine.startAudioIfNeeded()
        installKeyMonitor()
        liveScope.start()
        // Start the drawer scrolled at the top (transport row visible).
        DispatchQueue.main.async { [weak self] in self?.contentScroll?.contentView.scroll(to: .zero) }
        selectedROM = rom               // (active is true, so this kicks off a sample)
        autoSample(rom, debounce: false) // also sample immediately on open
    }

    /// Close the drawer: stop everything and cancel any pending sample.
    func suspend() {
        active = false
        liveScope.stop()
        removeKeyMonitor()
        pendingHarvest?.cancel(); pendingHarvest = nil
        harvestGen += 1 // invalidate any in-flight result
        if engine.isPlaying { togglePlay() }
        engine.shutdown()
    }

    private func clearAll() {
        if engine.isPlaying { togglePlay() } // stop the loop
        engine.clear()
        engine.panic()                        // silence any ringing notes
        refreshSteps()
        highlight(-1)
    }

    /// Screenshot mode: load made-up sounds and a pre-filled beat so the looper looks alive.
    private func loadDemoTunes() {
        loadKeyboardSounds(DemoMode.tuneSounds)
        populateMenus(DemoMode.tuneSounds)
        engine.clear()
        for (lane, steps) in DemoMode.tunePattern.enumerated() where lane < engine.lanes.count {
            for s in steps { engine.toggleStep(lane: lane, step: s) }
        }
        refreshSteps()
        status.stringValue = theme.cased("\(DemoMode.tuneSounds.count) sounds sampled from Super T3d Boy")
    }

    /// Sample the ROM's sounds. `debounce` waits briefly (so arrow-key browsing only
    /// samples the game you land on); the Sample button samples now.
    private func autoSample(_ rom: URL?, debounce: Bool) {
        pendingHarvest?.cancel()
        if DemoMode.isActive { loadDemoTunes(); return } // screenshot mode: fake sounds + beat
        guard active, let rom else { updateStatus(); return }
        harvestGen += 1
        let gen = harvestGen
        status.stringValue = theme.cased("Sampling \(rom.deletingPathExtension().lastPathComponent)…")
        let work = DispatchWorkItem { [weak self] in
            let sounds = SoundHarvester.harvest(rom: rom)
            DispatchQueue.main.async { self?.applyHarvest(sounds, rom: rom, gen: gen) }
        }
        pendingHarvest = work
        harvestQueue.asyncAfter(deadline: .now() + (debounce ? 0.35 : 0.0), execute: work)
    }

    private func applyHarvest(_ harvested: [ChiptunePatch], rom: URL, gen: Int) {
        guard gen == harvestGen, active, rom == selectedROM else { return } // stale / superseded
        let palette = harvested.isEmpty ? ChiptunePatch.builtIns : harvested
        loadKeyboardSounds(palette)
        populateMenus(palette) // fill each lane's dropdown with that channel's sounds + seed it
        status.stringValue = harvested.isEmpty
            ? theme.cased("No sounds found — using built-ins")
            : theme.cased("\(harvested.count) sounds sampled from \(rom.deletingPathExtension().lastPathComponent)")
    }

    private func updateStatus() {
        if let rom = selectedROM {
            status.stringValue = theme.cased("Tap Sample ROM to load sounds from \(rom.deletingPathExtension().lastPathComponent)")
        } else {
            status.stringValue = theme.cased("Select a game, then Sample ROM — or play the built-in sounds")
        }
    }

}

// MARK: - Tiny mute toggle

final class ChipMute: NSView {
    var on = false { didSet { needsDisplay = true } }
    var onToggle: ((Bool) -> Void)?
    override init(frame: NSRect) { super.init(frame: NSRect(x: 0, y: 0, width: 16, height: 16)); wantsLayer = true }
    required init?(coder: NSCoder) { fatalError() }
    override var intrinsicContentSize: NSSize { NSSize(width: 16, height: 16) }
    override func mouseDown(with event: NSEvent) { on.toggle(); onToggle?(on) }
    override func draw(_ dirtyRect: NSRect) {
        let p = NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 2), xRadius: 3, yRadius: 3)
        (on ? theme.textFaint : theme.keyGreen).withAlphaComponent(on ? 0.4 : 1).setFill()
        p.fill()
    }
}

// MARK: - Compact icon button (monotone SF Symbol, neutral capsule look)

final class ChipIconButton: NSView {
    var onClick: (() -> Void)?
    private let icon = NSImageView()
    private var hovered = false { didSet { needsDisplay = true; refreshTint() } }

    init(symbols: [String], label: String) {
        super.init(frame: .zero)
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        layer?.cornerRadius = theme.radiusMedium
        let cfg = NSImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
        let img = symbols.lazy.compactMap {
            NSImage(systemSymbolName: $0, accessibilityDescription: label)
        }.first?.withSymbolConfiguration(cfg)
        icon.image = img
        icon.image?.isTemplate = true // monotone, like the trophy
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.setAccessibilityElement(false)
        icon.translatesAutoresizingMaskIntoConstraints = false
        addSubview(icon)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 38),
            heightAnchor.constraint(equalToConstant: 28),
            icon.centerXAnchor.constraint(equalTo: centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 16),
            icon.heightAnchor.constraint(equalToConstant: 16),
        ])
        toolTip = label
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(label)
        refreshTint()
    }
    required init?(coder: NSCoder) { fatalError() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow],
                                       owner: self, userInfo: nil))
    }
    override func mouseEntered(with event: NSEvent) { hovered = true }
    override func mouseExited(with event: NSEvent) { hovered = false }
    override func mouseUp(with event: NSEvent) {
        if bounds.contains(convert(event.locationInWindow, from: nil)) { onClick?() }
    }
    override func accessibilityPerformPress() -> Bool { onClick?(); return true }

    private func refreshTint() { icon.contentTintColor = hovered ? theme.textPrimary : theme.textSecondary }

    override func draw(_ dirtyRect: NSRect) {
        // Neutral ghost capsule, matching CapsuleButton(.neutral).
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5),
                                xRadius: theme.radiusMedium, yRadius: theme.radiusMedium)
        if theme.skinned {
            theme.textPrimary.withAlphaComponent(hovered ? 0.06 : 0).setFill(); path.fill()
            theme.controlEdge.setStroke()
        } else {
            NSColor.labelColor.withAlphaComponent(hovered ? 0.13 : 0.08).setFill(); path.fill()
            NSColor.clear.setStroke()
        }
        path.lineWidth = 1; path.stroke()
    }
}
