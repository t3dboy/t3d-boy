// T3d Boy — T3d Tunes: the Performance panel.
//
// A single horizontal band of live-performance controls grouped under tiny synth-style
// captions: scene store/recall + a Morph knob, tap tempo, a momentary Stutter (beat-repeat)
// pad, a Pump (fake sidechain) knob + division, and per-lane Solo toggles. Everything reads
// the active theme tokens so it re-skins with the rest of the drawer.

import Cocoa

final class PerformancePanel: NSView {
    private let engine: ChiptuneEngine
    private let onChange: () -> Void

    // Scenes
    private let storeA = CapsuleButton(title: "Store A", style: .neutral, fontSize: 11, height: 24)
    private let storeB = CapsuleButton(title: "Store B", style: .neutral, fontSize: 11, height: 24)

    // Tap tempo
    private var tapTimes: [Double] = []
    private let bpmReadout = NSTextField(labelWithString: "")

    // Stutter (beat-repeat)
    private var stutterTimer: Timer?
    private var stutterRate = 1   // 0 = 1/8, 1 = 1/16, 2 = 1/32 (index into stutterDivs)
    private let stutterDivs = [8.0, 16.0, 32.0]

    init(engine: ChiptuneEngine, onChange: @escaping () -> Void) {
        self.engine = engine
        self.onChange = onChange
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        build()
    }
    required init?(coder: NSCoder) { fatalError() }

    deinit { stutterTimer?.invalidate() }

    // MARK: - Build

    private func build() {
        let groups = NSStackView(views: [
            scenesGroup(),
            divider(),
            tempoGroup(),
            divider(),
            stutterGroup(),
            divider(),
            pumpGroup(),
            divider(),
            soloGroup(),
        ])
        groups.orientation = .horizontal
        groups.alignment = .centerY
        groups.spacing = 14
        groups.translatesAutoresizingMaskIntoConstraints = false
        addSubview(groups)
        NSLayoutConstraint.activate([
            groups.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            groups.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -10),
            groups.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            groups.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -10),
            groups.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        refreshSceneTints()
        updateBpmReadout()
    }

    // MARK: Groups

    private func scenesGroup() -> NSView {
        storeA.onClick = { [weak self] in
            guard let self else { return }
            self.engine.storeScene(false); self.refreshSceneTints(); self.onChange()
        }
        storeB.onClick = { [weak self] in
            guard let self else { return }
            self.engine.storeScene(true); self.refreshSceneTints(); self.onChange()
        }
        let recallA = ChipIconButton(symbols: ["a.square", "a.circle"], label: "Recall Scene A")
        recallA.onClick = { [weak self] in self?.engine.recallScene(false); self?.onChange() }
        let recallB = ChipIconButton(symbols: ["b.square", "b.circle"], label: "Recall Scene B")
        recallB.onClick = { [weak self] in self?.engine.recallScene(true); self?.onChange() }

        let morph = ChipKnob(value: 0, in: 0 ... 1)
        morph.setAccessibilityLabel("Morph")
        morph.onChange = { [weak self] v in self?.engine.morph(v); self?.onChange() }

        let stores = NSStackView(views: [storeA, storeB])
        stores.orientation = .vertical; stores.alignment = .leading; stores.spacing = 4
        let recalls = NSStackView(views: [recallA, recallB])
        recalls.orientation = .vertical; recalls.spacing = 4

        let row = NSStackView(views: [stores, recalls, labeled(morph, "Morph")])
        row.orientation = .horizontal; row.alignment = .centerY; row.spacing = 8
        return captioned(row, "Scenes")
    }

    private func tempoGroup() -> NSView {
        let tap = CapsuleButton(title: "Tap", style: .neutral, fontSize: 12, height: 30)
        tap.onClick = { [weak self] in self?.registerTap() }

        bpmReadout.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        bpmReadout.textColor = theme.textSecondary
        bpmReadout.alignment = .center
        bpmReadout.setAccessibilityElement(false)

        let col = NSStackView(views: [tap, bpmReadout])
        col.orientation = .vertical; col.alignment = .centerX; col.spacing = 3
        return captioned(col, "Tempo")
    }

    private func stutterGroup() -> NSView {
        let pad = HoldPad(title: "Stutter")
        pad.onStart = { [weak self] in self?.startStutter() }
        pad.onStop = { [weak self] in self?.stopStutter() }

        let stepper = NSStepper()
        stepper.minValue = 0
        stepper.maxValue = Double(stutterDivs.count - 1)
        stepper.increment = 1
        stepper.integerValue = stutterRate
        stepper.valueWraps = false
        stepper.controlSize = .small
        stepper.target = self
        stepper.action = #selector(stutterRateChanged(_:))
        stepper.setAccessibilityLabel("Stutter rate")

        let rateCap = NSTextField(labelWithString: rateLabel())
        rateCap.font = .monospacedSystemFont(ofSize: 8, weight: .medium)
        rateCap.textColor = theme.textMuted
        rateCap.alignment = .center
        rateCap.setAccessibilityElement(false)
        stutterRateLabel = rateCap

        let rate = NSStackView(views: [stepper, rateCap])
        rate.orientation = .vertical; rate.alignment = .centerX; rate.spacing = 1

        let row = NSStackView(views: [pad, rate])
        row.orientation = .horizontal; row.alignment = .centerY; row.spacing = 6
        return captioned(row, "Stutter")
    }
    private weak var stutterRateLabel: NSTextField?

