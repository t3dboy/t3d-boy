// T3d Boy — theming.
//
// A `Theme` is the single source of truth for the app's look & feel. Every screen
// asks for *semantic* tokens (`theme.accent`, `theme.surfacePanel`, `theme.fontTitle`)
// instead of hardcoding colours, fonts, radii or materials — so a whole new visual
// identity is a matter of defining one `Theme` value, not editing every view.
//
// `ThemeManager` owns the registry of available themes, the current selection
// (persisted to UserDefaults), and broadcasts `.themeChanged` when it changes so
// open windows can restyle live. `Theme.classic` reproduces the app's original
// system-driven appearance; `Theme.pistachio` is the warm soft-dark "friendly TE"
// skin (boutique synth key colours, lowercase rounded type, pistachio LCD).
//
// `theme.skinned` distinguishes the two modes: when false (Classic) screens use the
// system look and skip decorative chrome; when true (Pistachio) they apply the full
// skin (coloured panels, screw-dot housings, scanlines, lowercase rounded labels).

import Cocoa

struct Theme {
    let id: String
    let name: String

    /// Full decorative skin (Pistachio) vs system-native look (Classic). Screens use
    /// this to gate extra chrome that only the skinned theme should draw.
    var skinned: Bool
    /// Lowercase chrome labels (tabs, buttons, titles) for the friendly aesthetic.
    var lowercaseLabels: Bool
    /// UPPERCASE chrome labels (the Engineer signature).
    var uppercaseLabels: Bool = false
    /// Monospaced type personality (Engineer) — `uiFont()` returns mono instead of rounded.
    var monospaced: Bool = false
    /// Square (vs pill) toggle switches.
    var toggleSquared: Bool = false
    /// Appearance this theme forces (e.g. Engineer is light-only); nil = honour the
    /// user's Dark mode setting.
    var forcedAppearance: NSAppearance.Name? = nil
    /// Use translucent vibrancy (sidebar/HUD materials) vs flat opaque surfaces.
    var usesVibrancy: Bool

    // MARK: Surfaces
    var surfaceWindow: NSColor   // window body / right detail pane
    var surfacePanel: NSColor    // left list pane, cards, settings group
    var surfaceBar: NSColor      // title bar
    var surfaceFooter: NSColor   // folder / footer strip
    var surfaceInset: NSColor    // sort field, tab track
    var surfaceScreen: NSColor   // LCD / cover housing frame
    var lineHard: NSColor        // structural borders between panes
    var lineHair: NSColor        // list / settings row dividers
    var controlEdge: NSColor     // ghost-button border, screw dots, meter edge

    // MARK: Text
    var textPrimary: NSColor     // detail title
    var textSecondary: NSColor   // body labels, settings titles
    var textTitleBar: NSColor    // window title text
    var textListIdle: NSColor    // unselected list title
    var textMuted: NSColor       // metadata, score numbers
    var textFaint: NSColor       // descriptions, indices
    var onLight: NSColor         // text on a light/selected fill

    // MARK: Accents
    var accent: NSColor          // primary tint (selection, prominent buttons)
    var onAccent: NSColor        // text/icon on an accent fill
    var keyCoral: NSColor        // hero — active tab, selection, score meter
    var keyGreen: NSColor        // go — play button, toggle "on"
    var keyYellow: NSColor       // favourites star, sort caret
    var keyBlue: NSColor         // the "color" console tab
    var onGreen: NSColor         // text on green
    var onYellow: NSColor        // text on yellow
    /// Per-console-tab accent fills (game boy / color / faves). nil → use `accent`.
    var tabAccents: [NSColor]?

    // MARK: Derived control colours
    var selection: NSColor       // selected list-row tint (fill)
    var selectionEdge: NSColor   // selected list-row left border
    var star: NSColor            // favourite star
    var warm: NSColor            // secondary warm accent
    var cool: NSColor            // secondary cool accent
    var meterEmpty: NSColor      // empty score-meter segment
    var toggleOffTrack: NSColor  // toggle off track
    var toggleOffKnob: NSColor   // toggle off knob

