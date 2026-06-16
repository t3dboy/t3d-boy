// T3d Boy — the "new version available" popup, fronted by T3d the mascot.
//
// Shows the latest release's name + changelog with three choices: Download (opens the
// .dmg, or the release page if there's no asset), Ignore for Now (asks again next
// launch), or Skip This Version (stops reminders for that one release — future
// releases still notify). Themed to match the rest of the app.

import Cocoa

final class UpdatePromptWindowController: NSWindowController {
    private let release: UpdateChecker.Release
    /// Called once the user dismisses the prompt (any of the three actions, or close).
    var onClose: (() -> Void)?

    init(release: UpdateChecker.Release) {
        self.release = release
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 560),
            styleMask: [.titled, .closable],
            backing: .buffered, defer: false)
        window.title = theme.cased("Update Available")
        window.isRestorable = false
        super.init(window: window)
        window.delegate = self
        window.backgroundColor = theme.surfaceWindow
        buildUI()
        window.center()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func buildUI() {
        guard let content = window?.contentView else { return }

        let mascot = MascotView(frame: .zero)

        let headline = NSTextField(labelWithString: theme.cased("A new version is available"))
        headline.font = theme.skinned ? .rounded(20, .bold) : .systemFont(ofSize: 20, weight: .bold)
        headline.textColor = theme.textPrimary
        headline.alignment = .center

        let sub = NSTextField(labelWithString: theme.cased(
            "You're on \(UpdateChecker.currentVersion) · \(release.version) is ready"))
        sub.font = theme.fontCaption
        sub.textColor = theme.textSecondary
        sub.alignment = .center

        // Changelog: read-only, scrollable, themed.
        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 12, height: 10)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                  height: CGFloat.greatestFiniteMagnitude)
        // NSTextView's default container already tracks width, so the notes wrap.
        textView.string = prettifiedNotes(release.notes)
        textView.font = theme.fontBody
        textView.textColor = theme.textSecondary

        let scroll = NSScrollView()
        scroll.documentView = textView
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false

        let card = NSView()
        card.wantsLayer = true
        card.layer?.backgroundColor = theme.surfacePanel.cgColor
        card.layer?.cornerRadius = 12
        card.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: card.topAnchor, constant: 4),
            scroll.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -4),
            scroll.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 6),
            scroll.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -6),
        ])

        let download = CapsuleButton(title: theme.cased("Download"), style: .prominent)
        download.onClick = { [weak self] in self?.download() }
        let later = CapsuleButton(title: theme.cased("Ignore for Now"),
                                  style: .neutral, fontSize: 12, height: 30)
        later.onClick = { [weak self] in self?.finish() }
        let skip = CapsuleButton(title: theme.cased("Stop Reminding Me About This Version"),
                                 style: .neutral, fontSize: 11, height: 26)
        skip.onClick = { [weak self] in self?.skip() }

        for v: NSView in [mascot, headline, sub, card, download, later, skip] {
            v.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(v)
        }

        NSLayoutConstraint.activate([
            mascot.topAnchor.constraint(equalTo: content.topAnchor, constant: 26),
            mascot.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            mascot.widthAnchor.constraint(equalToConstant: 96),
            mascot.heightAnchor.constraint(equalToConstant: 96),

            headline.topAnchor.constraint(equalTo: mascot.bottomAnchor, constant: 16),
            headline.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            headline.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),

            sub.topAnchor.constraint(equalTo: headline.bottomAnchor, constant: 6),
            sub.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            sub.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),

            card.topAnchor.constraint(equalTo: sub.bottomAnchor, constant: 16),
            card.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            card.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            card.bottomAnchor.constraint(equalTo: download.topAnchor, constant: -18),

            download.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            download.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            download.bottomAnchor.constraint(equalTo: later.topAnchor, constant: -8),

            later.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            later.bottomAnchor.constraint(equalTo: skip.topAnchor, constant: -4),

            skip.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            skip.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -18),
        ])
    }

    /// Light markdown → plain prettify so release notes read cleanly in a plain text view:
    /// drop heading hashes, normalise bullets, strip bold/code markers.
    private func prettifiedNotes(_ md: String) -> String {
        let cleaned = md
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "`", with: "")
        let lines = cleaned.components(separatedBy: "\n").map { line -> String in
            var t = line.trimmingCharacters(in: .whitespaces)
            while t.hasPrefix("#") { t.removeFirst() }
            t = t.trimmingCharacters(in: .whitespaces)
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("- ")
                || line.trimmingCharacters(in: .whitespaces).hasPrefix("* ") {
                return "  •  " + String(t.dropFirst(2))
            }
            return t
        }
        let out = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return out.isEmpty ? "See the release page for what's new." : out
    }

    // MARK: - Actions

    private func download() {
        NSWorkspace.shared.open(release.dmgURL ?? release.pageURL)
        finish()
    }

    private func skip() {
        UpdateChecker.skippedVersion = release.version
        finish()
    }

    private func finish() {
        onClose?()
        onClose = nil
        window?.close()
    }
}

extension UpdatePromptWindowController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        onClose?()
        onClose = nil
    }
}
