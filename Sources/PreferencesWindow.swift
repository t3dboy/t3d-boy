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
        label.stringValue = title
        label.font = .systemFont(ofSize: 13)
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
        layer?.backgroundColor = isSelected ? NSColor.controlAccentColor.cgColor : NSColor.clear.cgColor
        label.textColor = isSelected ? .white : .labelColor
        iconView.contentTintColor = isSelected ? .white : .secondaryLabelColor
    }
}

final class PreferencesWindowController: NSWindowController {
    // RetroAchievements
    private let loginForm = RALoginForm()
    private let hardcoreCheck = NSButton(checkboxWithTitle:
        "Hardcore mode (no save-state loads, rewind, slow-motion, or cheats)", target: nil, action: nil)
    private let drawerCheck = NSButton(checkboxWithTitle:
        "Show the achievements drawer by default", target: nil, action: nil)
    private let soundCheck = NSButton(checkboxWithTitle:
        "Play a sound when an achievement unlocks", target: nil, action: nil)
    private let volumeSlider = NSSlider(value: 0.7, minValue: 0, maxValue: 1, target: nil, action: nil)
    private let cornerPopup = NSPopUpButton()
    private let testButton = NSButton(title: "Test Connection", target: nil, action: nil)
    private let testResult = NSTextField(labelWithString: "")
    // Screen effects
    private let hcLightingCheck = NSButton(checkboxWithTitle: "Hardcore Lighting", target: nil, action: nil)
    private let wormCheck = NSButton(checkboxWithTitle: "Worm Light", target: nil, action: nil)
    private let lcdCheck = NSButton(checkboxWithTitle: "T3d LCD Real Feel™", target: nil, action: nil)
    // Appearance
    private let darkModeCheck = NSButton(checkboxWithTitle: "Dark mode", target: nil, action: nil)
    private let fpsCheck = NSButton(checkboxWithTitle:
        "Show the FPS counter in the game window", target: nil, action: nil)

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

        wireControls()

        // --- Content sections ---
        let testRow = NSStackView(views: [testButton, testResult])
        testRow.spacing = 10; testRow.alignment = .centerY

        let achievementsC = sectionContent(title: "Achievements", items: [
            subheading("Account"), loginForm,
            subheading("Options"), hardcoreCheck, drawerCheck, testRow,
            subheading("Notifications"), soundCheck,
            labeledRow("Unlock volume", volumeSlider),
            labeledRow("Notification position", cornerPopup),
        ])
        let screenC = sectionContent(title: "Screen Effects", items: [
            effectRow(hcLightingCheck, "Dim the screen to match your room's ambient light, like the non-backlit DMG"),
            effectRow(wormCheck, "A warm '90s clip-on light shining down over the screen"),
            effectRow(lcdCheck, "Faithfully emulates an old LCD's pixel persistence"),
        ])
        let appearanceC = sectionContent(title: "Appearance", items: [darkModeCheck, fpsCheck])

        let defs: [(String, String, NSView)] = [
            ("trophy", "Achievements", achievementsC),
            ("sparkles.tv", "Screen Effects", screenC),
            ("paintpalette", "Appearance", appearanceC),
        ]

