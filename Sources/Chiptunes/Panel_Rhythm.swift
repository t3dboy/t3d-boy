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
        c.font = .monospacedSystemFont(ofSize: 8, weight: .medium)
        c.textColor = theme.textMuted
        c.alignment = .center
        c.setAccessibilityElement(false)
        c.translatesAutoresizingMaskIntoConstraints = false
        return c
    }

    // MARK: - Build

    private func build() {
        // Column header row of tiny captions, aligned over the lane columns.
        let hLen = caption("Len"), hDir = caption("Dir"), hProb = caption("Prob"), hEuclid = caption("Euclid")

        // Mutate — evolve the whole pattern (top-right).
        let mutate = CapsuleButton(title: "Mutate", style: .neutral, fontSize: 11, height: 24)
        mutate.translatesAutoresizingMaskIntoConstraints = false
        mutate.onClick = { [weak self] in
            guard let self else { return }
            self.engine.mutate()
            self.onChange()
        }

        addSubview(mutate)
        for v in [hLen, hDir, hProb, hEuclid] { addSubview(v) }

        // Four lane rows.
        var rows: [NSView] = []
        for i in 0 ..< 4 {
            let voice = ChipVoice(rawValue: i)!
            let row = makeLaneRow(lane: i, voice: voice)
            addSubview(row)
            rows.append(row)
        }

        // --- Column x-anchors (shared by header captions + each row) ---
        // Layout (left→right): [tag 70] [Len 56] [Dir 110] [Prob 44] [Euclid ~120]
        let inset: CGFloat = 10

        NSLayoutConstraint.activate([
            mutate.topAnchor.constraint(equalTo: topAnchor, constant: inset),
            mutate.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -inset),
            mutate.widthAnchor.constraint(equalToConstant: 78),
        ])

        // Header captions sit on a single row above lane 0.
        let firstRow = rows[0]
        NSLayoutConstraint.activate([
            hLen.bottomAnchor.constraint(equalTo: firstRow.topAnchor, constant: -1),
            hLen.centerXAnchor.constraint(equalTo: leadingAnchor, constant: inset + Col.tagW + Col.lenW / 2),

            hDir.bottomAnchor.constraint(equalTo: firstRow.topAnchor, constant: -1),
            hDir.centerXAnchor.constraint(equalTo: leadingAnchor, constant: inset + Col.tagW + Col.lenW + Col.dirW / 2),

            hProb.bottomAnchor.constraint(equalTo: firstRow.topAnchor, constant: -1),
            hProb.centerXAnchor.constraint(equalTo: leadingAnchor, constant: inset + Col.tagW + Col.lenW + Col.dirW + Col.probW / 2),

            hEuclid.bottomAnchor.constraint(equalTo: firstRow.topAnchor, constant: -1),
            hEuclid.centerXAnchor.constraint(equalTo: leadingAnchor, constant: inset + Col.tagW + Col.lenW + Col.dirW + Col.probW + Col.euclidW / 2),
        ])

        // Stack the rows (header leaves ~12pt at top).
        var prev: NSView? = nil
        for row in rows {
            NSLayoutConstraint.activate([
                row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset),
                row.heightAnchor.constraint(equalToConstant: Col.rowH),
            ])
            if let p = prev {
                row.topAnchor.constraint(equalTo: p.bottomAnchor, constant: 2).isActive = true
            } else {
                row.topAnchor.constraint(equalTo: topAnchor, constant: 14).isActive = true
            }
            prev = row
        }
    }

    // Fixed column widths (so headers line up over every row).
    private enum Col {
        static let tagW: CGFloat = 64
        static let lenW: CGFloat = 56
        static let dirW: CGFloat = 110
        static let probW: CGFloat = 44
        static let euclidW: CGFloat = 130
        static let rowH: CGFloat = 24
    }

    // MARK: - One lane row

    private func makeLaneRow(lane: Int, voice: ChipVoice) -> NSView {
        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false

        // [●color + "PUL1"]
        let dot = NSView()
        dot.wantsLayer = true
        dot.layer?.cornerRadius = 4
        dot.layer?.backgroundColor = voiceColor(voice).cgColor
        dot.translatesAutoresizingMaskIntoConstraints = false

        let label = NSTextField(labelWithString: theme.cased(voice.short))
        label.font = theme.fontMonoSmall
        label.textColor = voiceColor(voice)
        label.setAccessibilityElement(false)
        label.translatesAutoresizingMaskIntoConstraints = false

        // [Len: NSStepper 1…16]
        let lenStepper = NSStepper()
        lenStepper.controlSize = .small
        lenStepper.minValue = 1
        lenStepper.maxValue = 16
        lenStepper.increment = 1
        lenStepper.integerValue = engine.length(lane: lane)
        lenStepper.valueWraps = false
        lenStepper.translatesAutoresizingMaskIntoConstraints = false
        lenStepper.setAccessibilityLabel("\(voice.short) length")

        let lenReadout = NSTextField(labelWithString: "\(engine.length(lane: lane))")
        lenReadout.font = theme.fontMonoSmall
        lenReadout.textColor = theme.textSecondary
        lenReadout.alignment = .right
        lenReadout.setAccessibilityElement(false)
        lenReadout.translatesAutoresizingMaskIntoConstraints = false

        lenStepper.onChange = { [weak self] in
            guard let self else { return }
            let n = lenStepper.integerValue
            self.engine.setLength(n, lane: lane)
            lenReadout.stringValue = "\(n)"
            self.onChange()
        }

        // [Dir: small NSSegmentedControl of the 4 StepDirection labels]
        let dirSeg = NSSegmentedControl(labels: StepDirection.allCases.map { $0.label },
                                        trackingMode: .selectOne, target: nil, action: nil)
        dirSeg.controlSize = .small
        dirSeg.segmentDistribution = .fillEqually
        dirSeg.selectedSegment = engine.direction(lane: lane).rawValue
        dirSeg.translatesAutoresizingMaskIntoConstraints = false
        dirSeg.setAccessibilityLabel("\(voice.short) direction")
        dirSeg.onChange = { [weak self] in
            guard let self else { return }
            let idx = dirSeg.selectedSegment
            if let d = StepDirection(rawValue: idx) {
                self.engine.setDirection(d, lane: lane)
                self.onChange()
            }
        }

        // [Prob: ChipKnob 0…1 → setLaneProbability]
        let probKnob = ChipKnob(value: 1.0, in: 0 ... 1)
        probKnob.setAccessibilityLabel("\(voice.short) probability")
        probKnob.onChange = { [weak self] v in
            self?.engine.setLaneProbability(Int((v * 100).rounded()), lane: lane)
            self?.onChange()
        }

        // [Euclid: NSStepper hits 0–16 + Fill button]
        let euclidStepper = NSStepper()
        euclidStepper.controlSize = .small
        euclidStepper.minValue = 0
        euclidStepper.maxValue = 16
        euclidStepper.increment = 1
        euclidStepper.integerValue = 4
        euclidStepper.valueWraps = false
        euclidStepper.translatesAutoresizingMaskIntoConstraints = false
        euclidStepper.setAccessibilityLabel("\(voice.short) Euclidean hits")

        let euclidReadout = NSTextField(labelWithString: "4")
        euclidReadout.font = theme.fontMonoSmall
        euclidReadout.textColor = theme.textSecondary
        euclidReadout.alignment = .right
        euclidReadout.setAccessibilityElement(false)
        euclidReadout.translatesAutoresizingMaskIntoConstraints = false
        euclidStepper.onChange = {
            euclidReadout.stringValue = "\(euclidStepper.integerValue)"
        }

        let fill = ChipIconButton(symbols: ["circle.grid.cross", "circle.grid.3x3.fill", "circle.grid.3x3"],
                                  label: "\(voice.short) Euclidean fill")
        fill.onClick = { [weak self] in
            guard let self else { return }
            self.engine.euclidean(lane: lane, hits: euclidStepper.integerValue)
            self.onChange()   // also covered by engine.onPatternChanged, but explicit is fine
        }

        for v in [dot, label, lenStepper, lenReadout, dirSeg, probKnob,
                  euclidStepper, euclidReadout, fill] {
            v.translatesAutoresizingMaskIntoConstraints = false
            row.addSubview(v)
        }

        // --- Column layout inside the row ---
        let cy = row.centerYAnchor
        NSLayoutConstraint.activate([
            // tag: dot + label
            dot.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            dot.centerYAnchor.constraint(equalTo: cy),
            dot.widthAnchor.constraint(equalToConstant: 8),
            dot.heightAnchor.constraint(equalToConstant: 8),
            label.leadingAnchor.constraint(equalTo: dot.trailingAnchor, constant: 6),
            label.centerYAnchor.constraint(equalTo: cy),

            // Len column: readout + stepper
            lenReadout.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: Col.tagW),
            lenReadout.centerYAnchor.constraint(equalTo: cy),
            lenReadout.widthAnchor.constraint(equalToConstant: 18),
            lenStepper.leadingAnchor.constraint(equalTo: lenReadout.trailingAnchor, constant: 3),
            lenStepper.centerYAnchor.constraint(equalTo: cy),

            // Dir column
            dirSeg.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: Col.tagW + Col.lenW),
            dirSeg.centerYAnchor.constraint(equalTo: cy),
            dirSeg.widthAnchor.constraint(equalToConstant: Col.dirW - 8),

            // Prob column (knob is 40×40; center it in the column)
            probKnob.centerXAnchor.constraint(equalTo: row.leadingAnchor,
                                              constant: Col.tagW + Col.lenW + Col.dirW + Col.probW / 2),
            probKnob.centerYAnchor.constraint(equalTo: cy),

            // Euclid column: readout + stepper + Fill
            euclidReadout.leadingAnchor.constraint(equalTo: row.leadingAnchor,
                                                   constant: Col.tagW + Col.lenW + Col.dirW + Col.probW),
            euclidReadout.centerYAnchor.constraint(equalTo: cy),
            euclidReadout.widthAnchor.constraint(equalToConstant: 18),
            euclidStepper.leadingAnchor.constraint(equalTo: euclidReadout.trailingAnchor, constant: 3),
            euclidStepper.centerYAnchor.constraint(equalTo: cy),
            fill.leadingAnchor.constraint(equalTo: euclidStepper.trailingAnchor, constant: 6),
            fill.centerYAnchor.constraint(equalTo: cy),
            fill.trailingAnchor.constraint(lessThanOrEqualTo: row.trailingAnchor),

            row.trailingAnchor.constraint(greaterThanOrEqualTo: fill.trailingAnchor),
        ])

        return row
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
