// T3d Boy — T3d Tunes "Perform" panel: a live loop station.
//
// Modelled on multi-channel loopers (à la Ed Sheeran's rig): the four Game Boy lanes are four
// loop tracks sharing one clock (the sequencer). Arm a track (REC) and play the keyboard in
// time — notes land on the grid quantised to the playhead — then bring tracks in and out with
// MUTE and redo them with CLEAR. A master tap tempo, a stutter (beat-repeat) pad and the
// sidechain pump round out the live-performance controls.

import Cocoa

// MARK: - Loop-station button (own-drawn so it can light up / pulse)

private final class LoopButton: NSView {
    var onClick: (() -> Void)?
    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?
    var title: String { didSet { needsDisplay = true } }
    var tint: NSColor
    var active = false { didSet { needsDisplay = true } }
    var dimmed = false { didSet { needsDisplay = true } }
    var glow: CGFloat = 0 { didSet { needsDisplay = true } }   // 0…1 pulse when armed
    private static let font = NSFont.monospacedSystemFont(ofSize: 10, weight: .semibold)

    init(title: String, tint: NSColor) {
        self.title = title; self.tint = tint
        super.init(frame: .zero)
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
    }
    required init?(coder: NSCoder) { fatalError() }

    override func mouseDown(with event: NSEvent) {
        if onRelease != nil { onPress?() } else { onClick?() }
    }
    override func mouseUp(with event: NSEvent) { onRelease?() }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 6, yRadius: 6)
        let fill: NSColor = active ? (tint.blended(withFraction: glow * 0.45, of: .white) ?? tint)
                                   : theme.surfaceInset
        fill.setFill(); path.fill()
        (active ? tint : theme.controlEdge).setStroke()
        path.lineWidth = 1; path.stroke()
        let fg = active ? theme.onAccent : (dimmed ? theme.textMuted : theme.textSecondary)
        let s = NSAttributedString(string: title, attributes: [.font: Self.font, .foregroundColor: fg])
        let sz = s.size()
        s.draw(at: NSPoint(x: bounds.midX - sz.width / 2, y: bounds.midY - sz.height / 2))
    }
}

// MARK: - Perform panel

final class PerformancePanel: NSView {
    private let engine: ChiptuneEngine
    private let onChange: () -> Void

    private var recButtons: [LoopButton] = []
    private var muteButtons: [LoopButton] = []
    private var soundLabels: [NSTextField] = []
    private let bpmLabel = NSTextField(labelWithString: "120 BPM")

    private var tapTimes: [Double] = []
    private var stutterTimer: Timer?
    private var refreshTimer: Timer?
    private var glowPhase: CGFloat = 0
    private var stutterSubdiv = 4   // hits per beat: 2 = 1/8, 4 = 1/16, 8 = 1/32
    private let stutterRateLabel = NSTextField(labelWithString: "1/16")

    init(engine: ChiptuneEngine, onChange: @escaping () -> Void) {
        self.engine = engine
        self.onChange = onChange
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        build()
        startRefresh()
    }
    required init?(coder: NSCoder) { fatalError() }
    deinit { stutterTimer?.invalidate(); refreshTimer?.invalidate() }

    private func caption(_ t: String, _ color: NSColor? = nil) -> NSTextField {
        let l = NSTextField(labelWithString: theme.cased(t))
        l.font = .monospacedSystemFont(ofSize: 8, weight: .medium)
        l.textColor = color ?? theme.textMuted
        l.setAccessibilityElement(false)
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }

    private func build() {
        // --- Header: how-to hint + tap tempo ---
        let hint = caption("Live loop — press Play, arm a track (REC), play it in, then layer up")
        bpmLabel.font = theme.fontMonoSmall
        bpmLabel.textColor = theme.textSecondary
        bpmLabel.stringValue = "\(engine.bpm) BPM"
        bpmLabel.translatesAutoresizingMaskIntoConstraints = false
        let tap = LoopButton(title: "TAP", tint: theme.accent)
        tap.onClick = { [weak self] in self?.tapTempo() }
        size(tap, 60, 24)
        let header = row([hint, flexSpacer(), tap, bpmLabel], spacing: 8)

        // --- Four loop tracks ---
        var trackRows: [NSView] = []
        for lane in 0 ..< 4 {
            let voice = ChipVoice(rawValue: lane)!
            let dot = NSView(); dot.wantsLayer = true; dot.layer?.cornerRadius = 5
            dot.layer?.backgroundColor = voiceColor(voice).cgColor
            dot.translatesAutoresizingMaskIntoConstraints = false
            size(dot, 10, 10)

            let name = NSTextField(labelWithString: voice.short)
            name.font = theme.fontMonoSmall; name.textColor = voiceColor(voice)
            name.translatesAutoresizingMaskIntoConstraints = false

            let sound = NSTextField(labelWithString: engine.patch(lane: lane).name)
            sound.font = theme.fontCaption; sound.textColor = theme.textMuted
            sound.lineBreakMode = .byTruncatingTail
            sound.translatesAutoresizingMaskIntoConstraints = false
            sound.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            soundLabels.append(sound)

            let rec = LoopButton(title: "REC", tint: .systemRed)
            rec.onClick = { [weak self] in self?.toggleArm(lane) }
            size(rec, 62, 26)
            rec.setAccessibilityLabel("\(voice.short) record arm")
            recButtons.append(rec)

            let mute = LoopButton(title: "MUTE", tint: theme.warm)
            mute.onClick = { [weak self] in self?.toggleMute(lane) }
            size(mute, 62, 26)
            mute.setAccessibilityLabel("\(voice.short) mute")
            muteButtons.append(mute)

            let clear = LoopButton(title: "CLEAR", tint: theme.textPrimary)
            clear.onClick = { [weak self] in self?.clear(lane) }
            size(clear, 58, 26)

            let head = row([dot, name], spacing: 6)
            size(head, 58, 26)
            let r = row([head, sound, flexSpacer(), rec, mute, clear], spacing: 8)
            size(r, nil, 28)
            trackRows.append(r)
        }

        // --- Performance FX: stutter pad + pump ---
        let stutter = LoopButton(title: "STUTTER", tint: theme.accent)
        stutter.onPress = { [weak self] in self?.startStutter() }
        stutter.onRelease = { [weak self] in self?.stopStutter() }
        size(stutter, 96, 28)
        let rateStepper = NSStepper()
        rateStepper.minValue = 0; rateStepper.maxValue = 2; rateStepper.increment = 1; rateStepper.integerValue = 1
        rateStepper.valueWraps = false; rateStepper.target = self; rateStepper.action = #selector(stutterRateChanged(_:))
        rateStepper.translatesAutoresizingMaskIntoConstraints = false
        stutterRateLabel.font = theme.fontMonoSmall; stutterRateLabel.textColor = theme.textSecondary
        stutterRateLabel.translatesAutoresizingMaskIntoConstraints = false

        let pumpSlider = NSSlider(value: engine.pumpDepth, minValue: 0, maxValue: 1,
                                  target: self, action: #selector(pumpChanged(_:)))
        pumpSlider.controlSize = .small
        pumpSlider.translatesAutoresizingMaskIntoConstraints = false
        size(pumpSlider, 130, 18)
        let pumpStepper = NSStepper()
        pumpStepper.minValue = 0; pumpStepper.maxValue = 3; pumpStepper.increment = 1; pumpStepper.integerValue = 1
        pumpStepper.target = self; pumpStepper.action = #selector(pumpDivChanged(_:))
        pumpStepper.translatesAutoresizingMaskIntoConstraints = false

        let fx = row([stutter, caption("Rate"), stutterRateLabel, rateStepper, flexSpacer(),
                      caption("Pump"), pumpSlider, pumpStepper], spacing: 8)
        size(fx, nil, 30)

        let rows = [header] + trackRows + [fx]
        let stack = NSStackView(views: rows)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 5
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
        ])
        for v in rows {   // stretch each row to the full width
            v.leadingAnchor.constraint(equalTo: stack.leadingAnchor).isActive = true
            v.trailingAnchor.constraint(equalTo: stack.trailingAnchor).isActive = true
        }
        updateStates()
    }

    // MARK: Layout helpers

    private func row(_ views: [NSView], spacing: CGFloat) -> NSStackView {
        let s = NSStackView(views: views)
        s.orientation = .horizontal; s.alignment = .centerY; s.spacing = spacing
        s.translatesAutoresizingMaskIntoConstraints = false
        return s
    }
    private func flexSpacer() -> NSView {
        let v = NSView(); v.translatesAutoresizingMaskIntoConstraints = false
        v.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return v
    }
    private func size(_ v: NSView, _ w: CGFloat?, _ h: CGFloat?) {
        if let w { v.widthAnchor.constraint(equalToConstant: w).isActive = true }
        if let h { v.heightAnchor.constraint(equalToConstant: h).isActive = true }
    }

    // MARK: Track actions

    private func toggleArm(_ lane: Int) {
        engine.armedLane = (engine.armedLane == lane) ? nil : lane
        updateStates()
    }
    private func toggleMute(_ lane: Int) {
        engine.setMuted(!engine.isMuted(lane: lane), lane: lane)
        updateStates()
    }
    private func clear(_ lane: Int) {
        engine.clearLane(lane)
        onChange()
        updateStates()
    }

    private func updateStates() {
        for lane in 0 ..< recButtons.count {
            recButtons[lane].active = (engine.armedLane == lane)
            let muted = engine.isMuted(lane: lane)
            muteButtons[lane].active = muted
            muteButtons[lane].title = muted ? "MUTED" : "MUTE"
            muteButtons[lane].dimmed = !engine.hasContent(lane: lane)
            soundLabels[lane].stringValue = engine.patch(lane: lane).name
        }
    }

    // MARK: Tap tempo

    private func tapTempo() {
        let now = ProcessInfo.processInfo.systemUptime
        if let last = tapTimes.last, now - last > 2.0 { tapTimes.removeAll() } // start a new count
        tapTimes.append(now)
        if tapTimes.count > 5 { tapTimes.removeFirst(tapTimes.count - 5) }
        guard tapTimes.count >= 2 else { return }
        let intervals = zip(tapTimes.dropFirst(), tapTimes).map { $0 - $1 }
        let avg = intervals.reduce(0, +) / Double(intervals.count)
        guard avg > 0.2, avg < 2.0 else { return }
        engine.bpm = max(40, min(240, Int((60.0 / avg).rounded())))
        bpmLabel.stringValue = "\(engine.bpm) BPM"
    }

    // MARK: Stutter (beat-repeat)

    private func startStutter() {
        stutterTimer?.invalidate()
        let interval = 60.0 / Double(max(40, engine.bpm)) / Double(stutterSubdiv)
        engine.triggerColumn(max(0, engine.currentStep))   // fire immediately
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.engine.triggerColumn(max(0, self.engine.currentStep))
        }
        RunLoop.main.add(t, forMode: .common)
        stutterTimer = t
    }
    private func stopStutter() { stutterTimer?.invalidate(); stutterTimer = nil }

    @objc private func stutterRateChanged(_ s: NSStepper) {
        let map = [2, 4, 8], names = ["1/8", "1/16", "1/32"]
        let i = max(0, min(2, s.integerValue))
        stutterSubdiv = map[i]; stutterRateLabel.stringValue = names[i]
    }

    // MARK: Pump

    @objc private func pumpChanged(_ s: NSSlider) { engine.pumpDepth = s.doubleValue }
    @objc private func pumpDivChanged(_ s: NSStepper) {
        engine.pumpDivision = [1, 2, 4, 8][max(0, min(3, s.integerValue))]
    }

    // MARK: Live refresh (armed-track pulse + state sync)

    private func startRefresh() {
        let t = Timer(timeInterval: 1.0 / 12.0, repeats: true) { [weak self] _ in
            guard let self, self.window != nil, !self.isHidden else { return }
            self.glowPhase += 0.5
            let g = (sin(self.glowPhase) + 1) / 2
            for (lane, rec) in self.recButtons.enumerated() where self.engine.armedLane == lane {
                rec.glow = g
            }
            self.bpmLabel.stringValue = "\(self.engine.bpm) BPM"
        }
        RunLoop.main.add(t, forMode: .common)
        refreshTimer = t
    }
}