    // MARK: Materials
    var sidebarMaterial: NSVisualEffectView.Material
    var hudMaterial: NSVisualEffectView.Material

    // MARK: Typography
    var fontTitle: NSFont          // pane / section titles
    var fontDetailTitle: NSFont    // the big selected-game title
    var fontSectionHeader: NSFont  // small all-caps group labels
    var fontBody: NSFont           // standard controls and labels
    var fontCaption: NSFont        // secondary descriptions
    var fontMonoSmall: NSFont      // numeric readouts (FPS, counts, index)

    // MARK: Metrics
    var radiusSmall: CGFloat       // chips, tab keys
    var radiusMedium: CGFloat      // cards, rows, buttons
    var radiusLarge: CGFloat       // windows, hero panels

    var spacing: CGFloat
    var spacingLarge: CGFloat

    // MARK: Motion
    var animFast: TimeInterval
    var animMedium: TimeInterval

    /// Apply this theme's casing to a chrome label.
    func cased(_ s: String) -> String {
        if uppercaseLabels { return s.uppercased() }
        if lowercaseLabels { return s.lowercased() }
        return s
    }
}

// MARK: - Font helpers

extension NSFont {
    /// System font in the rounded design (falls back to the standard face if rounded
    /// isn't available). Used by themes that want the friendly geometric look.
    static func rounded(_ size: CGFloat, _ weight: NSFont.Weight = .regular) -> NSFont {
        let base = NSFont.systemFont(ofSize: size, weight: weight)
        if let d = base.fontDescriptor.withDesign(.rounded) {
            return NSFont(descriptor: d, size: size) ?? base
        }
        return base
    }
}

// MARK: - Themes

extension Theme {
    /// The app's original appearance — system-driven, dark/light adaptive.
    static let classic = Theme(
        id: "classic",
        name: "Classic",
        skinned: false,
        lowercaseLabels: false,
        usesVibrancy: true,
        surfaceWindow: .windowBackgroundColor,
        surfacePanel: NSColor(name: nil) { a in
            a.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(white: 1, alpha: 0.05) : NSColor(white: 0, alpha: 0.035)
        },
        surfaceBar: .windowBackgroundColor,
        surfaceFooter: NSColor(white: 0.5, alpha: 0.06),
        surfaceInset: NSColor(white: 0.5, alpha: 0.07),
        surfaceScreen: NSColor.black.withAlphaComponent(0.15),
        lineHard: .separatorColor,
        lineHair: .separatorColor,
        controlEdge: .separatorColor,
        textPrimary: .labelColor,
        textSecondary: .secondaryLabelColor,
        textTitleBar: .secondaryLabelColor,
        textListIdle: .labelColor,
        textMuted: .secondaryLabelColor,
        textFaint: .tertiaryLabelColor,
        onLight: .white,
        accent: .controlAccentColor,
        onAccent: .white,
        keyCoral: .controlAccentColor,
        keyGreen: .controlAccentColor,
        keyYellow: .systemYellow,
        keyBlue: .controlAccentColor,
        onGreen: .white,
        onYellow: .black,
        tabAccents: nil,
        selection: .controlAccentColor,
        selectionEdge: .clear,
        star: .systemYellow,
        warm: .systemOrange,
        cool: .systemTeal,
        meterEmpty: NSColor(white: 0.5, alpha: 0.25),
        toggleOffTrack: NSColor(white: 0.5, alpha: 0.25),
        toggleOffKnob: .white,
        sidebarMaterial: .sidebar,
        hudMaterial: .hudWindow,
        fontTitle: .systemFont(ofSize: 20, weight: .bold),
        fontDetailTitle: .systemFont(ofSize: 22, weight: .bold),
        fontSectionHeader: .systemFont(ofSize: 11, weight: .semibold),
        fontBody: .systemFont(ofSize: 13),
        fontCaption: .systemFont(ofSize: 11),
        fontMonoSmall: .monospacedDigitSystemFont(ofSize: 11, weight: .medium),
        radiusSmall: 6,
        radiusMedium: 8,
        radiusLarge: 14,
        spacing: 8,
        spacingLarge: 16,
        animFast: 0.18,
        animMedium: 0.3
    )

