// T3d Boy — Preferences (⌘,) window.
//
// A System Settings–style window: a vibrant left sidebar of categories and a content
// pane on the right. Categories: Account, Achievements, Notifications, Screen Effects,
// Appearance. Controls read/write RASettings / the lighting effects, which persist to
// UserDefaults and broadcast so the live UI updates immediately.

import Cocoa

// A selectable sidebar row (SF Symbol + label) with an accent highlight when chosen.
private final class PrefRow: NSView {
    var onSelect: (() -> Void)?
    var isSelected = false { didSet { refresh() } }
    private let iconView = NSImageView()
    private let label = NSTextField(labelWithString: "")

    init(symbol: String, title: String) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 6
        iconView.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 13, weight: .medium))
        iconView.translatesAutoresizingMaskIntoConstraints = false
        label.stringValue = theme.cased(title)
        label.font = theme.fontBody
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(iconView); addSubview(label)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 30),
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 9),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 18),
            label.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 8),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -8),
        ])
        refresh()
    }
    required init?(coder: NSCoder) { fatalError() }

    override func mouseDown(with event: NSEvent) { onSelect?() }

    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); refresh() }

    private func refresh() {
        // Fill the selected row with the accent (not theme.selection, which on some themes —
        // e.g. Engineer — is a dark "lit-pad" colour that would leave onAccent text
        // unreadable). onAccent is guaranteed to contrast with the accent.
        layer?.backgroundColor = isSelected ? theme.accent.cgColor : NSColor.clear.cgColor
        label.textColor = isSelected ? theme.onAccent : theme.textPrimary
        iconView.contentTintColor = isSelected ? theme.onAccent : theme.textSecondary
    }
}

final class PreferencesWindowController: NSWindowController {
    // RetroAchievements
    private let loginForm = RALoginForm()
    private let hardcoreToggle = SettingToggle()
    private let drawerToggle = SettingToggle()
    private let soundToggle = SettingToggle()
    private let volumeSlider = NSSlider(value: 0.7, minValue: 0, maxValue: 1, target: nil, action: nil)
    private let cornerPopup = NSPopUpButton()
    private let testButton = NSButton(title: "Test Connection", target: nil, action: nil)
    private let testResult = NSTextField(labelWithString: "")
    // Screen effects
    private let hcLightingToggle = SettingToggle()
    private let wormToggle = SettingToggle()
    private let lcdToggle = SettingToggle()
    // Appearance
    private var themeRadios: [NSButton] = []
    private let darkModeToggle = SettingToggle()
    private let fpsToggle = SettingToggle()

