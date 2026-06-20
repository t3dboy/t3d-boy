// T3d Boy — T3d Tunes "Timbre" panel: per-lane GB-synth voicing.
//
// One row per lane (PUL1 / PUL2 / WAVE / NOIS), each exposing the authentic Game Boy
// synth controls the engine drives per note: Arpeggio (on + shape + rate), PWM (duty
// sweep), Vibrato (pitch wobble depth) and Ratchet (per-step retrigger count). The NOISE
// lane has no pitch, so its Arp / PWM / Vib cells are dimmed and inert — only Ratchet
// applies. Controls initialise from the engine's current per-lane state.

import Cocoa

final class TimbrePanel: NSView {
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

    // MARK: Build

    private func build() {
        // 2×2 grid: one card per channel.
        let cards = (0 ..< 4).map { laneRow(lane: $0) }
        let top = quarterRow([cards[0], cards[1]])
        let bottom = quarterRow([cards[2], cards[3]])
        let grid = NSStackView(views: [top, bottom])
        grid.orientation = .vertical
        grid.distribution = .fillEqually
        grid.spacing = 10
        grid.translatesAutoresizingMaskIntoConstraints = false
        addSubview(grid)
        NSLayoutConstraint.activate([
            grid.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            grid.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            grid.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            grid.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
        ])
    }

    private func quarterRow(_ cards: [NSView]) -> NSStackView {
        let r = NSStackView(views: cards)
        r.orientation = .horizontal
        r.distribution = .fillEqually
        r.spacing = 12
        return r
    }

    /// A horizontal control group.
    private func hRow(_ views: [NSView], _ spacing: CGFloat) -> NSStackView {
        let s = NSStackView(views: views)
        s.orientation = .horizontal; s.alignment = .centerY; s.spacing = spacing
        return s
    }

    /// A control with a caption above it.
    private func captioned(_ title: String, _ control: NSView, dim: Bool = false) -> NSView {
        let cap = caption(title)
        let v = NSStackView(views: [cap, control])
        v.orientation = .vertical; v.alignment = .centerX; v.spacing = 5
        v.translatesAutoresizingMaskIntoConstraints = false
        if dim { v.alphaValue = 0.32 }
        return v
    }

