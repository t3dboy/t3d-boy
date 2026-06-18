// T3d Boy — T3d Tunes drawer: a boutique-synth-style looping soundboard.
//
// Slides out of the top of the library (growing the window taller). Four lanes — the GB's
// four channels — each a 16-step loop you lay sounds into. A pad bank holds the sounds
// harvested from the selected ROM (or built-ins); tap a pad to load it into its lane and
// hear it. Knobs set per-lane pitch. Transport runs the loop. Everything reads the active
// theme's tokens, so it re-skins as Classic / Pistachio / Engineer / Liquid Glass.

import Cocoa

// MARK: - Voice palette (themed)

private func voiceColor(_ v: ChipVoice) -> NSColor {
    switch v {
    case .pulse1: return theme.keyCoral
    case .pulse2: return theme.keyBlue
    case .wave:   return theme.keyGreen
    case .noise:  return theme.keyYellow
    }
}

// MARK: - LED step cell

final class ChipStep: NSView {
    var on = false { didSet { needsDisplay = true } }
    var playing = false { didSet { needsDisplay = true } }
    var tint: NSColor = .systemBlue
    var onToggle: (() -> Void)?

    override init(frame: NSRect) { super.init(frame: frame); wantsLayer = true }
    required init?(coder: NSCoder) { fatalError() }
    override func mouseDown(with event: NSEvent) { onToggle?() }

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

// MARK: - Pad (a harvested/built-in sound)

final class ChipPad: NSView {
    let patch: ChiptunePatch
    var selected = false { didSet { needsDisplay = true } }
    var onTap: (() -> Void)?
    private var hot = false

    init(patch: ChiptunePatch) {
        self.patch = patch
        super.init(frame: .zero)
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: 84).isActive = true
        heightAnchor.constraint(equalToConstant: 46).isActive = true
    }
    required init?(coder: NSCoder) { fatalError() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow],
                                       owner: self, userInfo: nil))
    }
    override func mouseEntered(with event: NSEvent) { hot = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hot = false; needsDisplay = true }
    override func mouseDown(with event: NSEvent) { onTap?() }

    override func draw(_ dirtyRect: NSRect) {
        let c = voiceColor(patch.voice)
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1),
                                xRadius: theme.radiusSmall, yRadius: theme.radiusSmall)
        (selected ? c : c.withAlphaComponent(hot ? 0.34 : 0.20)).setFill()
        path.fill()
        c.withAlphaComponent(selected ? 1 : 0.5).setStroke()
        path.lineWidth = selected ? 2 : 1; path.stroke()

        let name = theme.cased(patch.name)
        let color = selected ? theme.onAccent : theme.textPrimary
        let attrs: [NSAttributedString.Key: Any] = [
            .font: theme.fontCaption, .foregroundColor: color,
        ]
        let s = NSAttributedString(string: name, attributes: attrs)
        s.draw(at: NSPoint(x: 8, y: bounds.height / 2 - 7))
    }
}

// MARK: - Rotary knob (pitch)

final class ChipKnob: NSView {
    var value: Double { didSet { needsDisplay = true; onChange?(value) } }
    private let range: ClosedRange<Double>
    var onChange: ((Double) -> Void)?
    private var lastY: CGFloat = 0

