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

    // Column x-positions (leading edge), tuned to fit ~900pt wide within the host's insets.
    private let xLabel: CGFloat = 0
    private let xArpToggle: CGFloat = 60
    private let xArpShape: CGFloat = 100
    private let xArpRate: CGFloat = 188
    private let xPWM: CGFloat = 250
    private let xVib: CGFloat = 330
    private let xRatchet: CGFloat = 412

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
        // Column-header caption row, aligned over each control column.
        let header = NSView()
        header.translatesAutoresizingMaskIntoConstraints = false
        addSubview(header)
        for (x, t) in [(xArpToggle, "Arp"), (xPWM, "PWM"), (xVib, "Vib"), (xRatchet, "Ratchet")] {
            let cap = caption(t)
            header.addSubview(cap)
            NSLayoutConstraint.activate([
                cap.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: x),
                cap.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            ])
        }

        let rows = NSStackView()
        rows.orientation = .vertical
        rows.alignment = .leading
        rows.spacing = 4
        rows.translatesAutoresizingMaskIntoConstraints = false
        for i in 0 ..< 4 { rows.addArrangedSubview(laneRow(lane: i)) }
        addSubview(rows)

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            header.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            header.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            header.heightAnchor.constraint(equalToConstant: 10),

            rows.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 2),
            rows.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            rows.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
        ])
    }

    private func laneRow(lane: Int) -> NSView {
        let voice = ChipVoice(rawValue: lane)!
        let accent = voiceColor(voice)
        let isPitched = (voice != .noise)
        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false

        // [● + label]
        let dot = NSView()
        dot.wantsLayer = true
        dot.layer?.backgroundColor = accent.cgColor
        dot.layer?.cornerRadius = 4
        dot.translatesAutoresizingMaskIntoConstraints = false
        let label = NSTextField(labelWithString: theme.cased(voice.short))
        label.font = theme.fontMonoSmall
        label.textColor = accent
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
        shapeMenu.controlSize = .small
        shapeMenu.font = theme.fontCaption
        shapeMenu.addItems(withTitles: ArpShape.allCases.map { theme.cased($0.label) })
        shapeMenu.selectItem(at: arp.shape.rawValue)
        shapeMenu.isEnabled = isPitched
        shapeMenu.setAccessibilityLabel("\(voice.short) arpeggio shape")

        // Arp rate stepper (1…8)
        let rateStepper = NSStepper()
        rateStepper.translatesAutoresizingMaskIntoConstraints = false
        rateStepper.controlSize = .small
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
        let pwmKnob = ChipKnob(value: engine.pwm(lane: lane), in: 0 ... 1)
        pwmKnob.setAccessibilityLabel("\(voice.short) pulse-width modulation")
        pwmKnob.onChange = { [weak self] v in
            guard let self else { return }
            self.engine.setPWM(v, lane: lane)
            self.onChange()
        }

        // Vibrato depth knob (0…1) — preserves the lane's current rate.
        let vibKnob = ChipKnob(value: engine.vibratoInfo(lane: lane).depth, in: 0 ... 1)
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
        ratchetStepper.controlSize = .small
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

        // Dim the pitch-only cells on the NOISE lane.
        let pwmCell = wrapKnob(pwmKnob)
        let vibCell = wrapKnob(vibKnob)
        if !isPitched {
            for v in [arpToggle, shapeMenu, rateStepper, rateReadout, pwmCell, vibCell] as [NSView] {
                v.alphaValue = 0.32
            }
        }

        // --- Layout ---
        for v in [dot, label, arpToggle, shapeMenu, rateStepper, rateReadout,
                  pwmCell, vibCell, ratchetStepper, ratchetReadout] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            row.addSubview(v)
        }
        NSLayoutConstraint.activate([
            row.heightAnchor.constraint(equalToConstant: 26),

            dot.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: xLabel),
            dot.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            dot.widthAnchor.constraint(equalToConstant: 8),
            dot.heightAnchor.constraint(equalToConstant: 8),
            label.leadingAnchor.constraint(equalTo: dot.trailingAnchor, constant: 6),
            label.centerYAnchor.constraint(equalTo: row.centerYAnchor),

            arpToggle.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: xArpToggle),
            arpToggle.centerYAnchor.constraint(equalTo: row.centerYAnchor),

            shapeMenu.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: xArpShape),
            shapeMenu.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            shapeMenu.widthAnchor.constraint(equalToConstant: 72),

            rateStepper.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: xArpRate),
            rateStepper.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            rateReadout.leadingAnchor.constraint(equalTo: rateStepper.trailingAnchor, constant: 3),
            rateReadout.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            rateReadout.widthAnchor.constraint(equalToConstant: 14),

            pwmCell.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: xPWM),
            pwmCell.centerYAnchor.constraint(equalTo: row.centerYAnchor),

            vibCell.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: xVib),
            vibCell.centerYAnchor.constraint(equalTo: row.centerYAnchor),

            ratchetStepper.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: xRatchet),
            ratchetStepper.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            ratchetReadout.leadingAnchor.constraint(equalTo: ratchetStepper.trailingAnchor, constant: 3),
            ratchetReadout.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            ratchetReadout.widthAnchor.constraint(equalToConstant: 14),
            ratchetStepper.trailingAnchor.constraint(lessThanOrEqualTo: row.trailingAnchor),
        ])
        return row
    }

    // A 20pt ChipKnob shrunk into a compact cell would overflow the row; ChipKnob is a
    // fixed 40×40, so wrap it so its centre aligns and it doesn't stretch the 26pt row.
    private func wrapKnob(_ knob: ChipKnob) -> NSView {
        let cell = NSView()
        cell.translatesAutoresizingMaskIntoConstraints = false
        knob.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(knob)
        NSLayoutConstraint.activate([
            cell.widthAnchor.constraint(equalToConstant: 40),
            cell.heightAnchor.constraint(equalToConstant: 24),
            knob.centerXAnchor.constraint(equalTo: cell.centerXAnchor),
            knob.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }

    private func caption(_ t: String) -> NSTextField {
        let cap = NSTextField(labelWithString: theme.cased(t))
        cap.font = .monospacedSystemFont(ofSize: 8, weight: .medium)
        cap.textColor = theme.textMuted
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
