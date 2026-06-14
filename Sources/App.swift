// T3d Boy — app delegate: library, ROM folder mapping, appearance, menus

import Cocoa
import UniformTypeIdentifiers

final class AppDelegate: NSObject, NSApplicationDelegate {
    static let appearanceKey = "appearance"

    var library: LibraryWindowController?
    var gameWindows: [GameWindowController] = []
    var onboarding: OnboardingWindowController?
    var achievementToasts: AchievementToastController?
    var preferences: PreferencesWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        ROMFolders.migrateIfNeeded()
        applyStoredAppearance()
        buildMenu()
        GamepadManager.shared.start()
        GamepadManager.shared.onStatusChange = { [weak self] in
            self?.gameWindows.forEach { $0.updateControllerStatus() }
        }

        // RetroAchievements: optional, degrades gracefully if unavailable.
        RASettings.registerDefaults()
        Achievements.shared.start()
        Achievements.shared.setHardcore(RASettings.hardcore) // apply stored preference
        Achievements.shared.loginWithStoredToken { _ in } // silent; no-ops if no saved token

        let toasts = AchievementToastController()
        toasts.corner = RASettings.toastCorner
        toasts.onActivate = { [weak self] id in
            let target = self?.gameWindows.first { $0.window?.isKeyWindow == true }
                ?? self?.gameWindows.last
            target?.openDrawerAndFocus(id)
        }
        toasts.start()
        achievementToasts = toasts
        // Keep the toast corner in sync when the user changes it in Preferences.
        NotificationCenter.default.addObserver(
            forName: .raSettingsChanged, object: nil, queue: .main
        ) { [weak self] _ in self?.achievementToasts?.corner = RASettings.toastCorner }

        // A theme switch rebuilds the open windows from scratch — many controls bake
        // the active theme (fonts, colours, lowercase) at construction and table cells
        // are cached, so recreating the controllers is the clean way to restyle live.
        NotificationCenter.default.addObserver(
            forName: .themeChanged, object: nil, queue: .main
        ) { [weak self] _ in DispatchQueue.main.async { self?.rebuildForTheme() } }

        // Direct ROM path on the command line (testing) skips the library
        let args = CommandLine.arguments
        if args.count > 1, FileManager.default.fileExists(atPath: args[1]) {
            play(url: URL(fileURLWithPath: args[1]))
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        showLibrary()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication,
                                       hasVisibleWindows flag: Bool) -> Bool {
        if !flag { showLibrary() }
        return true
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        if let url = urls.first { play(url: url) }
    }

    // MARK: - Library & folder mapping

    func showLibrary() {
        if library == nil {
            let lib = LibraryWindowController()
            lib.onPlay = { [weak self] url, rect in self?.play(url: url, from: rect) }
            library = lib
        }
        library?.refreshForAppearance()
        library?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)