    init(value: Double, in range: ClosedRange<Double>) {
        self.range = range
        self.value = min(max(value, range.lowerBound), range.upperBound)
        super.init(frame: .zero)
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: 38).isActive = true
        heightAnchor.constraint(equalToConstant: 38).isActive = true
    }
    required init?(coder: NSCoder) { fatalError() }

    override func mouseDown(with event: NSEvent) { lastY = event.locationInWindow.y }
    override func mouseDragged(with event: NSEvent) {
        let dy = event.locationInWindow.y - lastY
        lastY = event.locationInWindow.y
        let span = range.upperBound - range.lowerBound
        value = min(max(value + Double(dy) / 120 * span, range.lowerBound), range.upperBound)
    }

    override func draw(_ dirtyRect: NSRect) {
        let c = bounds.insetBy(dx: 5, dy: 5)
        let dial = NSBezierPath(ovalIn: c)
        theme.surfaceInset.setFill(); dial.fill()
        theme.controlEdge.setStroke(); dial.lineWidth = 1.5; dial.stroke()
        // indicator: -135° … +135° sweep
        let t = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
        let ang = (135 - t * 270) * .pi / 180
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
        if isExpanded { // ▾ close
            path.move(to: CGPoint(x: cx - w, y: cy + h / 2))
            path.addLine(to: CGPoint(x: cx, y: cy - h / 2))
            path.addLine(to: CGPoint(x: cx + w, y: cy + h / 2))
        } else {        // ▴ open
            path.move(to: CGPoint(x: cx - w, y: cy - h / 2))
            path.addLine(to: CGPoint(x: cx, y: cy + h / 2))
            path.addLine(to: CGPoint(x: cx + w, y: cy - h / 2))
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
    private let padStack = NSStackView()
    private var pads: [ChipPad] = []
    private let playButton = CapsuleButton(title: "▶  Play", style: .prominent)
    private let bpmLabel = NSTextField(labelWithString: "120 BPM")
    private let status = NSTextField(labelWithString: "")

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        layer?.masksToBounds = true // clip cleanly when collapsed to 0 height
        build()
        engine.onStep = { [weak self] step in self?.highlight(step) }
        loadPads(ChiptunePatch.builtIns)
        populateMenus(ChiptunePatch.builtIns)
    }
    required init?(coder: NSCoder) { fatalError() }

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

        let transport = NSStackView(views: [playButton, spacer(14), minus, bpmLabel, plus,
                                            spacer(20), clear])
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

        // --- Pad bank ---
        padStack.orientation = .horizontal
        padStack.alignment = .centerY
        padStack.spacing = 6
        let padScroll = NSScrollView()
        padScroll.drawsBackground = false
        padScroll.hasHorizontalScroller = true
        padScroll.borderType = .noBorder
        padScroll.documentView = padStack
        padScroll.translatesAutoresizingMaskIntoConstraints = false
        padStack.translatesAutoresizingMaskIntoConstraints = false

        status.font = theme.fontCaption
        status.textColor = theme.textFaint
        status.translatesAutoresizingMaskIntoConstraints = false

        for v in [transport, grid, padScroll, status] { addSubview(v) }
        NSLayoutConstraint.activate([
            transport.topAnchor.constraint(equalTo: bar.bottomAnchor, constant: 14),
            transport.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),

            grid.topAnchor.constraint(equalTo: transport.bottomAnchor, constant: 14),
            grid.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            grid.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18),

            padScroll.topAnchor.constraint(equalTo: grid.bottomAnchor, constant: 12),
            padScroll.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            padScroll.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18),
            padScroll.heightAnchor.constraint(equalToConstant: 50),

            padStack.heightAnchor.constraint(equalTo: padScroll.heightAnchor),

            status.topAnchor.constraint(equalTo: padScroll.bottomAnchor, constant: 6),
            status.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
        ])
        refreshSteps()
        updateStatus()
    }

    private func spacer(_ w: CGFloat) -> NSView {
        let v = NSView(); v.translatesAutoresizingMaskIntoConstraints = false
        v.widthAnchor.constraint(equalToConstant: w).isActive = true
        return v
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

        let knob = ChipKnob(value: Double(engine.root(lane: lane)), in: 24 ... 84)
        knob.onChange = { [weak self] v in self?.engine.setRoot(Int(v.rounded()), lane: lane) }

        for v in [head, menu, cellStack, knob] {
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

            cellStack.leadingAnchor.constraint(equalTo: menu.trailingAnchor, constant: 10),
            cellStack.trailingAnchor.constraint(equalTo: knob.leadingAnchor, constant: -12),
            cellStack.centerYAnchor.constraint(equalTo: row.centerYAnchor),

            knob.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            knob.centerYAnchor.constraint(equalTo: row.centerYAnchor),
        ])
        // Make the row stretch to the grid width.
        row.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return row
    }

    // MARK: Pads

    private func loadPads(_ patches: [ChiptunePatch]) {
        pads.forEach { $0.removeFromSuperview() }
        pads.removeAll()
        for p in patches {
            let pad = ChipPad(patch: p)
            pad.onTap = { [weak self] in self?.tapPad(p, view: pad) }
            pads.append(pad)
            padStack.addArrangedSubview(pad)
        }
    }

    private func tapPad(_ patch: ChiptunePatch, view: ChipPad) {
        // The pad bank is a live soundboard — tap to play a sound now (lane instruments are
        // chosen with the per-channel dropdowns).
        engine.startAudioIfNeeded()
        engine.audition(patch, note: engine.root(lane: patch.voice.rawValue))
        for p in pads { p.selected = (p === view) }
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
        playButton.title = engine.isPlaying ? "■  Stop" : "▶  Play"
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
        selectedROM = rom               // (active is true, so this kicks off a sample)
        autoSample(rom, debounce: false) // also sample immediately on open
    }

    /// Close the drawer: stop everything and cancel any pending sample.
    func suspend() {
        active = false
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
        loadPads(DemoMode.tuneSounds)
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
        loadPads(palette)
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