    /// "Friendly TE" skin — warm soft-dark shell, boutique synth key colours, lowercase rounded
    /// type, pistachio LCD. Values mirror build/t3d-boy-skin/DESIGN-SPEC.md.
    static let pistachio = Theme(
        id: "pistachio",
        name: "Pistachio",
        skinned: true,
        lowercaseLabels: false, // natural sentence/title case — the lowercase look read as too much
        forcedAppearance: .darkAqua, // warm-dark palette
        usesVibrancy: false,
        surfaceWindow: NSColor(hex: 0x272320),
        surfacePanel: NSColor(hex: 0x221F1B),
        surfaceBar: NSColor(hex: 0x1E1B18),
        surfaceFooter: NSColor(hex: 0x1D1A16),
        surfaceInset: NSColor(hex: 0x1A1714),
        surfaceScreen: NSColor(hex: 0x15130F),
        lineHard: NSColor(hex: 0x14110E),
        lineHair: NSColor(white: 0.92, alpha: 0.06),
        controlEdge: NSColor(hex: 0x3C372F),
        textPrimary: NSColor(hex: 0xF2ECE2),
        textSecondary: NSColor(hex: 0xECE6DC),
        textTitleBar: NSColor(hex: 0xB7AFA3),
        textListIdle: NSColor(hex: 0xCFC8BD),
        textMuted: NSColor(hex: 0x857E73),
        textFaint: NSColor(hex: 0x7B746A),
        onLight: .white,
        accent: NSColor(hex: 0xEC6A5A),
        onAccent: NSColor(hex: 0x2A1410),
        keyCoral: NSColor(hex: 0xEC6A5A),
        keyGreen: NSColor(hex: 0x74B07A),
        keyYellow: NSColor(hex: 0xEDC04E),
        keyBlue: NSColor(hex: 0x5E9AD6),
        onGreen: NSColor(hex: 0x16280F),
        onYellow: NSColor(hex: 0x201410),
        tabAccents: [NSColor(hex: 0xEC6A5A), NSColor(hex: 0x5E9AD6), NSColor(hex: 0xEDC04E)],
        selection: NSColor(hex: 0xEC6A5A).withAlphaComponent(0.12),
        selectionEdge: NSColor(hex: 0xEC6A5A),
        star: NSColor(hex: 0xEDC04E),
        warm: NSColor(hex: 0xEC6A5A),
        cool: NSColor(hex: 0x5E9AD6),
        meterEmpty: NSColor(hex: 0x37322B),
        toggleOffTrack: NSColor(hex: 0x332F29),
        toggleOffKnob: NSColor(hex: 0x7B746A),
        sidebarMaterial: .sidebar,
        hudMaterial: .hudWindow,
        fontTitle: .rounded(18, .medium),
        fontDetailTitle: .rounded(19, .medium),
        fontSectionHeader: .rounded(11, .medium),
        fontBody: .rounded(13, .regular),
        fontCaption: .rounded(11, .regular),
        fontMonoSmall: .monospacedDigitSystemFont(ofSize: 10.5, weight: .regular),
        radiusSmall: 8,
        radiusMedium: 11,
        radiusLarge: 18,
        spacing: 9,
        spacingLarge: 17,
        animFast: 0.15,
        animMedium: 0.25
    )

