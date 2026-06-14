// T3d Boy — decorative chrome for the "Engineer" theme.
//
// These views recreate the boutique sampler device flair around the
// existing ROM library: a near-black I/O strip, an engraved header plate with the
// wordmark + katakana + a drilled speaker grille, hex screws, and a bottom trim. They
// are purely cosmetic (no controls) — the spec calls for them to be built faithfully
// even though they don't do anything. The one live element is `MinutesLED`, which
// shows total minutes played across every ROM and accumulates as you play.

import Cocoa

/// A recessed hex screw dot.
final class HexScrew: NSView {
    init(diameter: CGFloat = 11) {
        super.init(frame: NSRect(x: 0, y: 0, width: diameter, height: diameter))
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: diameter).isActive = true
        heightAnchor.constraint(equalToConstant: diameter).isActive = true
        layer?.cornerRadius = diameter / 2
        layer?.backgroundColor = NSColor(hex: 0x9A9A95).cgColor
        layer?.borderWidth = 2
        layer?.borderColor = NSColor(hex: 0xB0B0AA).cgColor
    }
    required init?(coder: NSCoder) { fatalError() }
}

/// Small mono label chip used in the I/O bar.
private func ioChip(_ text: String, bg: NSColor, fg: NSColor) -> NSView {
    let label = NSTextField(labelWithString: text)
    label.font = .monospacedSystemFont(ofSize: 8, weight: .medium)
    label.textColor = fg
    label.setAccessibilityElement(false) // decorative device flair
    label.translatesAutoresizingMaskIntoConstraints = false
    let box = NSView()
    box.wantsLayer = true
    box.layer?.cornerRadius = 3
    box.layer?.backgroundColor = bg.cgColor
    box.translatesAutoresizingMaskIntoConstraints = false
    box.addSubview(label)
    NSLayoutConstraint.activate([
        label.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 7),
        label.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -7),
        label.topAnchor.constraint(equalTo: box.topAnchor, constant: 3),
        label.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -3),
    ])
    return box
}

private func ioWord(_ text: String, _ color: NSColor) -> NSTextField {
    let l = NSTextField(labelWithString: text)
    l.font = .monospacedSystemFont(ofSize: 8, weight: .regular)
    l.textColor = color
    l.setAccessibilityElement(false) // decorative
    return l
}

/// Near-black I/O bar: OUTPUT / DISPLAY / T3d chips on the left, SYNC / MIDI / POWER + a
/// glowing red dot on the right.
final class EngineerIOBar: NSView {
    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor(hex: 0x1B1B1D).cgColor
        translatesAutoresizingMaskIntoConstraints = false

        let powerDot = NSView()
        powerDot.wantsLayer = true
        powerDot.translatesAutoresizingMaskIntoConstraints = false
        powerDot.widthAnchor.constraint(equalToConstant: 7).isActive = true
        powerDot.heightAnchor.constraint(equalToConstant: 7).isActive = true
        powerDot.layer?.cornerRadius = 3.5
        powerDot.layer?.backgroundColor = NSColor(hex: 0xFF3320).cgColor
        powerDot.layer?.shadowColor = NSColor(hex: 0xFF3320).cgColor
        powerDot.layer?.shadowRadius = 4
        powerDot.layer?.shadowOpacity = 0.9
        powerDot.layer?.shadowOffset = .zero

        let left = NSStackView(views: [
            ioChip("OUTPUT", bg: NSColor(hex: 0xE9E9E4), fg: NSColor(hex: 0x1B1B1D)),
            ioChip("DISPLAY", bg: NSColor(hex: 0xF24F1E), fg: NSColor(hex: 0x1B1B1D)),
            ioChip("T3d", bg: NSColor(hex: 0x3A3A3D), fg: NSColor(hex: 0xCFCFCA)),
        ])
        left.spacing = 6
        left.translatesAutoresizingMaskIntoConstraints = false

        let right = NSStackView(views: [
            ioWord("SYNC", NSColor(hex: 0x7D7D78)),
            ioWord("MIDI", NSColor(hex: 0x7D7D78)),
            ioWord("POWER", NSColor(hex: 0xCFCFCA)),
            powerDot,
        ])
        right.spacing = 6
        right.alignment = .centerY
        right.translatesAutoresizingMaskIntoConstraints = false

        addSubview(left); addSubview(right)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 30),
            left.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            left.centerYAnchor.constraint(equalTo: centerYAnchor),
            right.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            right.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }
}

