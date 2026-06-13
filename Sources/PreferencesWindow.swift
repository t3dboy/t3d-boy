// T3d Boy — Preferences (⌘,) window.
//
// Currently a single RetroAchievements section: account sign-in, hardcore mode, and
// the cosmetic toast/drawer options. Built to grow — add a new section view and drop
// it into the stack. All controls read/write RASettings, which persists to
// UserDefaults and broadcasts .raSettingsChanged so the live UI updates immediately.

import Cocoa

final class PreferencesWindowController: NSWindowController {
    private let loginForm = RALoginForm()
    private let hardcoreCheck = NSButton(checkboxWithTitle:
        "Hardcore mode (no save-state loads, rewind, slow-motion, or cheats)", target: nil, action: nil)
    private let drawerCheck = NSButton(checkboxWithTitle:
        "Show the achievements drawer by default", target: nil, action: nil)
    private let soundCheck = NSButton(checkboxWithTitle:
        "Play a sound when an achievement unlocks", target: nil, action: nil)
    private let volumeSlider = NSSlider(value: 0.7, minValue: 0, maxValue: 1,
                                        target: nil, action: nil)
    private let cornerPopup = NSPopUpButton()
    private let testButton = NSButton(title: "Test Connection", target: nil, action: nil)
    private let testResult = NSTextField(labelWithString: "")
    private let darkModeCheck = NSButton(checkboxWithTitle: "Dark mode", target: nil, action: nil)

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 580),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Preferences"
        super.init(window: window)
        buildUI()
        window.center()
        loginForm.onChange = { [weak self] in self?.refreshControls() }
    }
    required init?(coder: NSCoder) { fatalError() }

    private func buildUI() {
        guard let content = window?.contentView else { return }

        let title = NSTextField(labelWithString: "RetroAchievements")
        title.font = .systemFont(ofSize: 17, weight: .bold)

        let account = section("Account", views: [loginForm])

        hardcoreCheck.target = self;  hardcoreCheck.action = #selector(toggleHardcore)
        drawerCheck.target = self;    drawerCheck.action = #selector(toggleDrawer)
        soundCheck.target = self;     soundCheck.action = #selector(toggleSound)
        volumeSlider.target = self;   volumeSlider.action = #selector(changeVolume)
        volumeSlider.widthAnchor.constraint(equalToConstant: 160).isActive = true

        let volumeRow = labeledRow("Unlock volume", volumeSlider)

        for corner in ToastCorner.allCases { cornerPopup.addItem(withTitle: corner.label) }
        cornerPopup.target = self
        cornerPopup.action = #selector(changeCorner)
        let cornerRow = labeledRow("Notification position", cornerPopup)

        testButton.bezelStyle = .rounded
        testButton.target = self
        testButton.action = #selector(testConnection)
        testResult.font = .systemFont(ofSize: 11)
        testResult.textColor = .secondaryLabelColor
        let testRow = NSStackView(views: [testButton, testResult])
        testRow.spacing = 10
        testRow.alignment = .centerY

        let options = section("Options", views: [
            hardcoreCheck, drawerCheck, soundCheck, volumeRow, cornerRow, testRow,
        ])

        let appearanceTitle = NSTextField(labelWithString: "Appearance")
        appearanceTitle.font = .systemFont(ofSize: 17, weight: .bold)
        darkModeCheck.target = self
        darkModeCheck.action = #selector(toggleDarkMode)
        let appearance = section("Theme", views: [darkModeCheck])

        let root = NSStackView(views: [title, account, options, appearanceTitle, appearance])
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 18
        root.edgeInsets = NSEdgeInsets(top: 22, left: 24, bottom: 22, right: 24)
        root.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(root)
        NSLayoutConstraint.activate([
            root.topAnchor.constraint(equalTo: content.topAnchor),
            root.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            root.bottomAnchor.constraint(greaterThanOrEqualTo: content.bottomAnchor, constant: -22),
        ])

        refreshControls()
    }

    // MARK: - Layout helpers

    private func section(_ heading: String, views: [NSView]) -> NSView {
        let label = NSTextField(labelWithString: heading.uppercased())
        label.font = .systemFont(ofSize: 11, weight: .semibold)
        label.textColor = .secondaryLabelColor
        let stack = NSStackView(views: [label] + views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        return stack
    }

    private func labeledRow(_ text: String, _ control: NSView) -> NSView {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 13)
        let row = NSStackView(views: [label, control])
        row.spacing = 10
        row.alignment = .centerY
        return row
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
        refreshAppearanceControl()
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
    @objc private func toggleDarkMode() {
        (NSApp.delegate as? AppDelegate)?.setAppearance(dark: darkModeCheck.state == .on)
    }

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