    /// "Engineer" — boutique-sampler-inspired: sandblasted light-grey
    /// device body, orange rubber keys, red LED read-outs, mono UPPERCASE type, drilled
    /// speaker grille, hex screws, katakana labels. Light-only. See design notes.
    static let engineer = Theme(
        id: "engineer",
        name: "Engineer",
        skinned: true,
        lowercaseLabels: false,
        uppercaseLabels: true,
        monospaced: true,
        toggleSquared: true,
        forcedAppearance: .aqua, // light device body
        usesVibrancy: false,
        surfaceWindow: NSColor(hex: 0xC6C6C1), // device body
        surfacePanel: NSColor(hex: 0xE7E7E1),  // ROM list panel
        surfaceBar: NSColor(hex: 0x1B1B1D),    // I/O bar
        surfaceFooter: NSColor(hex: 0xBCBCB6), // bottom trim
        surfaceInset: NSColor(hex: 0xDCDCD6),  // sort field, settings group, tab track
        surfaceScreen: NSColor(hex: 0x141416), // LED display housing
        lineHard: NSColor(hex: 0xBCBCB6),
        lineHair: NSColor(white: 0, alpha: 0.07),
        controlEdge: NSColor(hex: 0xC2C2BC),
        textPrimary: NSColor(hex: 0x1F1F1E),
        textSecondary: NSColor(hex: 0x5F5F5B),
        textTitleBar: NSColor(hex: 0xCFCFCA),
        textListIdle: NSColor(hex: 0x33332F),
        textMuted: NSColor(hex: 0x9A9A95),
        textFaint: NSColor(hex: 0x7D7D78),
        onLight: .white,
        accent: NSColor(hex: 0xF24F1E),       // orange
        onAccent: NSColor(hex: 0x201008),
        keyCoral: NSColor(hex: 0xF24F1E),
        keyGreen: NSColor(hex: 0xF24F1E),     // primary action / toggle-on = orange
        keyYellow: NSColor(hex: 0xF24F1E),
        keyBlue: NSColor(hex: 0xF24F1E),
        onGreen: NSColor(hex: 0x201008),
        onYellow: NSColor(hex: 0x201008),
        tabAccents: [NSColor(hex: 0xF24F1E), NSColor(hex: 0xF24F1E), NSColor(hex: 0xF24F1E)],
        selection: NSColor(hex: 0x2A2A2C),    // selected row lights up dark, opaque
        selectionEdge: .clear,
        star: NSColor(hex: 0xF24F1E),
        warm: NSColor(hex: 0xF24F1E),
        cool: NSColor(hex: 0xF24F1E),
        meterEmpty: NSColor(hex: 0xC2C2BC),
        toggleOffTrack: NSColor(hex: 0xB0B0AA),
        toggleOffKnob: NSColor(hex: 0xE3E3DE),
        sidebarMaterial: .sidebar,
        hudMaterial: .hudWindow,
        fontTitle: .monospacedSystemFont(ofSize: 15, weight: .medium),
        fontDetailTitle: .rounded(17, .medium),
        fontSectionHeader: .monospacedSystemFont(ofSize: 11, weight: .medium),
        fontBody: .monospacedSystemFont(ofSize: 12, weight: .regular),
        fontCaption: .monospacedSystemFont(ofSize: 10, weight: .regular),
        fontMonoSmall: .monospacedDigitSystemFont(ofSize: 10, weight: .regular),
        radiusSmall: 6,
        radiusMedium: 8,
        radiusLarge: 13,
        spacing: 9,
        spacingLarge: 16,
        animFast: 0.12,
        animMedium: 0.2
    )