/// The drilled speaker grille: a fixed grid of perfectly round holes.
final class EngineerGrille: NSView {
    private let cols = 9, rows = 6, hole: CGFloat = 6, gap: CGFloat = 7

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor(hex: 0xD9D9D3).setFill()
        bounds.fill()
        let gridW = CGFloat(cols) * hole + CGFloat(cols - 1) * gap
        let gridH = CGFloat(rows) * hole + CGFloat(rows - 1) * gap
        let ox = (bounds.width - gridW) / 2
        let oy = (bounds.height - gridH) / 2
        NSColor(hex: 0x9D9D97).setFill()
        for r in 0..<rows {
            for c in 0..<cols {
                let x = ox + CGFloat(c) * (hole + gap)
                let y = oy + CGFloat(r) * (hole + gap)
                let p = NSBezierPath(ovalIn: NSRect(x: x, y: y, width: hole, height: hole))
                p.fill()
                NSColor.black.withAlphaComponent(0.3).setStroke()
                p.lineWidth = 0.5
                p.stroke()
                NSColor(hex: 0x9D9D97).setFill()
            }
        }
    }
}

/// Engraved header plate: T3d·BOY wordmark + ライブラリ, hairline, subtitle, a screw,
/// and the speaker grille down the right edge.
final class EngineerHeaderPlate: NSView {
    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor(hex: 0xECEAE5).cgColor
        translatesAutoresizingMaskIntoConstraints = false

        let wordmark = NSTextField(labelWithString: "T3d·BOY")
        wordmark.font = .rounded(23, .medium)
        wordmark.textColor = NSColor(hex: 0x1F1F1E)
        let kata = NSTextField(labelWithString: "ライブラリ")
        kata.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
        kata.textColor = NSColor(hex: 0xF24F1E)
        let titleRow = NSStackView(views: [wordmark, kata])
        titleRow.alignment = .lastBaseline
        titleRow.spacing = 9
        titleRow.translatesAutoresizingMaskIntoConstraints = false

        let rule = NSView()
        rule.wantsLayer = true
        rule.layer?.backgroundColor = NSColor(hex: 0xCDCDC6).cgColor
        rule.translatesAutoresizingMaskIntoConstraints = false

        let subtitle = NSTextField(labelWithString: "8-BIT DOT-MATRIX SYSTEM   ·   DMG-01")
        subtitle.font = .monospacedSystemFont(ofSize: 8, weight: .regular)
        subtitle.textColor = NSColor(hex: 0x6F6F6B)
        subtitle.translatesAutoresizingMaskIntoConstraints = false
        kata.setAccessibilityElement(false)       // decorative katakana
        subtitle.setAccessibilityElement(false)   // decorative model line

        let screw = HexScrew(diameter: 9)
        let grille = EngineerGrille()
        grille.translatesAutoresizingMaskIntoConstraints = false
        let grilleEdge = NSView()
        grilleEdge.wantsLayer = true
        grilleEdge.layer?.backgroundColor = NSColor(hex: 0xC2C2BC).cgColor
        grilleEdge.translatesAutoresizingMaskIntoConstraints = false
        let bottomLine = NSView()
        bottomLine.wantsLayer = true
        bottomLine.layer?.backgroundColor = NSColor(hex: 0xB6B6B0).cgColor
        bottomLine.translatesAutoresizingMaskIntoConstraints = false

        for v in [titleRow, rule, subtitle, screw, grilleEdge, grille, bottomLine] { addSubview(v) }

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 74),

            grille.trailingAnchor.constraint(equalTo: trailingAnchor),
            grille.topAnchor.constraint(equalTo: topAnchor),
            grille.bottomAnchor.constraint(equalTo: bottomAnchor),
            grille.widthAnchor.constraint(equalToConstant: 128),
            grilleEdge.trailingAnchor.constraint(equalTo: grille.leadingAnchor),
            grilleEdge.topAnchor.constraint(equalTo: topAnchor),
            grilleEdge.bottomAnchor.constraint(equalTo: bottomAnchor),
            grilleEdge.widthAnchor.constraint(equalToConstant: 1),

            titleRow.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            titleRow.topAnchor.constraint(equalTo: topAnchor, constant: 13),
            titleRow.trailingAnchor.constraint(lessThanOrEqualTo: grilleEdge.leadingAnchor, constant: -16),

            screw.topAnchor.constraint(equalTo: topAnchor, constant: 11),
            screw.trailingAnchor.constraint(equalTo: grilleEdge.leadingAnchor, constant: -8),

            rule.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            rule.trailingAnchor.constraint(equalTo: grilleEdge.leadingAnchor, constant: -16),
            rule.topAnchor.constraint(equalTo: titleRow.bottomAnchor, constant: 9),
            rule.heightAnchor.constraint(equalToConstant: 1),

            subtitle.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            subtitle.topAnchor.constraint(equalTo: rule.bottomAnchor, constant: 7),

            bottomLine.leadingAnchor.constraint(equalTo: leadingAnchor),
            bottomLine.trailingAnchor.constraint(equalTo: trailingAnchor),
            bottomLine.bottomAnchor.constraint(equalTo: bottomAnchor),
            bottomLine.heightAnchor.constraint(equalToConstant: 1),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }
}

