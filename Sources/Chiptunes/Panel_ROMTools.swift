// T3d Boy — T3d Tunes "ROM" panel: cartridge-driven generative tools.
//
// Three sections, left-to-right under tiny synth captions:
//   1. Auto-compose — build a starter loop from this cartridge's harvested palette.
//   2. Sound-shuffle — per-lane, each hit grabs a random palette patch of that voice.
//   3. Mashup — open a 2nd game's ROM, sample it off the main thread, and blend its
//      sounds into the live palette (so the lanes/keyboard can play both games at once).
//
// Reads the active theme's tokens, matching the rest of the drawer (CapsuleButton,
// SettingToggle, voiceColor, mono-8 captions).

import Cocoa
import UniformTypeIdentifiers

final class ROMToolsPanel: NSView {
    private let engine: ChiptuneEngine
    private let onChange: () -> Void

    // Mashup state.
    private let mashStatus = NSTextField(labelWithString: "")
    private var mashButton: CapsuleButton!
    private var sampling = false
    private let mashQueue = DispatchQueue(label: "t3dboy.mashup")

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
        // --- 1. Auto-compose ---
        let composeBtn = CapsuleButton(title: "Auto-compose", style: .prominent, fontSize: 13, height: 32)
        composeBtn.onClick = { [weak self] in
            guard let self else { return }
            self.engine.autoCompose() // fires the grid redraw itself…
            self.onChange()           // …but keep the host in sync too.
        }
        composeBtn.widthAnchor.constraint(greaterThanOrEqualToConstant: 130).isActive = true
        let composeSection = section(
            caption: "Auto-compose",
            sub: "Builds a loop from this cartridge's sounds",
            content: composeBtn)

        // --- 2. Sound-shuffle (one tiny toggle per lane, tinted to its voice) ---
        var toggleRow: [NSView] = []
        for i in 0 ..< ChipVoice.allCases.count {
            let voice = ChipVoice(rawValue: i)!
            let toggle = SettingToggle()
            toggle.setAccessibilityName("\(voice.short) sound shuffle. Each hit grabs a random palette sound of this voice")
            toggle.isOn = engine.soundShuffle(lane: i)
            toggle.onToggle = { [weak self] on in self?.engine.setSoundShuffle(on, lane: i) }
            toggleRow.append(laneToggle(toggle, voice: voice))
        }
        let shuffleControls = NSStackView(views: toggleRow)
        shuffleControls.orientation = .horizontal
        shuffleControls.alignment = .bottom
        shuffleControls.spacing = 16
        let shuffleSection = section(
            caption: "Shuffle sounds",
            sub: "Each hit picks a random palette sound",
            content: shuffleControls)

        // --- 3. Two-ROM mashup ---
        let addBtn = CapsuleButton(title: "Add ROM…", style: .neutral, fontSize: 13, height: 32)
        addBtn.onClick = { [weak self] in self?.pickMashupROM() }
        addBtn.widthAnchor.constraint(greaterThanOrEqualToConstant: 130).isActive = true
        mashButton = addBtn
        mashStatus.font = .monospacedSystemFont(ofSize: 9, weight: .medium)
        mashStatus.textColor = theme.textMuted
        mashStatus.lineBreakMode = .byWordWrapping
        mashStatus.maximumNumberOfLines = 2
        mashStatus.setAccessibilityElement(false)
        mashStatus.widthAnchor.constraint(greaterThanOrEqualToConstant: 200).isActive = true
        let mashStack = NSStackView(views: [addBtn, mashStatus])
        mashStack.orientation = .vertical
        mashStack.alignment = .leading
        mashStack.spacing = 8
        let mashSection = section(
            caption: "Mashup — blend a 2nd game's sounds",
            sub: nil,
            content: mashStack)

        // --- Lay out the three sections with dividers between them, spread across the full
        // width (equal spacing) now that the panel spans the whole drawer. ---
        let columns = NSStackView(views: [composeSection, divider(), shuffleSection, divider(), mashSection])
        columns.orientation = .horizontal
        columns.alignment = .centerY
        columns.distribution = .equalSpacing
        columns.spacing = 30
        columns.translatesAutoresizingMaskIntoConstraints = false
        addSubview(columns)
        NSLayoutConstraint.activate([
            columns.topAnchor.constraint(greaterThanOrEqualTo: topAnchor, constant: 16),
            columns.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 40),
            columns.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -40),
            columns.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -16),
            columns.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    // MARK: Section helpers

    /// A captioned column: tiny mono caption, optional sub-caption, then the content view.
    private func section(caption title: String, sub: String?, content: NSView) -> NSView {
        let head = caption(title)
        var views: [NSView] = [head, content]
        if let sub {
            views.append(caption(sub, faint: true))
        }
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }

    /// The tiny synth-style caption used throughout the drawer (mono 9pt, muted).
    /// Wraps to two lines so headings/subtext are never truncated.
    private func caption(_ t: String, faint: Bool = false) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: theme.cased(t))
        label.font = .monospacedSystemFont(ofSize: 9, weight: .medium)
        label.textColor = faint ? theme.textFaint : theme.textMuted
        label.isSelectable = false
        label.maximumNumberOfLines = 2
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        label.widthAnchor.constraint(greaterThanOrEqualToConstant: 150).isActive = true
        label.setAccessibilityElement(false)
        return label
    }

    /// A sound-shuffle toggle with its voice's short name beneath, tinted to the voice colour.
    private func laneToggle(_ toggle: SettingToggle, voice: ChipVoice) -> NSView {
        let cap = NSTextField(labelWithString: theme.cased(voice.short))
        cap.font = .monospacedSystemFont(ofSize: 8, weight: .medium)
        cap.textColor = voiceColor(voice)
        cap.alignment = .center
        cap.setAccessibilityElement(false)
        let v = NSStackView(views: [toggle, cap])
        v.orientation = .vertical
        v.alignment = .centerX
        v.spacing = 2
        return v
    }

    /// A thin vertical hairline between sections.
    private func divider() -> NSView {
        let v = NSView()
        v.wantsLayer = true
        v.layer?.backgroundColor = theme.lineHair.cgColor
        v.translatesAutoresizingMaskIntoConstraints = false
        v.widthAnchor.constraint(equalToConstant: 1).isActive = true
        v.heightAnchor.constraint(equalToConstant: 140).isActive = true
        return v
    }

    // MARK: Mashup

    private func pickMashupROM() {
        guard !sampling else { return } // guard against re-entry while sampling

        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "Choose a 2nd game to blend its sounds into the palette."
        panel.prompt = "Add"
        if #available(macOS 11.0, *) {
            panel.allowedContentTypes = ["gb", "gbc", "zip"].compactMap { UTType(filenameExtension: $0) }
        } else {
            panel.allowedFileTypes = ["gb", "gbc", "zip"]
        }

        guard panel.runModal() == .OK, let url = panel.url else { return }

        sampling = true
        mashButton.isEnabled = false
        mashStatus.stringValue = theme.cased("Sampling…")

        let name = url.deletingPathExtension().lastPathComponent
        mashQueue.async { [weak self] in
            let patches = SoundHarvester.harvest(rom: url)
            DispatchQueue.main.async {
                guard let self else { return }
                self.sampling = false
                self.mashButton.isEnabled = true
                if patches.isEmpty {
                    self.mashStatus.stringValue = theme.cased("No sounds found in \(name)")
                    return
                }
                self.engine.setPalette(self.engine.palette + patches)
                self.mashStatus.stringValue = theme.cased("Added \(patches.count) sounds from \(name)")
                self.onChange()
            }
        }
    }
}