    /// "Liquid Glass" — a parody of Apple's glassy design language: bright, cool, frosted
    /// and bulbous… that's melting. Light-only; the melt drips are drawn by
    /// `LiquidGlassChrome`. Selection is a saturated glass blue so white text reads on it.
    static let liquidGlass = Theme(
        id: "liquidglass",
        name: "Liquid Glass",
        skinned: true,
        lowercaseLabels: false,
        forcedAppearance: .aqua, // glass reads best bright
        usesVibrancy: false, // real see-through glass, not a frosted vibrancy material
        // Per-pixel see-through: the window is clear and these panels are translucent, so
        // the real desktop shows through the chrome while opaque content (box art) stays
        // solid. Tuned so the glass has structure but you still see the desktop through it.
        surfaceWindow: NSColor(hex: 0xE7EFF8),                 // fallback (e.g. update prompt)
        surfacePanel: NSColor(white: 1, alpha: 0.08),          // slight structure over the 25% film
        surfaceBar: NSColor(white: 1, alpha: 0.10),
        surfaceFooter: NSColor(white: 1, alpha: 0.08),
        surfaceInset: NSColor(white: 1, alpha: 0.22),          // tab track, sort field (affordance)
        surfaceScreen: NSColor(hex: 0x14304F),                 // deep glass LCD housing
        lineHard: NSColor(hex: 0xBBD0E8),
        lineHair: NSColor(white: 0.15, alpha: 0.08),
        controlEdge: NSColor(hex: 0xAFC8E4),
        textPrimary: NSColor(hex: 0x18293E),
        textSecondary: NSColor(hex: 0x415066),
        textTitleBar: NSColor(hex: 0x415066),
        textListIdle: NSColor(hex: 0x26384E),
        textMuted: NSColor(hex: 0x7C8DA4),
        textFaint: NSColor(hex: 0x9AA9BE),
        onLight: .white,
        accent: NSColor(hex: 0x2E8BFF),        // glass azure
        onAccent: .white,
        keyCoral: NSColor(hex: 0x2E8BFF),      // hero = azure
        keyGreen: NSColor(hex: 0x2E8BFF),      // go / toggle-on = azure
        keyYellow: NSColor(hex: 0xFFC857),
        keyBlue: NSColor(hex: 0x49C0E8),
        onGreen: .white,
        onYellow: NSColor(hex: 0x2A1B00),
        tabAccents: [NSColor(hex: 0x2E8BFF), NSColor(hex: 0x49C0E8), NSColor(hex: 0xFFC857)],
        selection: NSColor(hex: 0x2E8BFF).withAlphaComponent(0.85),
        selectionEdge: NSColor(hex: 0x7FB4FF),
        star: NSColor(hex: 0xFFC857),
        warm: NSColor(hex: 0xFF9F4A),
        cool: NSColor(hex: 0x49C0E8),
        meterEmpty: NSColor(hex: 0xCBD8EA),
        toggleOffTrack: NSColor(hex: 0xC4D6EC),
        toggleOffKnob: .white,
        sidebarMaterial: .popover, // bright frosted blur in the Preferences sidebar
        hudMaterial: .hudWindow,
        fontTitle: .systemFont(ofSize: 19, weight: .semibold),
        fontDetailTitle: .systemFont(ofSize: 22, weight: .bold),
        fontSectionHeader: .systemFont(ofSize: 11, weight: .semibold),
        fontBody: .systemFont(ofSize: 13, weight: .regular),
        fontCaption: .systemFont(ofSize: 11, weight: .regular),
        fontMonoSmall: .monospacedDigitSystemFont(ofSize: 10.5, weight: .regular),
        radiusSmall: 10,
        radiusMedium: 16,
        radiusLarge: 26, // bulbous glass
        spacing: 9,
        spacingLarge: 17,
        animFast: 0.18,
        animMedium: 0.32
    )

    /// The red LED read-out colour for Engineer (rank, scores, status). Generic themes
    /// fall back to the accent.
    var led: NSColor { id == "engineer" ? NSColor(hex: 0xFF3320) : accent }
    var ledDim: NSColor { id == "engineer" ? NSColor(hex: 0x9A3A2A) : textMuted }
}

extension Array {
    /// Bounds-checked access: nil instead of a crash when the index is out of range.
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

extension NSColor {
    /// 0xRRGGBB → opaque sRGB colour.
    convenience init(hex: UInt32) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: 1)
    }
}

/// Convenience accessor: `theme.accent` anywhere.
var theme: Theme { ThemeManager.shared.current }

/// A UI font that adopts the rounded face under a skinned theme, plain system
/// otherwise. Drop-in for `.systemFont(ofSize:weight:)` at call sites that should
/// follow the theme's type personality.
func uiFont(_ size: CGFloat, _ weight: NSFont.Weight = .regular) -> NSFont {
    if theme.monospaced { return .monospacedSystemFont(ofSize: size, weight: weight) }
    return theme.skinned ? .rounded(size, weight) : .systemFont(ofSize: size, weight: weight)
}

