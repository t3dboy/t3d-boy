// T3d Boy — first-run onboarding, hosted by T3d the mascot. Also reusable
// from File > Generate Missing Box Art as a scan-only flow.

import Cocoa
import UniformTypeIdentifiers

final class OnboardingWindowController: NSWindowController, NSWindowDelegate {
    enum Mode { case firstRun, scanOnly }
    private enum Step { case welcome, folder, artPrompt, scanning, done }
    private enum ScanScope { case top100, all }

    var onFoldersChanged: (() -> Void)?
    var onFinished: (() -> Void)?

    private let mode: Mode
    private var gbFolder: URL?
    private var gbcFolder: URL?
    private var step: Step = .welcome
    private var scanStart = Date()

    private let mascot = MascotView(frame: .zero)
    private let headline = NSTextField(labelWithString: "")
    private let body = NSTextField(wrappingLabelWithString: "")
    private let progressBar = NSProgressIndicator()
    private let progressLabel = NSTextField(labelWithString: "")
    private let primaryButton = CapsuleButton(title: "", style: .prominent)
    private let secondaryButton = CapsuleButton(title: "", style: .neutral, fontSize: 12, height: 30)
    private let tertiaryButton = CapsuleButton(title: "", style: .neutral, fontSize: 11, height: 26)
    private var controlsCard = NSView()

    // Two-folder picker (folder step)
    private var folderPicker = NSView()
    private let gbPathLabel = NSTextField(labelWithString: "Not set")
    private let gbcPathLabel = NSTextField(labelWithString: "Not set")
    private let gbChooseButton = CapsuleButton(title: "Choose…", style: .neutral, fontSize: 11, height: 26)
    private let gbcChooseButton = CapsuleButton(title: "Choose…", style: .neutral, fontSize: 11, height: 26)

    // Rough per-game cost used for up-front predictions; the live estimate
    // during a scan uses the measured rate instead
    private static let secondsPerGame = 0.8