        if ROMFolders.isConfigured {
            library?.reload()
        } else {
            showOnboarding(mode: .firstRun) // first launch: T3d takes it from here
        }
    }

    /// Recreate the library and preferences windows so the newly-selected theme
    /// applies everywhere. Preserves which were on screen.
    private func rebuildForTheme() {
        applyStoredAppearance() // a theme may force light/dark (Engineer is light-only)
        if let oldLib = library {
            let wasVisible = oldLib.window?.isVisible ?? false
            let oldOrigin = oldLib.window?.frame.origin
            oldLib.close()
            let lib = LibraryWindowController()
            lib.onPlay = { [weak self] url, rect in self?.play(url: url, from: rect) }
            library = lib
            if wasVisible {
                lib.showWindow(nil) // adopts the new theme's own size
                // Keep the window roughly where it was (themes have different sizes, so
                // don't carry the old size over — Engineer is larger than the others).
                if let oldOrigin, let w = lib.window {
                    var f = w.frame; f.origin = oldOrigin; w.setFrame(f, display: false)
                }
                if ROMFolders.isConfigured { lib.reload() }
            }
        }
        if let oldPrefs = preferences, oldPrefs.window?.isVisible == true {
            let section = oldPrefs.selectedSection
            oldPrefs.close()
            let prefs = PreferencesWindowController()
            preferences = prefs
            prefs.showWindow(nil)
            prefs.selectSection(section) // stay on the same tab (e.g. Appearance)
            prefs.window?.makeKeyAndOrderFront(nil)
        }
    }

    func showOnboarding(mode: OnboardingWindowController.Mode) {
        guard onboarding == nil else {
            onboarding?.window?.makeKeyAndOrderFront(nil)
            return
        }
        let wizard = OnboardingWindowController(mode: mode)
        wizard.onFoldersChanged = { [weak self] in self?.library?.reload() }
        wizard.onFinished = { [weak self] in
            self?.onboarding = nil
            self?.library?.reload() // surface freshly generated art
            self?.library?.window?.makeKeyAndOrderFront(nil)
        }
        onboarding = wizard
        wizard.showWindow(nil)
        wizard.window?.makeKeyAndOrderFront(nil)
    }

    @objc func generateBoxArt(_ sender: Any?) {
        guard ROMFolders.isConfigured else {
            showOnboarding(mode: .firstRun)
            return
        }
        showOnboarding(mode: .scanOnly)
    }

    @objc func chooseFolder(_ sender: Any?) {
        library?.changeFolderForCurrentTab()
    }

    @objc func openROM(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.message = "Select a .zip or .gb ROM file"
        var types: [UTType] = [.zip]
        if let gb = UTType(filenameExtension: "gb") { types.append(gb) }
        if let gbc = UTType(filenameExtension: "gbc") { types.append(gbc) }
        panel.allowedContentTypes = types
        if panel.runModal() == .OK, let url = panel.url {
            play(url: url)
        }
    }

    @objc func showLibraryAction(_ sender: Any?) {
        showLibrary()
    }

    @objc func showPreferences(_ sender: Any?) {
        if preferences == nil { preferences = PreferencesWindowController() }
        preferences?.showWindow(nil)
        preferences?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func play(url: URL, from sourceRect: NSRect? = nil) {
        do {
            let rom = try ROMLoader.load(url: url)
            let game = GameWindowController(
                rom: rom, title: url.deletingPathExtension().lastPathComponent, url: url,
                sourceRect: sourceRect)
            game.onClose = { [weak self, weak game] in
                self?.gameWindows.removeAll { $0 === game }
            }
            gameWindows.append(game)
            game.launch()
        } catch {
            let alert = NSAlert()
            alert.messageText = "Could not load ROM"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }

    // MARK: - Appearance

    var isDarkMode: Bool {
        NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    private func applyStoredAppearance() {
        // A skinned theme may force its own appearance (e.g. Engineer is light-only,
        // Pistachio dark); otherwise honour the user's Dark mode choice (dark by default).
        if let forced = theme.forcedAppearance {
            NSApp.appearance = NSAppearance(named: forced)
            return
        }
        switch UserDefaults.standard.string(forKey: AppDelegate.appearanceKey) {
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        default: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }

    func setAppearance(dark: Bool) {
        NSApp.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        UserDefaults.standard.set(dark ? "dark" : "light", forKey: AppDelegate.appearanceKey)
        library?.refreshForAppearance()
        preferences?.refreshAppearanceControl()
    }

    @objc func toggleDarkMode(_ sender: Any?) {
        setAppearance(dark: !isDarkMode)
    }

    // MARK: - Menu

    private func buildMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About T3d Boy",
                        action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
                        keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Preferences…",
                        action: #selector(showPreferences(_:)), keyEquivalent: ",")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit T3d Boy",
                        action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        let fileMenuItem = NSMenuItem()
        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(withTitle: "ROM Library",
                         action: #selector(showLibraryAction(_:)), keyEquivalent: "l")
        fileMenu.addItem(withTitle: "Open ROM…",
                         action: #selector(openROM(_:)), keyEquivalent: "o")
        fileMenu.addItem(.separator())
        fileMenu.addItem(withTitle: "Change Folder for Current Tab…",
                         action: #selector(chooseFolder(_:)), keyEquivalent: "")
        fileMenu.addItem(withTitle: "Generate Missing Box Art…",
                         action: #selector(generateBoxArt(_:)), keyEquivalent: "")
        fileMenuItem.submenu = fileMenu
        mainMenu.addItem(fileMenuItem)

        let gameMenuItem = NSMenuItem()
        let gameMenu = NSMenu(title: "Game")
        gameMenu.addItem(withTitle: "Pause",
                         action: #selector(GameWindowController.togglePause(_:)),
                         keyEquivalent: "p")
        let hardcoreItem = NSMenuItem(
            title: "Hardcore Lighting",
            action: #selector(GameWindowController.toggleHardcoreLighting(_:)), keyEquivalent: "h")
        hardcoreItem.keyEquivalentModifierMask = [.command, .control]
        gameMenu.addItem(hardcoreItem)
        let wormItem = NSMenuItem(
            title: "Worm Light",
            action: #selector(GameWindowController.toggleWormLight(_:)), keyEquivalent: "l")
        wormItem.keyEquivalentModifierMask = [.command, .control]
        gameMenu.addItem(wormItem)
        gameMenu.addItem(.separator())
        let saveItem = NSMenuItem(title: "Save State", action: nil, keyEquivalent: "")
        let saveSub = NSMenu(title: "Save State")
        let loadItem = NSMenuItem(title: "Load State", action: nil, keyEquivalent: "")
        let loadSub = NSMenu(title: "Load State")
        for slot in 1...5 {
            let save = NSMenuItem(title: "Slot \(slot)",
                                  action: #selector(GameWindowController.saveState(_:)),
                                  keyEquivalent: "\(slot)")
            save.tag = slot
            saveSub.addItem(save)
            let load = NSMenuItem(title: "Slot \(slot)",
                                  action: #selector(GameWindowController.loadState(_:)),
                                  keyEquivalent: "\(slot)")
            load.keyEquivalentModifierMask = [.command, .shift]
            load.tag = slot
            loadSub.addItem(load)
        }
        saveItem.submenu = saveSub
        loadItem.submenu = loadSub
        gameMenu.addItem(saveItem)
        gameMenu.addItem(loadItem)
        gameMenuItem.submenu = gameMenu
        mainMenu.addItem(gameMenuItem)

        let viewMenuItem = NSMenuItem()
        let viewMenu = NSMenu(title: "View")
        let darkItem = NSMenuItem(title: "Toggle Dark Mode",
                                  action: #selector(toggleDarkMode(_:)), keyEquivalent: "D")
        darkItem.keyEquivalentModifierMask = [.command, .shift]
        viewMenu.addItem(darkItem)
        viewMenuItem.submenu = viewMenu
        mainMenu.addItem(viewMenuItem)

        NSApp.mainMenu = mainMenu
    }
}