final class ThemeManager {
    static let shared = ThemeManager()

    private let key = "selectedTheme"
    private(set) var all: [Theme]
    private(set) var current: Theme

    private init() {
        all = [.classic, .pistachio, .engineer, .liquidGlass]
        let savedID = UserDefaults.standard.string(forKey: key)
        // Pistachio is the default look for a fresh install; saved choice wins.
        current = all.first { $0.id == savedID } ?? .pistachio
    }

    func register(_ theme: Theme) {
        guard !all.contains(where: { $0.id == theme.id }) else { return }
        all.append(theme)
    }

    /// Switch the active theme, persist the choice, and notify open windows.
    func select(id: String) {
        guard let next = all.first(where: { $0.id == id }), next.id != current.id else { return }
        current = next
        UserDefaults.standard.set(id, forKey: key)
        NotificationCenter.default.post(name: .themeChanged, object: nil)
    }
}

extension Notification.Name {
    /// Posted by ThemeManager when the active theme changes. Screens rebuild/restyle on it.
    static let themeChanged = Notification.Name("T3dBoy.themeChanged")
}

// MARK: - Themed building blocks

enum ThemedUI {
    static func title(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: theme.cased(text))
        label.font = theme.fontTitle
        label.textColor = theme.textPrimary
        return label
    }

    static func sectionHeader(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: theme.cased(text.uppercased()))
        label.font = theme.fontSectionHeader
        label.textColor = theme.textMuted
        return label
    }

    static func caption(_ text: String) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: theme.cased(text))
        label.font = theme.fontCaption
        label.textColor = theme.textFaint
        return label
    }

    static func separator() -> NSView {
        let v = NSView()
        v.wantsLayer = true
        v.layer?.backgroundColor = theme.lineHair.cgColor
        v.translatesAutoresizingMaskIntoConstraints = false
        v.heightAnchor.constraint(equalToConstant: 1).isActive = true
        return v
    }

    /// A subtle rounded info chip, e.g. "Not compatible with this device".
    static func infoPill(_ text: String) -> NSView {
        let label = NSTextField(labelWithString: theme.cased(text))
        label.font = theme.fontCaption
        label.textColor = theme.textMuted
        label.translatesAutoresizingMaskIntoConstraints = false
        let pill = NSView()
        pill.wantsLayer = true
        pill.layer?.cornerRadius = 9
        pill.layer?.backgroundColor = theme.textPrimary.withAlphaComponent(0.08).cgColor
        pill.translatesAutoresizingMaskIntoConstraints = false
        pill.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: pill.leadingAnchor, constant: 9),
            label.trailingAnchor.constraint(equalTo: pill.trailingAnchor, constant: -9),
            label.topAnchor.constraint(equalTo: pill.topAnchor, constant: 3),
            label.bottomAnchor.constraint(equalTo: pill.bottomAnchor, constant: -3),
        ])
        pill.setContentHuggingPriority(.required, for: .horizontal)
        return pill
    }
}

// MARK: - Setting toggle
//
// The on/off control used across settings. Adapts to the active theme: a native
// NSSwitch in Classic (matches the rest of the system-native UI), a green pill
// (`ThemedToggle`) in skinned themes like Pistachio. One API for both.

final class SettingToggle: NSView {
    var onToggle: ((Bool) -> Void)?

    private let nativeSwitch: NSSwitch?
    private let pill: ThemedToggle?