    private func pumpGroup() -> NSView {
        let depth = ChipKnob(value: engine.pumpDepth, in: 0 ... 1)
        depth.setAccessibilityLabel("Pump depth")
        depth.onChange = { [weak self] v in self?.engine.pumpDepth = v }

        let divs = [1, 2, 4, 8]
        let stepper = NSStepper()
        stepper.minValue = 0
        stepper.maxValue = Double(divs.count - 1)
        stepper.increment = 1
        stepper.integerValue = divs.firstIndex(of: engine.pumpDivision) ?? 2
        stepper.valueWraps = false
        stepper.controlSize = .small
        stepper.setAccessibilityLabel("Pump division")
        let divLabel = NSTextField(labelWithString: "1/\(engine.pumpDivision)")
        divLabel.font = .monospacedSystemFont(ofSize: 8, weight: .medium)
        divLabel.textColor = theme.textMuted
        divLabel.alignment = .center
        divLabel.setAccessibilityElement(false)
        let onStep: () -> Void = { [weak self, weak stepper, weak divLabel] in
            guard let self, let stepper else { return }
            let d = divs[max(0, min(divs.count - 1, stepper.integerValue))]
            self.engine.pumpDivision = d
            divLabel?.stringValue = "1/\(d)"
        }
        stepperBridge = StepperBridge(action: onStep)
        stepper.target = stepperBridge
        stepper.action = #selector(StepperBridge.fire)

        let div = NSStackView(views: [stepper, divLabel])
        div.orientation = .vertical; div.alignment = .centerX; div.spacing = 1

        let row = NSStackView(views: [labeled(depth, "Depth"), div])
        row.orientation = .horizontal; row.alignment = .centerY; row.spacing = 6
        return captioned(row, "Pump")
    }
    private var stepperBridge: StepperBridge?

    private func soloGroup() -> NSView {
        var cells: [NSView] = []
        for i in 0 ..< 4 {
            let voice = ChipVoice(rawValue: i)!
            let toggle = SettingToggle()
            toggle.isOn = engine.isSolo(lane: i)
            toggle.setAccessibilityName("Solo \(voice.short)")
            toggle.onToggle = { [weak self] on in self?.engine.setSolo(on, lane: i); self?.onChange() }
            cells.append(labeled(toggle, voice.short, tint: voiceColor(voice)))
        }
        let row = NSStackView(views: cells)
        row.orientation = .horizontal; row.alignment = .centerY; row.spacing = 8
        return captioned(row, "Solo")
    }

    // MARK: - Tap tempo

    private func registerTap() {
        let now = ProcessInfo.processInfo.systemUptime
        // Reset the average if it's been too long since the last tap (new tempo intent).
        if let last = tapTimes.last, now - last > 2.0 { tapTimes.removeAll() }
        tapTimes.append(now)
        if tapTimes.count > 5 { tapTimes.removeFirst(tapTimes.count - 5) }
        guard tapTimes.count >= 2 else { updateBpmReadout(); return }
        var intervals: [Double] = []
        for i in 1 ..< tapTimes.count { intervals.append(tapTimes[i] - tapTimes[i - 1]) }
        let avg = intervals.reduce(0, +) / Double(intervals.count)
        guard avg > 0 else { return }
        engine.bpm = max(40, min(240, Int((60.0 / avg).rounded())))
        updateBpmReadout()
        onChange()
    }

    private func updateBpmReadout() {
        bpmReadout.stringValue = theme.cased("\(engine.bpm) BPM")
    }

    // MARK: - Stutter

    @objc private func stutterRateChanged(_ sender: NSStepper) {
        stutterRate = max(0, min(stutterDivs.count - 1, sender.integerValue))
        stutterRateLabel?.stringValue = rateLabel()
        // Retune a running stutter to the new rate.
        if stutterTimer != nil { startStutter() }
    }

    private func rateLabel() -> String { "1/\(Int(stutterDivs[stutterRate]))" }

    private func stutterInterval() -> TimeInterval {
        // A 1/N note = (4/N) quarter-notes; one quarter = 60/bpm seconds.
        let bpm = Double(max(40, engine.bpm))
        return (60.0 / bpm) * (4.0 / stutterDivs[stutterRate])
    }

    private func startStutter() {
        stutterTimer?.invalidate()
        let fire: () -> Void = { [weak self] in
            guard let self else { return }
            self.engine.triggerColumn(max(0, self.engine.currentStep))
        }
        fire() // immediate first hit
        let t = Timer(timeInterval: stutterInterval(), repeats: true) { _ in fire() }
        RunLoop.main.add(t, forMode: .common)
        stutterTimer = t
    }