    init(mode: Mode) {
        self.mode = mode
        self.gbFolder = ROMFolders.folder(.gb)
        self.gbcFolder = ROMFolders.folder(.gbc)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 470, height: 612),
            styleMask: [.titled, .closable],
            backing: .buffered, defer: false)
        window.title = "Welcome to T3d Boy"
        super.init(window: window)
        window.delegate = self
        buildUI()
        window.center()
        apply(mode == .scanOnly ? .artPrompt : .welcome)
    }
    required init?(coder: NSCoder) { fatalError() }

    private func buildUI() {
        guard let content = window?.contentView else { return }

        headline.font = .systemFont(ofSize: 21, weight: .bold)
        headline.alignment = .center

        body.font = .systemFont(ofSize: 13)
        body.textColor = .secondaryLabelColor
        body.alignment = .center

        progressBar.style = .bar
        progressBar.isIndeterminate = false
        progressBar.minValue = 0
        progressBar.maxValue = 1
        progressBar.isHidden = true

        progressLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        progressLabel.textColor = .secondaryLabelColor
        progressLabel.alignment = .center
        progressLabel.isHidden = true

        primaryButton.onClick = { [weak self] in self?.primaryAction() }
        secondaryButton.onClick = { [weak self] in self?.secondaryAction() }
        tertiaryButton.onClick = { [weak self] in self?.tertiaryAction() }

        controlsCard = makeControlsCard()
        controlsCard.isHidden = true
        folderPicker = makeFolderPicker()
        folderPicker.isHidden = true

        for v: NSView in [mascot, headline, body, progressBar, progressLabel,
                          controlsCard, folderPicker,
                          primaryButton, secondaryButton, tertiaryButton] {
            v.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(v)
        }
        NSLayoutConstraint.activate([
            mascot.topAnchor.constraint(equalTo: content.topAnchor, constant: 30),
            mascot.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            mascot.widthAnchor.constraint(equalToConstant: 120),
            mascot.heightAnchor.constraint(equalToConstant: 120),

            headline.topAnchor.constraint(equalTo: mascot.bottomAnchor, constant: 20),
            headline.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 30),
            headline.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -30),

            body.topAnchor.constraint(equalTo: headline.bottomAnchor, constant: 10),
            body.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 44),
            body.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -44),

            progressBar.topAnchor.constraint(equalTo: body.bottomAnchor, constant: 18),
            progressBar.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 60),
            progressBar.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -60),

            progressLabel.topAnchor.constraint(equalTo: progressBar.bottomAnchor, constant: 6),
            progressLabel.centerXAnchor.constraint(equalTo: content.centerXAnchor),

            controlsCard.topAnchor.constraint(equalTo: body.bottomAnchor, constant: 18),
            controlsCard.centerXAnchor.constraint(equalTo: content.centerXAnchor),

            folderPicker.topAnchor.constraint(equalTo: body.bottomAnchor, constant: 22),
            folderPicker.centerXAnchor.constraint(equalTo: content.centerXAnchor),

            primaryButton.bottomAnchor.constraint(equalTo: secondaryButton.topAnchor, constant: -10),
            primaryButton.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            primaryButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 230),

            secondaryButton.bottomAnchor.constraint(equalTo: tertiaryButton.topAnchor, constant: -8),
            secondaryButton.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            secondaryButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 230),

            tertiaryButton.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -20),
            tertiaryButton.centerXAnchor.constraint(equalTo: content.centerXAnchor),
        ])
    }

    // MARK: - Two-folder picker (folder step)

    private func makeFolderPicker() -> NSView {
        let card = NSView()
        func title(_ s: String) -> NSTextField {
            let t = NSTextField(labelWithString: s)
            t.font = .systemFont(ofSize: 13, weight: .semibold)
            t.translatesAutoresizingMaskIntoConstraints = false
            return t
        }
        let gbTitle = title("Game Boy")
        let gbcTitle = title("Game Boy Color")
        for l in [gbPathLabel, gbcPathLabel] {
            l.font = .systemFont(ofSize: 11)
            l.textColor = .secondaryLabelColor
            l.lineBreakMode = .byTruncatingMiddle
            l.translatesAutoresizingMaskIntoConstraints = false
        }
        gbChooseButton.onClick = { [weak self] in self?.chooseFolderRow(.gb) }
        gbcChooseButton.onClick = { [weak self] in self?.chooseFolderRow(.gbc) }
        gbChooseButton.translatesAutoresizingMaskIntoConstraints = false
        gbcChooseButton.translatesAutoresizingMaskIntoConstraints = false

        for v in [gbTitle, gbcTitle, gbPathLabel, gbcPathLabel,
                  gbChooseButton, gbcChooseButton] {
            card.addSubview(v)
        }
        NSLayoutConstraint.activate([
            card.widthAnchor.constraint(equalToConstant: 384),

            gbTitle.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            gbTitle.topAnchor.constraint(equalTo: card.topAnchor, constant: 2),
            gbTitle.widthAnchor.constraint(equalToConstant: 132),
            gbChooseButton.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            gbChooseButton.centerYAnchor.constraint(equalTo: gbTitle.centerYAnchor),
            gbPathLabel.leadingAnchor.constraint(equalTo: gbTitle.trailingAnchor, constant: 6),
            gbPathLabel.trailingAnchor.constraint(
                lessThanOrEqualTo: gbChooseButton.leadingAnchor, constant: -8),
            gbPathLabel.centerYAnchor.constraint(equalTo: gbTitle.centerYAnchor),

            gbcTitle.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            gbcTitle.topAnchor.constraint(equalTo: gbTitle.bottomAnchor, constant: 18),
            gbcTitle.widthAnchor.constraint(equalToConstant: 132),
            gbcChooseButton.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            gbcChooseButton.centerYAnchor.constraint(equalTo: gbcTitle.centerYAnchor),
            gbcPathLabel.leadingAnchor.constraint(equalTo: gbcTitle.trailingAnchor, constant: 6),
            gbcPathLabel.trailingAnchor.constraint(
                lessThanOrEqualTo: gbcChooseButton.leadingAnchor, constant: -8),
            gbcPathLabel.centerYAnchor.constraint(equalTo: gbcTitle.centerYAnchor),

            card.bottomAnchor.constraint(equalTo: gbcChooseButton.bottomAnchor),
        ])
        return card
    }

    private func refreshFolderRows() {
        gbPathLabel.stringValue = gbFolder?.lastPathComponent ?? "Not set"
        gbcPathLabel.stringValue = gbcFolder?.lastPathComponent ?? "Not set"
        gbChooseButton.title = gbFolder == nil ? "Choose…" : "Change"
        gbcChooseButton.title = gbcFolder == nil ? "Choose…" : "Change"
    }

    private func chooseFolderRow(_ system: ROMFolders.System) {
        guard let window else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = system == .gbc
            ? "Choose your Game Boy Color ROM folder"
            : "Choose your Game Boy ROM folder"
        panel.prompt = "Use This Folder"
        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .OK, let url = panel.url else { return }
            if system == .gb { self.gbFolder = url } else { self.gbcFolder = url }
            self.refreshFolderRows()
            if self.step == .folder {
                self.primaryButton.isEnabled = self.gbFolder != nil || self.gbcFolder != nil
            }
        }
    }

    // MARK: - Controls recap card (done step)

    private func makeControlsCard() -> NSView {
        let rows: [(String, String)] = [
            ("← ↑ ↓ →", "D-pad"),
            ("Z / X", "A / B buttons"),
            ("Return / Shift", "Start / Select"),
            ("Space", "Pause"),
            ("⌘1–5", "Save state  ·  ⇧⌘1–5 to load"),
            ("🎮", "Controllers pair over Bluetooth"),
        ]
        let card = NSView()
        var previous: NSView?
        for (key, desc) in rows {
            let chip = NSBox()
            chip.boxType = .custom
            chip.cornerRadius = 6
            chip.fillColor = NSColor.labelColor.withAlphaComponent(0.08)
            chip.borderColor = NSColor.separatorColor
            chip.borderWidth = 1
            chip.contentViewMargins = .zero

            let keyLabel = NSTextField(labelWithString: key)
            keyLabel.font = .monospacedSystemFont(ofSize: 11, weight: .medium)
            keyLabel.alignment = .center
            keyLabel.translatesAutoresizingMaskIntoConstraints = false
            chip.contentView?.addSubview(keyLabel)

            let descLabel = NSTextField(labelWithString: desc)
            descLabel.font = .systemFont(ofSize: 12)
            descLabel.textColor = .secondaryLabelColor

            chip.translatesAutoresizingMaskIntoConstraints = false
            descLabel.translatesAutoresizingMaskIntoConstraints = false
            card.addSubview(chip)
            card.addSubview(descLabel)

            NSLayoutConstraint.activate([
                keyLabel.centerXAnchor.constraint(equalTo: chip.centerXAnchor),
                keyLabel.centerYAnchor.constraint(equalTo: chip.centerYAnchor),
                keyLabel.leadingAnchor.constraint(greaterThanOrEqualTo: chip.leadingAnchor, constant: 8),

                chip.leadingAnchor.constraint(equalTo: card.leadingAnchor),
                chip.widthAnchor.constraint(equalToConstant: 116),
                chip.heightAnchor.constraint(equalToConstant: 24),
                chip.topAnchor.constraint(
                    equalTo: previous?.bottomAnchor ?? card.topAnchor,
                    constant: previous == nil ? 0 : 8),

                descLabel.leadingAnchor.constraint(equalTo: chip.trailingAnchor, constant: 12),
                descLabel.centerYAnchor.constraint(equalTo: chip.centerYAnchor),
                descLabel.trailingAnchor.constraint(lessThanOrEqualTo: card.trailingAnchor),
            ])
            previous = chip
        }
        if let previous {
            card.bottomAnchor.constraint(equalTo: previous.bottomAnchor).isActive = true
        }
        card.widthAnchor.constraint(equalToConstant: 360).isActive = true
        return card
    }

    // MARK: - Estimates

    private static func estimateString(forGames count: Int) -> String {
        let secs = Double(count) * secondsPerGame
        if secs < 55 { return "under 1 min" }
        return "≈ \(Int((secs / 60).rounded(.up))) min"
    }

    private static func timeLeftString(_ seconds: TimeInterval) -> String {
        if seconds < 60 { return "under a minute left" }
        let mins = Int((seconds / 60).rounded(.up))
        return "about \(mins) min left"
    }

    private static func topByReviews(_ roms: [URL], limit: Int) -> [URL] {
        roms.compactMap { url in Popularity.score(for: url).map { (url, $0) } }
            .sorted { $0.1 > $1.1 }
            .prefix(limit)
            .map { $0.0 }
    }

    // Deduped ROMs across both configured folders
    private func unionRoms() -> [URL] {
        var seen = Set<String>()
        var out: [URL] = []
        for folder in [gbFolder, gbcFolder].compactMap({ $0 }) {
            for rom in ROMLoader.romFiles(in: folder) where seen.insert(rom.path).inserted {
                out.append(rom)
            }
        }
        return out
    }

    // MARK: - Steps

    private func apply(_ newStep: Step) {
        step = newStep
        progressBar.isHidden = true
        progressLabel.isHidden = true
        secondaryButton.isHidden = true
        tertiaryButton.isHidden = true
        controlsCard.isHidden = true
        folderPicker.isHidden = true

        switch newStep {
        case .welcome:
            headline.stringValue = "Hi, I'm T3d!"
            body.stringValue = """
            Welcome to T3d Boy, your Game Boy and \
            Game Boy Color emulator. I'll get you set up in under a minute.
            """
            primaryButton.title = "Let's go"

        case .folder:
            headline.stringValue = "Where do your games live?"
            body.stringValue = """
            Pick a folder for each system — or the same folder for both if \
            your games live together. You can change these any time from the library.
            """
            folderPicker.isHidden = false
            refreshFolderRows()
            primaryButton.title = "Continue"
            primaryButton.isEnabled = gbFolder != nil || gbcFolder != nil

        case .artPrompt:
            let roms = unionRoms()
            let missingAll = ThumbnailStore.shared.missingCount(for: roms)
            let top = Self.topByReviews(roms, limit: 100)
            let missingTop = ThumbnailStore.shared.missingCount(for: top)

            if missingAll == 0 {
                headline.stringValue = "Box art is all set!"
                body.stringValue = "All \(roms.count) games already have artwork."
                primaryButton.title = "Continue"
                primaryButton.isEnabled = true
                return
            }
            headline.stringValue = "Want box art for your games?"
            body.stringValue = """
            I found \(roms.count) games — \(missingAll) still need box art. \
            I make it by booting each game and photographing its title screen. \
            Start with the best-reviewed classics, or do everything now.
            """
            primaryButton.title =
                "Scan Top \(top.count) by Reviews  (\(Self.estimateString(forGames: missingTop)))"
            primaryButton.isEnabled = missingTop > 0
            secondaryButton.title =
                "Scan All \(missingAll) Games  (\(Self.estimateString(forGames: missingAll)))"
            secondaryButton.isHidden = false
            tertiaryButton.title = "Later — make art as I browse"
            tertiaryButton.isHidden = false

        case .scanning:
            headline.stringValue = "Generating box art…"
            body.stringValue = "Booting every game and snapping its title screen."
            progressBar.isHidden = false
            progressLabel.isHidden = false
            progressLabel.stringValue = "Starting…"
            primaryButton.title = "Cancel"

        case .done:
            headline.stringValue = "You're all set!"
            body.stringValue = mode == .scanOnly
                ? "Art is ready. While you're here, a quick refresher:"
                : "Here's everything you need to know:"
            controlsCard.isHidden = false
            primaryButton.title = mode == .scanOnly ? "Done" : "Open My Library"
        }
    }

    private func primaryAction() {
        switch step {
        case .welcome:
            apply(.folder)
        case .folder:
            if let gbFolder { ROMFolders.setFolder(gbFolder, for: .gb) }
            if let gbcFolder { ROMFolders.setFolder(gbcFolder, for: .gbc) }
            onFoldersChanged?()
            apply(.artPrompt)
        case .artPrompt:
            if primaryButton.title == "Continue" {
                apply(.done)
            } else {
                startScan(scope: .top100)
            }
        case .scanning:
            ThumbnailStore.shared.cancelGeneration()
            primaryButton.isEnabled = false // completion handler closes the step
        case .done:
            close()
        }
    }

    private func secondaryAction() {
        if step == .artPrompt { startScan(scope: .all) }
    }

    private func tertiaryAction() {
        if step == .artPrompt { apply(.done) }
    }

    private func startScan(scope: ScanScope) {
        apply(.scanning)
        scanStart = Date()
        var roms = unionRoms()
        if scope == .top100 { roms = Self.topByReviews(roms, limit: 100) }

        ThumbnailStore.shared.generateMissing(for: roms) { [weak self] done, total in
            guard let self else { return }
            self.progressBar.maxValue = Double(total)
            self.progressBar.doubleValue = Double(done)
            var text = "\(done) / \(total)"
            let elapsed = Date().timeIntervalSince(self.scanStart)
            if done >= 5, elapsed > 3, done < total {
                let rate = Double(done) / elapsed
                let remaining = Double(total - done) / max(rate, 0.001)
                text += "  ·  " + Self.timeLeftString(remaining)
            }
            self.progressLabel.stringValue = text
        } completion: { [weak self] _ in
            guard let self else { return }
            self.primaryButton.isEnabled = true
            self.apply(.done)
        }
    }

    func windowWillClose(_ notification: Notification) {
        ThumbnailStore.shared.cancelGeneration()
        onFinished?()
    }
}
