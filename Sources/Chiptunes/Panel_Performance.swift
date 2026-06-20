// T3d Boy — T3d Tunes "Perform" panel: the global live-performance controls.
//
// Live looping itself is now per-track, right on the sequencer rows: each lane's REC button
// banks its pattern into a loop, clears the grid so you can layer another part on top, and the
// loop keeps playing. This panel holds the controls that apply across the whole performance —
// a tap-tempo, a stutter (beat-repeat) pad, the sidechain pump, and a one-press clear that
// wipes every banked loop at once.

import Cocoa

// MARK: - Performance button (own-drawn so it can light up / pulse)

private final class LoopButton: NSView {
    var onClick: (() -> Void)?
    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?
    var title: String { didSet { needsDisplay = true } }
    var tint: NSColor
    var active = false { didSet { needsDisplay = true } }
    var dimmed = false { didSet { needsDisplay = true } }
    var glow: CGFloat = 0 { didSet { needsDisplay = true } }   // 0…1 pulse when active
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

    private let bpmLabel = NSTextField(labelWithString: "120 BPM")

    private var tapTimes: [Double] = []
    private var stutterTimer: Timer?
    private var refreshTimer: Timer?
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
        // --- Header: tap tempo + BPM read-out ---
        let title = caption("PERFORM", theme.textSecondary)
        bpmLabel.font = theme.fontMonoSmall
        bpmLabel.textColor = theme.textSecondary
        bpmLabel.stringValue = "\(engine.bpm) BPM"
        bpmLabel.translatesAutoresizingMaskIntoConstraints = false
        let tap = LoopButton(title: "TAP", tint: theme.accent)
        tap.onClick = { [weak self] in self?.tapTempo() }
        size(tap, 60, 26)
        let header = row([title, flexSpacer(), tap, bpmLabel], spacing: 8)
        size(header, nil, 28)

        // --- How live looping works (it lives on the sequencer rows now) ---
        let how1 = caption("Live loop on the rows: press Play, build a pattern, then hit a row's REC")
        let how2 = caption("to bank it — the grid clears, the loop keeps playing. Layer up and REC again.")

        // --- Stutter (beat-repeat) pad + rate ---
        let stutter = LoopButton(title: "STUTTER", tint: theme.accent)
        stutter.onPress = { [weak self] in self?.startStutter() }
        stutter.onRelease = { [weak self] in self?.stopStutter() }
        size(stutter, 120, 34)
        let rateStepper = NSStepper()
        rateStepper.minValue = 0; rateStepper.maxValue = 2; rateStepper.increment = 1; rateStepper.integerValue = 1
        rateStepper.valueWraps = false; rateStepper.target = self; rateStepper.action = #selector(stutterRateChanged(_:))
        rateStepper.translatesAutoresizingMaskIntoConstraints = false
        stutterRateLabel.font = theme.fontMonoSmall; stutterRateLabel.textColor = theme.textSecondary
        stutterRateLabel.translatesAutoresizingMaskIntoConstraints = false
        let stutterGroup = labeledGroup("Stutter", row([stutter, caption("Rate"), stutterRateLabel, rateStepper], spacing: 8))

        // --- Sidechain pump ---
        let pumpSlider = NSSlider(value: engine.pumpDepth, minValue: 0, maxValue: 1,
                                  target: self, action: #selector(pumpChanged(_:)))
        pumpSlider.controlSize = .small
        pumpSlider.translatesAutoresizingMaskIntoConstraints = false
        size(pumpSlider, 170, 18)
        let pumpStepper = NSStepper()
        pumpStepper.minValue = 0; pumpStepper.maxValue = 3; pumpStepper.increment = 1; pumpStepper.integerValue = 1
        pumpStepper.target = self; pumpStepper.action = #selector(pumpDivChanged(_:))
        pumpStepper.translatesAutoresizingMaskIntoConstraints = false
        let pumpGroup = labeledGroup("Pump", row([pumpSlider, pumpStepper], spacing: 8))

        // --- Clear every banked loop in one press (the grid is untouched) ---
        let clearLoops = LoopButton(title: "CLEAR ALL LOOPS", tint: theme.warm)
        clearLoops.onClick = { [weak self] in self?.clearAllLoops() }
        size(clearLoops, 180, 34)
        let clearGroup = labeledGroup("Loops", clearLoops)

        // The three control groups spread evenly across the full width.
        let controls = NSStackView(views: [stutterGroup, pumpGroup, clearGroup])
        controls.orientation = .horizontal
        controls.alignment = .top
        controls.distribution = .equalSpacing
        controls.translatesAutoresizingMaskIntoConstraints = false

        let rows = [header, how1, how2, controls]
        let stack = NSStackView(views: rows)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 14),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 40),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -40),
        ])
        for v in [header, controls] {   // stretch the header + controls row to full width
            v.leadingAnchor.constraint(equalTo: stack.leadingAnchor).isActive = true
            v.trailingAnchor.constraint(equalTo: stack.trailingAnchor).isActive = true
        }
    }

    /// A control group with a tiny caption above it (for the spread-out Perform controls).
    private func labeledGroup(_ title: String, _ content: NSView) -> NSView {
        let cap = caption(title)
        let v = NSStackView(views: [cap, content])
        v.orientation = .vertical
        v.alignment = .leading
        v.spacing = 6
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
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

    // MARK: Actions

    private func clearAllLoops() {
        for lane in 0 ..< engine.lanes.count { engine.clearLoop(lane) }
        onChange()
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

    // MARK: Live refresh (keep the BPM read-out in sync with tap/elsewhere)

    private func startRefresh() {
        let t = Timer(timeInterval: 1.0 / 8.0, repeats: true) { [weak self] _ in
            guard let self, self.window != nil, !self.isHidden else { return }
            self.bpmLabel.stringValue = "\(self.engine.bpm) BPM"
        }
        RunLoop.main.add(t, forMode: .common)
        refreshTimer = t
    }
}