    private func stopStutter() {
        stutterTimer?.invalidate()
        stutterTimer = nil
    }

    // MARK: - Scenes

    private func refreshSceneTints() {
        styleStore(storeA, on: engine.hasScene(false))
        styleStore(storeB, on: engine.hasScene(true))
    }

    private func styleStore(_ button: CapsuleButton, on: Bool) {
        button.wantsLayer = true
        button.layer?.borderWidth = on ? 1.5 : 0
        button.layer?.borderColor = on ? theme.keyGreen.cgColor : NSColor.clear.cgColor
        button.layer?.cornerRadius = theme.skinned ? theme.radiusMedium : 12
    }

    // MARK: - Layout helpers

    /// A control with a tiny synth-style caption beneath it.
    private func labeled(_ control: NSView, _ title: String, tint: NSColor? = nil) -> NSView {
        let cap = NSTextField(labelWithString: theme.cased(title))
        cap.font = .monospacedSystemFont(ofSize: 8, weight: .medium)
        cap.textColor = tint ?? theme.textMuted
        cap.alignment = .center
        cap.setAccessibilityElement(false)
        let v = NSStackView(views: [control, cap])
        v.orientation = .vertical; v.alignment = .centerX; v.spacing = 2
        return v
    }

    /// A group of controls under a small section caption.
    private func captioned(_ body: NSView, _ title: String) -> NSView {
        let cap = NSTextField(labelWithString: theme.cased(title))
        cap.font = .monospacedSystemFont(ofSize: 8, weight: .medium)
        cap.textColor = theme.textMuted
        cap.setAccessibilityElement(false)
        let v = NSStackView(views: [body, cap])
        v.orientation = .vertical; v.alignment = .centerX; v.spacing = 3
        return v
    }

    private func divider() -> NSView {
        let v = NSView()
        v.wantsLayer = true
        v.layer?.backgroundColor = theme.lineHair.cgColor
        v.translatesAutoresizingMaskIntoConstraints = false
        v.widthAnchor.constraint(equalToConstant: 1).isActive = true
        v.heightAnchor.constraint(equalToConstant: 80).isActive = true
        v.setAccessibilityElement(false)
        return v
    }
}

// MARK: - Hold pad (momentary beat-repeat)
//
// A capsule that fires `onStart` on mouse-down and `onStop` on mouse-up — for the Stutter
// beat-repeat, which must run only while held (CapsuleButton uses click semantics, so we
// roll a minimal hold control matching its neutral look).
private final class HoldPad: NSView {
    var onStart: (() -> Void)?
    var onStop: (() -> Void)?
    private let label = NSTextField(labelWithString: "")
    private var held = false { didSet { needsDisplay = true } }

    init(title: String) {
        super.init(frame: .zero)
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        label.stringValue = theme.cased(title)
        label.font = theme.skinned ? .rounded(12, .medium) : .systemFont(ofSize: 12, weight: .semibold)
        label.alignment = .center
        label.textColor = theme.textSecondary
        label.translatesAutoresizingMaskIntoConstraints = false
        label.setAccessibilityElement(false)
        addSubview(label)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 30),
            widthAnchor.constraint(greaterThanOrEqualToConstant: 64),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
        ])
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(title)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func hitTest(_ point: NSPoint) -> NSView? { frame.contains(point) ? self : nil }

    override func mouseDown(with event: NSEvent) {
        held = true
        onStart?()
    }
    override func mouseUp(with event: NSEvent) {
        guard held else { return }
        held = false
        onStop?()
    }

    // VoiceOver: a press is a single momentary burst.
    override func accessibilityPerformPress() -> Bool {
        onStart?(); onStop?(); return true
    }

    override func layout() {
        super.layout()
        layer?.cornerRadius = theme.skinned ? theme.radiusMedium : bounds.height / 2
    }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5),
                                xRadius: layer?.cornerRadius ?? 8, yRadius: layer?.cornerRadius ?? 8)
        if theme.skinned {
            theme.textPrimary.withAlphaComponent(held ? 0.16 : 0).setFill(); path.fill()
            (held ? theme.keyGreen : theme.controlEdge).setStroke()
        } else {
            NSColor.labelColor.withAlphaComponent(held ? 0.2 : 0.08).setFill(); path.fill()
            NSColor.clear.setStroke()
        }
        path.lineWidth = 1; path.stroke()
        label.textColor = held ? theme.textPrimary : theme.textSecondary
    }
}

// MARK: - Stepper bridge
//
// Routes a target/action NSStepper to a Swift closure (NSStepper needs an @objc target).
private final class StepperBridge: NSObject {
    private let action: () -> Void
    init(action: @escaping () -> Void) { self.action = action; super.init() }
    @objc func fire() { action() }
}