    private var darkModeRow: NSView?
    private let contentArea = NSView()
    private var sections: [(row: PrefRow, content: NSView)] = []

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 520),
            styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = "Preferences"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        super.init(window: window)
        buildUI()
        window.center()
        loginForm.onChange = { [weak self] in self?.refreshControls() }
        NotificationCenter.default.addObserver(
            forName: .screenEffectsChanged, object: nil, queue: .main
        ) { [weak self] _ in self?.refreshEffectControls() }
    }
    required init?(coder: NSCoder) { fatalError() }

    private func buildUI() {
        guard let content = window?.contentView else { return }
        window?.backgroundColor = theme.skinned ? theme.surfaceWindow : .windowBackgroundColor
        if theme.skinned {
            content.wantsLayer = true
            content.layer?.backgroundColor = theme.surfaceWindow.cgColor
        }

        wireControls()

        // --- Content sections ---
        let testRow = NSStackView(views: [testButton, testResult])
        testRow.spacing = 10; testRow.alignment = .centerY

        let achievementsC = sectionContent(title: "Achievements", items: [
            subheading("Account"), loginForm,
            subheading("Options"),
            toggleRow("Hardcore mode", hardcoreToggle,
                      subtitle: "No save-state loads, rewind, slow-motion, or cheats"),
            toggleRow("Show the achievements drawer by default", drawerToggle),
            testRow,
            subheading("Notifications"),
            toggleRow("Play a sound when an achievement unlocks", soundToggle),
            labeledRow("Unlock volume", volumeSlider),
            labeledRow("Notification position", cornerPopup),
        ])
        let screenC = sectionContent(title: "Screen Effects", items: [
            toggleRow("Hardcore Lighting", hcLightingToggle,
                      subtitle: "Dim the screen to match your room's ambient light, like the non-backlit DMG"),
            toggleRow("Worm Light", wormToggle,
                      subtitle: "A warm '90s clip-on light shining down over the screen"),
            toggleRow("T3d LCD Real Feel™", lcdToggle,
                      subtitle: "Faithfully emulates an old LCD's pixel persistence"),
        ])
        let darkRow = toggleRow("Dark mode", darkModeToggle,
                                subtitle: theme.forcedAppearance != nil
                                    ? "\(theme.name) uses its own colour palette" : nil)
        darkModeRow = darkRow
        let appearanceC = sectionContent(title: "Appearance", items: [
            labeledRow("Theme", themeSelector()),
            darkRow,
            toggleRow("Show the FPS counter in the game window", fpsToggle),
        ])

        let defs: [(String, String, NSView)] = [
            ("trophy", "Achievements", achievementsC),
            ("sparkles.tv", "Screen Effects", screenC),
            ("paintpalette", "Appearance", appearanceC),
        ]

        // --- Sidebar ---
        let sidebar: NSView
        if theme.usesVibrancy {
            let v = NSVisualEffectView()
            v.material = theme.sidebarMaterial
            v.blendingMode = .behindWindow
            v.state = .followsWindowActiveState
            sidebar = v
        } else {
            let v = NSView()
            v.wantsLayer = true
            v.layer?.backgroundColor = theme.surfacePanel.cgColor
            sidebar = v
        }
        sidebar.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(sidebar)

        let rows = NSStackView()
        rows.orientation = .vertical
        rows.alignment = .leading
        rows.spacing = 2
        rows.translatesAutoresizingMaskIntoConstraints = false
        sidebar.addSubview(rows)

        contentArea.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(contentArea)

        NSLayoutConstraint.activate([
            sidebar.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            sidebar.topAnchor.constraint(equalTo: content.topAnchor),
            sidebar.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            sidebar.widthAnchor.constraint(equalToConstant: 190),

            rows.topAnchor.constraint(equalTo: sidebar.topAnchor, constant: 38), // clear traffic lights
            rows.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 8),
            rows.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: -8),

            contentArea.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor),
            contentArea.topAnchor.constraint(equalTo: content.topAnchor),
            contentArea.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            contentArea.trailingAnchor.constraint(equalTo: content.trailingAnchor),
        ])

        for (i, (symbol, title, view)) in defs.enumerated() {
            let row = PrefRow(symbol: symbol, title: title)
            row.onSelect = { [weak self] in self?.select(i) }
            rows.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: rows.widthAnchor).isActive = true

            view.translatesAutoresizingMaskIntoConstraints = false
            view.isHidden = true
            contentArea.addSubview(view)
            NSLayoutConstraint.activate([
                view.topAnchor.constraint(equalTo: contentArea.topAnchor),
                view.leadingAnchor.constraint(equalTo: contentArea.leadingAnchor),
                view.trailingAnchor.constraint(equalTo: contentArea.trailingAnchor),
                // Fill the pane height too — without a bottom the view collapses to ~0
                // height and its controls, though drawn, fall outside its bounds and
                // become unclickable (hit-testing respects bounds).
                view.bottomAnchor.constraint(equalTo: contentArea.bottomAnchor),
            ])
            sections.append((row, view))
        }

        refreshControls()
        select(0)
    }

    private func wireControls() {
        hardcoreToggle.onToggle = { RASettings.hardcore = $0; Achievements.shared.setHardcore($0) }
        drawerToggle.onToggle = { RASettings.showDrawerByDefault = $0 }
        soundToggle.onToggle = { [weak self] in RASettings.unlockSound = $0; self?.refreshControls() }
        volumeSlider.target = self;   volumeSlider.action = #selector(changeVolume)
        volumeSlider.widthAnchor.constraint(equalToConstant: 160).isActive = true
        for corner in ToastCorner.allCases { cornerPopup.addItem(withTitle: corner.label) }
        cornerPopup.target = self;    cornerPopup.action = #selector(changeCorner)
        testButton.bezelStyle = .rounded
        testButton.target = self;     testButton.action = #selector(testConnection)
        testResult.font = theme.fontCaption; testResult.textColor = theme.textSecondary
        hcLightingToggle.onToggle = { HardcoreLighting.isEnabled = $0 }
        wormToggle.onToggle = { WormLight.isEnabled = $0 }
        lcdToggle.onToggle = { LCDGhosting.isEnabled = $0 }
        darkModeToggle.onToggle = { (NSApp.delegate as? AppDelegate)?.setAppearance(dark: $0) }
        fpsToggle.onToggle = { RASettings.showFPS = $0 }
    }

    /// Radio-button theme picker (native, reliably clickable). Grouped by shared action.
    private func themeSelector() -> NSView {
        themeRadios = ThemeManager.shared.all.enumerated().map { i, t in
            let b = NSButton(radioButtonWithTitle: theme.cased(t.name),
                             target: self, action: #selector(themeRadioChanged(_:)))
            b.tag = i
            b.font = theme.fontBody
            b.contentTintColor = theme.textPrimary
            return b
        }
        let stack = NSStackView(views: themeRadios)
        stack.orientation = .horizontal
        stack.spacing = 18
        stack.alignment = .centerY
        return stack
    }

    @objc private func themeRadioChanged(_ sender: NSButton) {
        guard let t = ThemeManager.shared.all[safe: sender.tag] else { return }
        ThemeManager.shared.select(id: t.id)
    }

    /// The section currently shown, so a theme switch (which recreates this window)
    /// can reopen on the same tab instead of jumping back to the first.
    private(set) var selectedSection = 0

    /// Select a section by index, clamped to the valid range. Public so the app can
    /// restore the tab after recreating the window.
    func selectSection(_ index: Int) { select(min(max(0, index), max(0, sections.count - 1))) }

    private func select(_ index: Int) {
        selectedSection = index
        for (i, s) in sections.enumerated() {
            s.row.isSelected = (i == index)
            s.content.isHidden = (i != index)
        }
    }

    // MARK: - Layout helpers

    private func sectionContent(title: String, items: [NSView]) -> NSView {
        let header = ThemedUI.title(title)
        let stack = NSStackView(views: [header] + items)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.setCustomSpacing(20, after: header)
        // Give each in-section subheading (a bare label) extra room above it.
        for (i, v) in items.enumerated() where v is NSTextField {
            stack.setCustomSpacing(26, after: i == 0 ? header : items[i - 1])
        }
        stack.translatesAutoresizingMaskIntoConstraints = false
        let container = NSView()
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 28),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -28),
        ])
        return container
    }

    // A small all-caps group label used to separate clusters within a section.
    private func subheading(_ text: String) -> NSView {
        ThemedUI.sectionHeader(text)
    }

    private func labeledRow(_ text: String, _ control: NSView) -> NSView {
        let label = NSTextField(labelWithString: theme.cased(text))
        label.font = theme.fontBody
        label.textColor = theme.textSecondary
        let row = NSStackView(views: [label, control])
        row.spacing = 10; row.alignment = .centerY
        return row
    }

    // A settings row: title on the left, toggle pinned to the right, optional grey
    // description beneath the title. Fixed width so toggles line up down a section.
    private func toggleRow(_ title: String, _ toggle: SettingToggle, subtitle: String? = nil) -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        toggle.setAccessibilityName(subtitle.map { "\(title). \($0)" } ?? title)
        let label = NSTextField(labelWithString: theme.cased(title))
        label.font = theme.fontBody
        label.textColor = theme.textSecondary
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        toggle.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label); container.addSubview(toggle)

        var cs = [
            container.widthAnchor.constraint(equalToConstant: 440),
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            label.topAnchor.constraint(equalTo: container.topAnchor),
            toggle.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            toggle.centerYAnchor.constraint(equalTo: label.centerYAnchor),
            toggle.leadingAnchor.constraint(greaterThanOrEqualTo: label.trailingAnchor, constant: 12),
        ]
        if let subtitle {
            let sub = ThemedUI.caption(subtitle)
            sub.translatesAutoresizingMaskIntoConstraints = false
            sub.preferredMaxLayoutWidth = 360
            container.addSubview(sub)
            cs += [
                sub.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                sub.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 3),
                sub.trailingAnchor.constraint(lessThanOrEqualTo: toggle.leadingAnchor, constant: -12),
                sub.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            ]
        } else {
            cs.append(label.bottomAnchor.constraint(equalTo: container.bottomAnchor))
        }
        NSLayoutConstraint.activate(cs)
        return container
    }

    // MARK: - State

    private func refreshControls() {
        loginForm.refresh()
        hardcoreToggle.isOn = RASettings.hardcore
        drawerToggle.isOn = RASettings.showDrawerByDefault
        soundToggle.isOn = RASettings.unlockSound
        volumeSlider.doubleValue = RASettings.unlockVolume
        volumeSlider.isEnabled = RASettings.unlockSound
        cornerPopup.selectItem(at: RASettings.toastCorner.rawValue)
        fpsToggle.isOn = RASettings.showFPS
        if let i = ThemeManager.shared.all.firstIndex(where: { $0.id == theme.id }) {
            for (j, b) in themeRadios.enumerated() { b.state = (j == i) ? .on : .off }
        }
        refreshEffectControls()
        refreshAppearanceControl()
    }

    private func refreshEffectControls() {
        hcLightingToggle.isOn = HardcoreLighting.isEnabled
        wormToggle.isOn = WormLight.isEnabled
        lcdToggle.isOn = LCDGhosting.isEnabled
    }

    /// Keep the dark-mode toggle in step with the app's current appearance. Skinned
    /// themes (e.g. Pistachio) define their own palette, so dark mode doesn't apply —
    /// grey the control out.
    func refreshAppearanceControl() {
        darkModeToggle.isOn = (NSApp.delegate as? AppDelegate)?.isDarkMode == true
        let locked = theme.forcedAppearance != nil
        darkModeToggle.isEnabled = !locked
        darkModeRow?.alphaValue = locked ? 0.4 : 1
    }

    // MARK: - Actions

    @objc private func changeVolume()   { RASettings.unlockVolume = volumeSlider.doubleValue }
    @objc private func changeCorner() {
        RASettings.toastCorner = ToastCorner(rawValue: cornerPopup.indexOfSelectedItem) ?? .topRight
    }

    @objc private func testConnection() {
        testButton.isEnabled = false
        testResult.stringValue = "Checking…"
        testResult.textColor = theme.textSecondary
        Achievements.shared.testConnection { [weak self] ok in
            guard let self else { return }
            self.testButton.isEnabled = true
            self.testResult.stringValue = ok ? "Connected ✓" : "Couldn't reach RetroAchievements"
            self.testResult.textColor = ok ? .systemGreen : .systemRed
        }
    }
}
