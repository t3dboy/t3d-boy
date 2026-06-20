// T3d Boy — T3d Tunes "Rhythm" panel: a compact per-lane rhythm / generative editor.
//
// One row per lane (PUL1 / PUL2 / WAVE / NOIS), each exposing the engine's polymeter and
// generative controls: loop Length, step Direction, lane Probability, and a Euclidean fill.
// A "Mutate" button (top-right) evolves the whole pattern. Everything reads the active theme.

import Cocoa

final class RhythmPanel: NSView {
    private let engine: ChiptuneEngine
    private let onChange: () -> Void

    init(engine: ChiptuneEngine, onChange: @escaping () -> Void) {
        self.engine = engine
        self.onChange = onChange
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        build()
    }
    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Tiny synth-style caption

    private func caption(_ t: String) -> NSTextField {
        let c = NSTextField(labelWithString: theme.cased(t))
        c.font = .monospacedSystemFont(ofSize: 9, weight: .medium)
        c.textColor = theme.textMuted
        c.alignment = .center
        c.setAccessibilityElement(false)
        c.translatesAutoresizingMaskIntoConstraints = false
        return c
    }

    // MARK: - Build

    private func build() {
        // 2×2 grid: one card per channel, so each gets a roomy quarter.
        let cards = (0 ..< 4).map { channelCard(lane: $0, voice: ChipVoice(rawValue: $0)!) }
        let top = quarterRow([cards[0], cards[1]])
        let bottom = quarterRow([cards[2], cards[3]])
        let grid = NSStackView(views: [top, bottom])
        grid.orientation = .vertical
        grid.distribution = .fillEqually
        grid.spacing = 10
        grid.translatesAutoresizingMaskIntoConstraints = false
        addSubview(grid)

        // Mutate — evolve the whole pattern — overlaid in the top-right corner (clear of the
        // top-right card's header, which sits on the left).
        let mutate = CapsuleButton(title: "Mutate", style: .neutral, fontSize: 12, height: 26)
        mutate.translatesAutoresizingMaskIntoConstraints = false
        mutate.onClick = { [weak self] in
            guard let self else { return }
            self.engine.mutate()
            self.onChange()
        }
        addSubview(mutate)

        NSLayoutConstraint.activate([
            grid.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            grid.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            grid.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            grid.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),

            mutate.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            mutate.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -22),
            mutate.widthAnchor.constraint(equalToConstant: 100),
        ])
    }

    private func quarterRow(_ cards: [NSView]) -> NSStackView {
        let r = NSStackView(views: cards)
        r.orientation = .horizontal
        r.distribution = .fillEqually
        r.spacing = 12
        return r
    }

    // MARK: - One channel card (a "quarter")

    private func channelCard(lane: Int, voice: ChipVoice) -> NSView {
        let accent = voiceColor(voice)
        let card = NSView()
        card.wantsLayer = true
        card.layer?.cornerRadius = theme.radiusMedium
        card.layer?.backgroundColor = accent.withAlphaComponent(0.07).cgColor
        card.layer?.borderWidth = 1
        card.layer?.borderColor = accent.withAlphaComponent(0.28).cgColor
        card.translatesAutoresizingMaskIntoConstraints = false

        // Header: dot + channel name (bigger than the old thin rows).
        let dot = NSView()
        dot.wantsLayer = true
        dot.layer?.cornerRadius = 5
        dot.layer?.backgroundColor = accent.cgColor
        dot.translatesAutoresizingMaskIntoConstraints = false
        let name = NSTextField(labelWithString: theme.cased(voice.short))
        name.font = theme.skinned ? .rounded(14, .semibold) : .systemFont(ofSize: 14, weight: .bold)
        name.textColor = accent
        name.setAccessibilityElement(false)
        let header = NSStackView(views: [dot, name])
        header.orientation = .horizontal; header.alignment = .centerY; header.spacing = 7
        header.translatesAutoresizingMaskIntoConstraints = false

        // [Len: NSStepper 1…16]
        let lenStepper = NSStepper()
        lenStepper.controlSize = .regular
        lenStepper.minValue = 1; lenStepper.maxValue = 16; lenStepper.increment = 1
        lenStepper.integerValue = engine.length(lane: lane)
        lenStepper.valueWraps = false
        lenStepper.translatesAutoresizingMaskIntoConstraints = false
        lenStepper.setAccessibilityLabel("\(voice.short) length")
        let lenReadout = readout("\(engine.length(lane: lane))")
        lenStepper.onChange = { [weak self] in
            guard let self else { return }
            let n = lenStepper.integerValue
            self.engine.setLength(n, lane: lane)
            lenReadout.stringValue = "\(n)"
            self.onChange()
        }

        // [Dir: NSSegmentedControl of the 4 StepDirection labels]
        let dirSeg = NSSegmentedControl(labels: StepDirection.allCases.map { $0.label },
                                        trackingMode: .selectOne, target: nil, action: nil)
        dirSeg.controlSize = .regular
        dirSeg.segmentDistribution = .fillEqually
        dirSeg.selectedSegment = engine.direction(lane: lane).rawValue
        dirSeg.translatesAutoresizingMaskIntoConstraints = false
        dirSeg.setAccessibilityLabel("\(voice.short) direction")
        dirSeg.onChange = { [weak self] in
            guard let self else { return }
            if let d = StepDirection(rawValue: dirSeg.selectedSegment) {
                self.engine.setDirection(d, lane: lane)
                self.onChange()
            }
        }

        // [Prob: ChipKnob 0…1 → setLaneProbability] — bigger knob.
        let probKnob = ChipKnob(value: 1.0, in: 0 ... 1, diameter: 52)
        probKnob.setAccessibilityLabel("\(voice.short) probability")
        probKnob.onChange = { [weak self] v in
            self?.engine.setLaneProbability(Int((v * 100).rounded()), lane: lane)
            self?.onChange()
        }

        // [Euclid: NSStepper hits 0–16 + Fill button]
        let euclidStepper = NSStepper()
        euclidStepper.controlSize = .regular
        euclidStepper.minValue = 0; euclidStepper.maxValue = 16; euclidStepper.increment = 1
        euclidStepper.integerValue = 4
        euclidStepper.valueWraps = false
        euclidStepper.translatesAutoresizingMaskIntoConstraints = false
        euclidStepper.setAccessibilityLabel("\(voice.short) Euclidean hits")
        let euclidReadout = readout("4")
        euclidStepper.onChange = { euclidReadout.stringValue = "\(euclidStepper.integerValue)" }
        let fill = ChipIconButton(symbols: ["circle.grid.cross", "circle.grid.3x3.fill", "circle.grid.3x3"],
                                  label: "\(voice.short) Euclidean fill")
        fill.onClick = { [weak self] in
            guard let self else { return }
            self.engine.euclidean(lane: lane, hits: euclidStepper.integerValue)
            self.onChange()
        }

        // Captioned control groups, spread across the card.
        let lenGroup = captioned("Len", hRow([lenReadout, lenStepper], 5))
        let dirGroup = captioned("Dir", dirSeg)
        let probGroup = captioned("Prob", probKnob)
        let euclidGroup = captioned("Euclid", hRow([euclidReadout, euclidStepper, fill], 8))
        dirSeg.widthAnchor.constraint(greaterThanOrEqualToConstant: 168).isActive = true

        let controls = NSStackView(views: [lenGroup, dirGroup, probGroup, euclidGroup])
        controls.orientation = .horizontal
        controls.alignment = .centerY
        controls.distribution = .equalSpacing
        controls.translatesAutoresizingMaskIntoConstraints = false

        card.addSubview(header)
        card.addSubview(controls)
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: card.topAnchor, constant: 8),
            header.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
            dot.widthAnchor.constraint(equalToConstant: 10),
            dot.heightAnchor.constraint(equalToConstant: 10),

            controls.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            controls.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            controls.topAnchor.constraint(greaterThanOrEqualTo: header.bottomAnchor, constant: 4),
            controls.centerYAnchor.constraint(equalTo: card.centerYAnchor, constant: 12),
            controls.bottomAnchor.constraint(lessThanOrEqualTo: card.bottomAnchor, constant: -8),
        ])
        return card
    }

    // MARK: - Small builders

    /// A readout label (mono, right-aligned, fixed width so steppers don't jitter the layout).
    private func readout(_ s: String) -> NSTextField {
        let l = NSTextField(labelWithString: s)
        l.font = theme.fontMonoSmall
        l.textColor = theme.textSecondary
        l.alignment = .right
        l.setAccessibilityElement(false)
        l.translatesAutoresizingMaskIntoConstraints = false
        l.widthAnchor.constraint(equalToConstant: 20).isActive = true
        return l
    }

    /// A horizontal control group.
    private func hRow(_ views: [NSView], _ spacing: CGFloat) -> NSStackView {
        let s = NSStackView(views: views)
        s.orientation = .horizontal; s.alignment = .centerY; s.spacing = spacing
        return s
    }

    /// A control with a caption above it.
    private func captioned(_ title: String, _ control: NSView) -> NSView {
        let cap = caption(title)
        let v = NSStackView(views: [cap, control])
        v.orientation = .vertical; v.alignment = .centerX; v.spacing = 5
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }
}

// MARK: - Closure-driven target/action for native AppKit controls

/// Lets `NSStepper` / `NSSegmentedControl` fire a Swift closure (matches the closure-based
/// `onChange` / `onClick` style used by the custom controls in this drawer).
private final class ClosureTarget: NSObject {
    let action: () -> Void
    init(_ action: @escaping () -> Void) { self.action = action }
    @objc func fire(_ sender: Any?) { action() }
}

private var closureTargetKey: UInt8 = 0

private extension NSControl {
    /// A closure called whenever the control's value changes. Retains the closure via the
    /// control's target (stored as an associated object so it lives as long as the control).
    var onChange: (() -> Void)? {
        get { (objc_getAssociatedObject(self, &closureTargetKey) as? ClosureTarget)?.action }
        set {
            guard let newValue else {
                objc_setAssociatedObject(self, &closureTargetKey, nil, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
                target = nil; action = nil
                return
            }
            let t = ClosureTarget(newValue)
            objc_setAssociatedObject(self, &closureTargetKey, t, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            target = t
            action = #selector(ClosureTarget.fire(_:))
        }
    }
}