        // --- Sidebar ---
        let sidebar = NSVisualEffectView()
        sidebar.material = .sidebar
        sidebar.blendingMode = .behindWindow
        sidebar.state = .followsWindowActiveState
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
            ])
            sections.append((row, view))
        }

        refreshControls()
        select(0)
    }

    private func wireControls() {
        hardcoreCheck.target = self;  hardcoreCheck.action = #selector(toggleHardcore)
        drawerCheck.target = self;    drawerCheck.action = #selector(toggleDrawer)
        soundCheck.target = self;     soundCheck.action = #selector(toggleSound)
        volumeSlider.target = self;   volumeSlider.action = #selector(changeVolume)
        volumeSlider.widthAnchor.constraint(equalToConstant: 160).isActive = true
        for corner in ToastCorner.allCases { cornerPopup.addItem(withTitle: corner.label) }
        cornerPopup.target = self;    cornerPopup.action = #selector(changeCorner)
        testButton.bezelStyle = .rounded
        testButton.target = self;     testButton.action = #selector(testConnection)
        testResult.font = .systemFont(ofSize: 11); testResult.textColor = .secondaryLabelColor
        hcLightingCheck.target = self; hcLightingCheck.action = #selector(toggleHCLighting)
        wormCheck.target = self;       wormCheck.action = #selector(toggleWormLight)
        lcdCheck.target = self;        lcdCheck.action = #selector(toggleLCD)
        darkModeCheck.target = self;   darkModeCheck.action = #selector(toggleDarkMode)
        fpsCheck.target = self;        fpsCheck.action = #selector(toggleFPS)
    }

    private func select(_ index: Int) {
        for (i, s) in sections.enumerated() {
            s.row.isSelected = (i == index)
            s.content.isHidden = (i != index)
        }
    }

    // MARK: - Layout helpers

    private func sectionContent(title: String, items: [NSView]) -> NSView {
        let header = NSTextField(labelWithString: title)
        header.font = .systemFont(ofSize: 20, weight: .bold)
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
        let label = NSTextField(labelWithString: text.uppercased())
        label.font = .systemFont(ofSize: 11, weight: .semibold)
        label.textColor = .secondaryLabelColor
        return label
    }

    private func labeledRow(_ text: String, _ control: NSView) -> NSView {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 13)
        let row = NSStackView(views: [label, control])
        row.spacing = 10; row.alignment = .centerY
        return row
    }

    // A toggle with a secondary description underneath, indented under its label.
    private func effectRow(_ check: NSButton, _ subtitle: String) -> NSView {
        let sub = NSTextField(wrappingLabelWithString: subtitle)
        sub.font = .systemFont(ofSize: 11)
        sub.textColor = .secondaryLabelColor
        sub.translatesAutoresizingMaskIntoConstraints = false
        sub.preferredMaxLayoutWidth = 380
        let holder = NSView()
        holder.translatesAutoresizingMaskIntoConstraints = false
        holder.addSubview(sub)
        NSLayoutConstraint.activate([
            sub.leadingAnchor.constraint(equalTo: holder.leadingAnchor, constant: 20),
            sub.topAnchor.constraint(equalTo: holder.topAnchor),
            sub.bottomAnchor.constraint(equalTo: holder.bottomAnchor),
            sub.trailingAnchor.constraint(lessThanOrEqualTo: holder.trailingAnchor),
        ])
        let v = NSStackView(views: [check, holder])
        v.orientation = .vertical
        v.alignment = .leading
        v.spacing = 2
        return v
    }

    // MARK: - State

    private func refreshControls() {
        loginForm.refresh()
        hardcoreCheck.state = RASettings.hardcore ? .on : .off
        drawerCheck.state = RASettings.showDrawerByDefault ? .on : .off
        soundCheck.state = RASettings.unlockSound ? .on : .off
        volumeSlider.doubleValue = RASettings.unlockVolume
        volumeSlider.isEnabled = RASettings.unlockSound
        cornerPopup.selectItem(at: RASettings.toastCorner.rawValue)
        fpsCheck.state = RASettings.showFPS ? .on : .off
        refreshEffectControls()
        refreshAppearanceControl()
    }

    private func refreshEffectControls() {
        hcLightingCheck.state = HardcoreLighting.isEnabled ? .on : .off
        wormCheck.state = WormLight.isEnabled ? .on : .off
        lcdCheck.state = LCDGhosting.isEnabled ? .on : .off
    }

    /// Keep the dark-mode checkbox in step with the app's current appearance.
    func refreshAppearanceControl() {
        darkModeCheck.state = (NSApp.delegate as? AppDelegate)?.isDarkMode == true ? .on : .off
    }

    // MARK: - Actions

    @objc private func toggleHardcore() { RASettings.hardcore = (hardcoreCheck.state == .on) }
    @objc private func toggleDrawer()   { RASettings.showDrawerByDefault = (drawerCheck.state == .on) }
    @objc private func toggleSound() {
        RASettings.unlockSound = (soundCheck.state == .on)
        volumeSlider.isEnabled = RASettings.unlockSound
    }
    @objc private func changeVolume()   { RASettings.unlockVolume = volumeSlider.doubleValue }
    @objc private func changeCorner() {
        RASettings.toastCorner = ToastCorner(rawValue: cornerPopup.indexOfSelectedItem) ?? .topRight
    }
    @objc private func toggleHCLighting() { HardcoreLighting.isEnabled = (hcLightingCheck.state == .on) }
    @objc private func toggleWormLight()  { WormLight.isEnabled = (wormCheck.state == .on) }
    @objc private func toggleLCD()        { LCDGhosting.isEnabled = (lcdCheck.state == .on) }
    @objc private func toggleDarkMode() {
        (NSApp.delegate as? AppDelegate)?.setAppearance(dark: darkModeCheck.state == .on)
    }
    @objc private func toggleFPS() { RASettings.showFPS = (fpsCheck.state == .on) }

    @objc private func testConnection() {
        testButton.isEnabled = false
        testResult.stringValue = "Checking…"
        testResult.textColor = .secondaryLabelColor
        Achievements.shared.testConnection { [weak self] ok in
            guard let self else { return }
            self.testButton.isEnabled = true
            self.testResult.stringValue = ok ? "Connected ✓" : "Couldn't reach RetroAchievements"
            self.testResult.textColor = ok ? .systemGreen : .systemRed
        }
    }
}