    private func laneRow(lane: Int) -> NSView {
        let voice = ChipVoice(rawValue: lane)!
        let accent = voiceColor(voice)
        let isPitched = (voice != .noise)
        let row = NSView()
        row.wantsLayer = true
        row.layer?.cornerRadius = theme.radiusMedium
        row.layer?.backgroundColor = accent.withAlphaComponent(0.07).cgColor
        row.layer?.borderWidth = 1
        row.layer?.borderColor = accent.withAlphaComponent(0.28).cgColor
        row.translatesAutoresizingMaskIntoConstraints = false

        // [● + label]
        let dot = NSView()
        dot.wantsLayer = true
        dot.layer?.backgroundColor = accent.cgColor
        dot.layer?.cornerRadius = 5
        dot.translatesAutoresizingMaskIntoConstraints = false
        let label = NSTextField(labelWithString: theme.cased(voice.short))
        label.font = theme.skinned ? .rounded(14, .semibold) : .systemFont(ofSize: 14, weight: .bold)
        label.textColor = accent
        label.setAccessibilityElement(false)
        label.translatesAutoresizingMaskIntoConstraints = false

        let arp = engine.arpInfo(lane: lane)

        // Arp toggle
        let arpToggle = SettingToggle()
        arpToggle.setAccessibilityName("\(voice.short) Arpeggiator")
        arpToggle.isOn = arp.on
        arpToggle.isEnabled = isPitched

        // Arp shape menu
        let shapeMenu = NSPopUpButton(frame: .zero, pullsDown: false)
        shapeMenu.translatesAutoresizingMaskIntoConstraints = false
        shapeMenu.controlSize = .regular
        shapeMenu.font = theme.fontCaption
        shapeMenu.addItems(withTitles: ArpShape.allCases.map { theme.cased($0.label) })
        shapeMenu.selectItem(at: arp.shape.rawValue)
        shapeMenu.isEnabled = isPitched
        shapeMenu.setAccessibilityLabel("\(voice.short) arpeggio shape")

        // Arp rate stepper (1…8)
        let rateStepper = NSStepper()
        rateStepper.translatesAutoresizingMaskIntoConstraints = false
        rateStepper.controlSize = .regular
        rateStepper.minValue = 1
        rateStepper.maxValue = 8
        rateStepper.increment = 1
        rateStepper.integerValue = arp.rate
        rateStepper.isEnabled = isPitched
        rateStepper.setAccessibilityLabel("\(voice.short) arpeggio rate")
        let rateReadout = NSTextField(labelWithString: "\(arp.rate)")
        rateReadout.font = theme.fontMonoSmall
        rateReadout.textColor = theme.textMuted
        rateReadout.alignment = .center
        rateReadout.translatesAutoresizingMaskIntoConstraints = false
        rateReadout.setAccessibilityElement(false)

        // Apply arp changes from any of the three controls.
        let applyArp: () -> Void = { [weak self] in
            guard let self else { return }
            let shape = ArpShape(rawValue: shapeMenu.indexOfSelectedItem) ?? .octave
            let rate = rateStepper.integerValue
            rateReadout.stringValue = "\(rate)"
            self.engine.setArp(on: arpToggle.isOn, shape: shape, rate: rate, lane: lane)
            self.onChange()
        }
        arpToggle.onToggle = { _ in applyArp() }
        // Drive shape/rate via target-action relays (NSPopUpButton/NSStepper need an ObjC target).
        let shapeRelay = ActionRelay { applyArp() }
        shapeMenu.target = shapeRelay
        shapeMenu.action = #selector(ActionRelay.fire)
        let rateRelay = ActionRelay { applyArp() }
        rateStepper.target = rateRelay
        rateStepper.action = #selector(ActionRelay.fire)
        objc_setAssociatedObject(row, &Self.relayKeyA, shapeRelay, .OBJC_ASSOCIATION_RETAIN)
        objc_setAssociatedObject(row, &Self.relayKeyB, rateRelay, .OBJC_ASSOCIATION_RETAIN)

        // PWM knob (0…1)
        let pwmKnob = ChipKnob(value: engine.pwm(lane: lane), in: 0 ... 1, diameter: 52)
        pwmKnob.setAccessibilityLabel("\(voice.short) pulse-width modulation")
        pwmKnob.onChange = { [weak self] v in
            guard let self else { return }
            self.engine.setPWM(v, lane: lane)
            self.onChange()
        }

        // Vibrato depth knob (0…1) — preserves the lane's current rate.
        let vibKnob = ChipKnob(value: engine.vibratoInfo(lane: lane).depth, in: 0 ... 1, diameter: 52)
        vibKnob.setAccessibilityLabel("\(voice.short) vibrato depth")
        vibKnob.onChange = { [weak self] v in
            guard let self else { return }
            let rate = self.engine.vibratoInfo(lane: lane).rate
            self.engine.setVibrato(depth: v, rate: rate, lane: lane)
            self.onChange()
        }

        // Ratchet stepper (1…8) — applies to every lane, including NOISE.
        let initialRatchet = engine.ratchet(lane: lane, step: 0)
        let ratchetStepper = NSStepper()
        ratchetStepper.translatesAutoresizingMaskIntoConstraints = false
        ratchetStepper.controlSize = .regular
        ratchetStepper.minValue = 1
        ratchetStepper.maxValue = 8
        ratchetStepper.increment = 1
        ratchetStepper.integerValue = initialRatchet
        ratchetStepper.setAccessibilityLabel("\(voice.short) ratchet")
        let ratchetReadout = NSTextField(labelWithString: "\(initialRatchet)")
        ratchetReadout.font = theme.fontMonoSmall
        ratchetReadout.textColor = theme.textMuted
        ratchetReadout.alignment = .center
        ratchetReadout.translatesAutoresizingMaskIntoConstraints = false
        ratchetReadout.setAccessibilityElement(false)
        let ratchetRelay = ActionRelay { [weak self] in
            guard let self else { return }
            let r = ratchetStepper.integerValue
            ratchetReadout.stringValue = "\(r)"
            self.engine.setLaneRatchet(r, lane: lane)
            self.onChange()
        }
        ratchetStepper.target = ratchetRelay
        ratchetStepper.action = #selector(ActionRelay.fire)
        objc_setAssociatedObject(row, &Self.relayKeyC, ratchetRelay, .OBJC_ASSOCIATION_RETAIN)

        // --- Header (dot + channel name) ---
        let header = NSStackView(views: [dot, label])
        header.orientation = .horizontal; header.alignment = .centerY; header.spacing = 7
        header.translatesAutoresizingMaskIntoConstraints = false

        // --- Captioned control groups, spread across the card's quarter. ---
        shapeMenu.widthAnchor.constraint(equalToConstant: 92).isActive = true
        rateReadout.widthAnchor.constraint(equalToConstant: 14).isActive = true
        ratchetReadout.widthAnchor.constraint(equalToConstant: 14).isActive = true

        let arpGroup = captioned("Arp", hRow([arpToggle, shapeMenu, rateStepper, rateReadout], 6),
                                 dim: !isPitched)
        let pwmGroup = captioned("PWM", pwmKnob, dim: !isPitched)
        let vibGroup = captioned("Vib", vibKnob, dim: !isPitched)
        let ratchetGroup = captioned("Ratchet", hRow([ratchetStepper, ratchetReadout], 5))

        let controls = NSStackView(views: [arpGroup, pwmGroup, vibGroup, ratchetGroup])
        controls.orientation = .horizontal
        controls.alignment = .centerY
        controls.distribution = .equalSpacing
        controls.translatesAutoresizingMaskIntoConstraints = false

        row.addSubview(header)
        row.addSubview(controls)
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: row.topAnchor, constant: 8),
            header.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 14),
            dot.widthAnchor.constraint(equalToConstant: 10),
            dot.heightAnchor.constraint(equalToConstant: 10),

            controls.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 14),
            controls.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -14),
            controls.topAnchor.constraint(greaterThanOrEqualTo: header.bottomAnchor, constant: 4),
            controls.centerYAnchor.constraint(equalTo: row.centerYAnchor, constant: 12),
            controls.bottomAnchor.constraint(lessThanOrEqualTo: row.bottomAnchor, constant: -8),
        ])
        return row
    }

    private func caption(_ t: String) -> NSTextField {
        let cap = NSTextField(labelWithString: theme.cased(t))
        cap.font = .monospacedSystemFont(ofSize: 9, weight: .medium)
        cap.textColor = theme.textMuted
        cap.alignment = .center
        cap.translatesAutoresizingMaskIntoConstraints = false
        cap.setAccessibilityElement(false)
        return cap
    }

    // Associated-object keys keeping each row's action relays alive.
    private static var relayKeyA = 0
    private static var relayKeyB = 0
    private static var relayKeyC = 0
}

// MARK: - Tiny target-action relay
//
// NSPopUpButton / NSStepper need an ObjC target + selector. This forwards their action to
// a Swift closure, so each lane row can capture its own controls without a shared selector.
private final class ActionRelay: NSObject {
    private let handler: () -> Void
    init(_ handler: @escaping () -> Void) { self.handler = handler }
    @objc func fire() { handler() }
}