    init() {
        if theme.skinned {
            let p = ThemedToggle(); pill = p; nativeSwitch = nil
        } else {
            let s = NSSwitch(); s.controlSize = .small; nativeSwitch = s; pill = nil
        }
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        let inner: NSView = pill ?? nativeSwitch!
        inner.translatesAutoresizingMaskIntoConstraints = false
        addSubview(inner)
        NSLayoutConstraint.activate([
            inner.leadingAnchor.constraint(equalTo: leadingAnchor),
            inner.trailingAnchor.constraint(equalTo: trailingAnchor),
            inner.topAnchor.constraint(equalTo: topAnchor),
            inner.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        pill?.onToggle = { [weak self] v in self?.onToggle?(v) }
        nativeSwitch?.target = self
        nativeSwitch?.action = #selector(switchChanged)
    }
    required init?(coder: NSCoder) { fatalError() }

    @objc private func switchChanged() { onToggle?(nativeSwitch?.state == .on) }

    /// VoiceOver label for the toggle (the setting's name), since the visible label is a
    /// separate sibling view the toggle can't see.
    func setAccessibilityName(_ name: String) {
        pill?.setAccessibilityLabel(name)
        nativeSwitch?.setAccessibilityLabel(name)
    }

    /// Disable interaction, e.g. a setting that doesn't apply to the current theme.
    /// (Dim the containing row for the visual greyed-out cue.)
    var isEnabled: Bool = true {
        didSet {
            nativeSwitch?.isEnabled = isEnabled
            pill?.isInteractive = isEnabled
        }
    }

    var isOn: Bool {
        get { pill?.isOn ?? (nativeSwitch?.state == .on) }
        set {
            pill?.setOn(newValue)
            nativeSwitch?.state = newValue ? .on : .off
        }
    }
}

// MARK: - Pill toggle
//
// A theme-aware toggle switch used in place of NSButton checkboxes. Matches the
// design spec: pill track (green when on / dark when off) with a sliding knob.

final class ThemedToggle: FocusableControl {
    var onToggle: ((Bool) -> Void)?
    var isOn = false { didSet { refresh(animated: true) } }
    var isInteractive = true

    override var acceptsFirstResponder: Bool { isInteractive }
    override var focusRingCornerRadius: CGFloat { theme.toggleSquared ? 6 : bounds.height / 2 }
    override func activate() {
        guard isInteractive else { return }
        isOn.toggle()
        onToggle?(isOn)
    }

    private let track = CALayer()
    private let knob = CALayer()
    private let trackW: CGFloat = 38
    private let trackH: CGFloat = 22
    private let inset: CGFloat = 2

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: trackW, height: trackH))
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: trackW).isActive = true
        heightAnchor.constraint(equalToConstant: trackH).isActive = true
        track.frame = bounds
        track.cornerRadius = theme.toggleSquared ? 5 : trackH / 2
        layer?.addSublayer(track)
        let kd = trackH - inset * 2
        knob.frame = CGRect(x: inset, y: inset, width: kd, height: kd)
        knob.cornerRadius = theme.toggleSquared ? 3 : kd / 2
        layer?.addSublayer(knob)
        setAccessibilityElement(true)
        setAccessibilityRole(.checkBox)
        refresh(animated: false)
    }
    required init?(coder: NSCoder) { fatalError() }

    /// Set state without firing the callback.
    func setOn(_ value: Bool) { let old = onToggle; onToggle = nil; isOn = value; onToggle = old }

    override func mouseDown(with event: NSEvent) {
        guard isInteractive else { return }
        isOn.toggle()
        onToggle?(isOn)
    }

    // MARK: Accessibility — a checkbox (role/element set in init; label via setAccessibilityName).
    override func accessibilityPerformPress() -> Bool {
        guard isInteractive else { return false }
        isOn.toggle()
        onToggle?(isOn)
        return true
    }

    override func layout() {
        super.layout()
        track.frame = bounds
        refresh(animated: false)
    }

    private func refresh(animated: Bool) {
        let kd = bounds.height - inset * 2
        let onX = bounds.width - inset - kd
        CATransaction.begin()
        CATransaction.setDisableActions(!animated)
        CATransaction.setAnimationDuration(theme.animFast)
        track.backgroundColor = (isOn ? theme.keyGreen : theme.toggleOffTrack).cgColor
        knob.backgroundColor = (isOn ? theme.onGreen : theme.toggleOffKnob).cgColor
        knob.frame = CGRect(x: isOn ? onX : inset, y: inset, width: kd, height: kd)
        CATransaction.commit()
        setAccessibilityValue(isOn ? 1 : 0)
    }
}
