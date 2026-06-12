// T3d Boy — app delegate: library, ROM folder mapping, appearance, menus

import Cocoa
import UniformTypeIdentifiers

final class AppDelegate: NSObject, NSApplicationDelegate {
    static let appearanceKey = "appearance"

    var library: LibraryWindowController?
    var gameWindows: [GameWindowController] = []
    var onboarding: OnboardingWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        ROMFolders.migrateIfNeeded()
        applyStoredAppearance()
        buildMenu()
        GamepadManager.shared.start()
        GamepadManager.shared.onStatusChange = { [weak self] in
            self?.gameWindows.forEach { $0.updateControllerStatus() }
        }

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
            lib.onPlay = { [weak self] url in self?.play(url: url) }
            lib.onToggleDark = { [weak self] dark in self?.setAppearance(dark: dark) }
            library = lib
        }
        library?.setDarkSwitch(on: isDarkMode)
        library?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)

        if ROMFolders.isConfigured {
            library?.reload()
        } else {
            showOnboarding(mode: .firstRun) // first launch: T3d takes it from here
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

    func play(url: URL) {
        do {
            let rom = try ROMLoader.load(url: url)
            let game = GameWindowController(
                rom: rom, title: url.deletingPathExtension().lastPathComponent, url: url)
            game.onClose = { [weak self, weak game] in
                self?.gameWindows.removeAll { $0 === game }
            }
            gameWindows.append(game)
            game.showWindow(nil)
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
        switch UserDefaults.standard.string(forKey: AppDelegate.appearanceKey) {
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        default: break // follow the system
        }
    }

    func setAppearance(dark: Bool) {
        NSApp.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        UserDefaults.standard.set(dark ? "dark" : "light", forKey: AppDelegate.appearanceKey)
        library?.setDarkSwitch(on: dark)
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