/// Bottom trim strip: hex screws, the engineering wordmark and a serial number.
final class EngineerTrim: NSView {
    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor(hex: 0xBCBCB6).cgColor
        translatesAutoresizingMaskIntoConstraints = false

        let topLine = NSView()
        topLine.wantsLayer = true
        topLine.layer?.backgroundColor = NSColor(hex: 0xAAAAA4).cgColor
        topLine.translatesAutoresizingMaskIntoConstraints = false

        let left = NSTextField(labelWithString: "T3d ENGINEERING · MADE FOR PLAY")
        left.font = .monospacedSystemFont(ofSize: 7, weight: .regular)
        left.textColor = NSColor(hex: 0x6F6F6B)
        let sn = NSTextField(labelWithString: "SN 0001-DMG")
        sn.font = .monospacedSystemFont(ofSize: 7, weight: .regular)
        sn.textColor = NSColor(hex: 0x6F6F6B)
        left.translatesAutoresizingMaskIntoConstraints = false
        sn.translatesAutoresizingMaskIntoConstraints = false
        left.setAccessibilityElement(false)  // decorative trim text
        sn.setAccessibilityElement(false)
        let screwL = HexScrew(), screwR = HexScrew()

        for v in [topLine, left, sn, screwL, screwR] { addSubview(v) }
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 32),
            topLine.leadingAnchor.constraint(equalTo: leadingAnchor),
            topLine.trailingAnchor.constraint(equalTo: trailingAnchor),
            topLine.topAnchor.constraint(equalTo: topAnchor),
            topLine.heightAnchor.constraint(equalToConstant: 1),
            screwL.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            screwL.centerYAnchor.constraint(equalTo: centerYAnchor),
            left.leadingAnchor.constraint(equalTo: screwL.trailingAnchor, constant: 10),
            left.centerYAnchor.constraint(equalTo: centerYAnchor),
            screwR.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            screwR.centerYAnchor.constraint(equalTo: centerYAnchor),
            sn.trailingAnchor.constraint(equalTo: screwR.leadingAnchor, constant: -10),
            sn.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }
}

/// Live red-LED chip showing total minutes played across every ROM, with an orange
/// 分 ("minutes") glyph. Updates whenever play time is recorded.
final class MinutesLED: NSView {
    private let number = NSTextField(labelWithString: "0")
    private let unit = NSTextField(labelWithString: "分")
    private var observer: NSObjectProtocol?

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 4
        layer?.backgroundColor = NSColor(hex: 0x161618).cgColor
        translatesAutoresizingMaskIntoConstraints = false

        number.font = .monospacedDigitSystemFont(ofSize: 13, weight: .bold)
        number.textColor = NSColor(hex: 0xFF3320)
        number.translatesAutoresizingMaskIntoConstraints = false
        unit.font = .monospacedSystemFont(ofSize: 10, weight: .medium)
        unit.textColor = NSColor(hex: 0xF24F1E)
        unit.translatesAutoresizingMaskIntoConstraints = false
        addSubview(number); addSubview(unit)
        NSLayoutConstraint.activate([
            number.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 7),
            number.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            number.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2),
            unit.leadingAnchor.constraint(equalTo: number.trailingAnchor, constant: 3),
            unit.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -7),
            unit.firstBaselineAnchor.constraint(equalTo: number.firstBaselineAnchor),
        ])
        refresh()
        observer = NotificationCenter.default.addObserver(
            forName: PlayStats.changed, object: nil, queue: .main
        ) { [weak self] _ in self?.refresh() }
    }
    required init?(coder: NSCoder) { fatalError() }
    deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }

    func refresh() {
        let mins = PlayStats.shared.totalSeconds / 60
        number.stringValue = "\(mins)"
        unit.setAccessibilityElement(false)
        number.setAccessibilityElement(false)
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
        setAccessibilityLabel("Total play time: \(mins) minutes")
    }
}
