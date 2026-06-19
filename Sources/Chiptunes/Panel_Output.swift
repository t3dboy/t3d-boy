// T3d Boy — T3d Tunes "Visual" panel: live oscilloscope, the WAVE channel's wavetable
// editor, and a real-time WAV export of the live FX'd output.
//
// Three sections, left-to-right: a 30 fps oscilloscope of the engine's most-recent output;
// a draggable 32-bar editor for the wave channel's 16-byte table (with Sine/Saw/Square
// presets); and an "Export WAV…" button that records one loop of the live output to disk.

import Cocoa
import AVFoundation
import UniformTypeIdentifiers

// MARK: - Tiny caption helper

/// The panel's standard 8pt muted monospace caption.
private func panelCaption(_ t: String) -> NSTextField {
    let label = NSTextField(labelWithString: theme.cased(t))
    label.font = .monospacedSystemFont(ofSize: 8, weight: .medium)
    label.textColor = theme.textMuted
    label.alignment = .left
    label.setAccessibilityElement(false)
    label.translatesAutoresizingMaskIntoConstraints = false
    return label
}

// MARK: - Oscilloscope

/// A self-driving waveform view: polls `engine.snapshotScope()` on a ~30 fps timer and draws
/// the samples as a centred polyline. The timer only runs while the view is in a window and
/// visible, and is invalidated in `deinit`.
final class ScopeView: NSView {
    private let engine: ChiptuneEngine
    private var timer: Timer?

    init(engine: ChiptuneEngine) {
        self.engine = engine
        super.init(frame: .zero)
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
    }
    required init?(coder: NSCoder) { fatalError() }

    deinit { timer?.invalidate() }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateTimer()
    }
    override var isHidden: Bool { didSet { updateTimer() } }

    private func updateTimer() {
        let shouldRun = window != nil && !isHidden
        if shouldRun, timer == nil {
            let t = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
                self?.needsDisplay = true
            }
            RunLoop.main.add(t, forMode: .common)
            timer = t
        } else if !shouldRun {
            timer?.invalidate(); timer = nil
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        let r = bounds
        let radius = theme.radiusSmall
        // Screen housing.
        let bg = NSBezierPath(roundedRect: r.insetBy(dx: 0.5, dy: 0.5), xRadius: radius, yRadius: radius)
        theme.surfaceScreen.setFill(); bg.fill()
        theme.controlEdge.setStroke(); bg.lineWidth = 1; bg.stroke()

        let samples = engine.snapshotScope()
        guard samples.count > 1, r.width > 2, r.height > 2 else { return }

        let inset: CGFloat = 4
        let plot = r.insetBy(dx: inset, dy: inset)
        let midY = plot.midY
        let halfH = plot.height / 2

        // Centre line.
        let centre = NSBezierPath()
        centre.move(to: NSPoint(x: plot.minX, y: midY))
        centre.line(to: NSPoint(x: plot.maxX, y: midY))
        theme.controlEdge.withAlphaComponent(0.5).setStroke()
        centre.lineWidth = 0.5; centre.stroke()

        // Waveform polyline.
        let wave = NSBezierPath()
        let n = samples.count
        for i in 0 ..< n {
            let x = plot.minX + plot.width * CGFloat(i) / CGFloat(n - 1)
            let v = CGFloat(max(-1, min(1, samples[i])))
            let y = midY + v * halfH
            if i == 0 { wave.move(to: NSPoint(x: x, y: y)) }
            else { wave.line(to: NSPoint(x: x, y: y)) }
        }
        theme.accent.setStroke()
        wave.lineWidth = 1.5
        wave.lineJoinStyle = .round
        wave.stroke()
    }
}

// MARK: - Wavetable editor

/// A 32-bar editor for the WAVE lane's table. Reads `engine.wavetable(lane: 2)` (16 bytes =
/// 32 four-bit samples), lets you draw bar heights by dragging, repacks and writes them back.
final class WavetableEditor: NSView {
    private let engine: ChiptuneEngine
    private let onChange: () -> Void
    private var samples = [Int](repeating: 0, count: 32) // 0…15 each
    private static let lane = 2

    init(engine: ChiptuneEngine, onChange: @escaping () -> Void) {
        self.engine = engine
        self.onChange = onChange
        super.init(frame: .zero)
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        reload()
    }
    required init?(coder: NSCoder) { fatalError() }

    /// Pull the current table from the engine into the local sample buffer.
    func reload() {
        let bytes = engine.wavetable(lane: Self.lane)
        guard bytes.count == 16 else { return }
        for i in 0 ..< 16 {
            samples[i * 2]     = Int(bytes[i] >> 4) & 0x0F   // high nibble = even sample
            samples[i * 2 + 1] = Int(bytes[i]) & 0x0F        // low nibble  = odd sample
        }
        needsDisplay = true
    }

    /// Repack the 32 four-bit samples into 16 bytes and push to the engine.
    private func commit() {
        var bytes = [UInt8](repeating: 0, count: 16)
        for i in 0 ..< 16 {
            let hi = UInt8(max(0, min(15, samples[i * 2])))
            let lo = UInt8(max(0, min(15, samples[i * 2 + 1])))
            bytes[i] = (hi << 4) | lo
        }
        engine.setWavetable(bytes, lane: Self.lane)
        onChange()
        needsDisplay = true
    }

    /// Overwrite the whole table from a 0…1 shape function and commit.
    private func fill(_ shape: (Int) -> Double) {
        for i in 0 ..< 32 {
            samples[i] = max(0, min(15, Int((shape(i) * 15).rounded())))
        }
        commit()
    }

    func loadSine()   { fill { (sin(2 * .pi * Double($0) / 32) + 1) / 2 } }
    func loadSaw()    { fill { Double($0) / 31 } }
    func loadSquare() { fill { $0 < 16 ? 1 : 0 } }

    // Drawing the bar under the cursor.

    override func mouseDown(with event: NSEvent) { paint(event) }
    override func mouseDragged(with event: NSEvent) { paint(event) }

    private func paint(_ event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        guard bounds.width > 0, bounds.height > 1 else { return }
        let idx = max(0, min(31, Int(p.x / (bounds.width / 32))))
        let v = max(0, min(15, Int((p.y / bounds.height * 16).rounded(.down))))
        guard samples[idx] != v else { return }
        samples[idx] = v
        commit()
    }

    override func draw(_ dirtyRect: NSRect) {
        let r = bounds
        let radius = theme.radiusSmall
        let bg = NSBezierPath(roundedRect: r.insetBy(dx: 0.5, dy: 0.5), xRadius: radius, yRadius: radius)
        theme.surfaceInset.setFill(); bg.fill()
        theme.controlEdge.setStroke(); bg.lineWidth = 1; bg.stroke()

        guard r.width > 2, r.height > 2 else { return }
        let pad: CGFloat = 3
        let plot = r.insetBy(dx: pad, dy: pad)
        let barW = plot.width / 32
        let tint = voiceColor(.wave)
        for i in 0 ..< 32 {
            let h = plot.height * CGFloat(samples[i] + 1) / 16
            let x = plot.minX + CGFloat(i) * barW
            let bar = NSRect(x: x + 0.5, y: plot.minY, width: barW - 1, height: h)
            let path = NSBezierPath(roundedRect: bar, xRadius: 1, yRadius: 1)
            tint.withAlphaComponent(0.85).setFill()
            path.fill()
        }
    }
}

// MARK: - Output panel

final class OutputPanel: NSView {
    private let engine: ChiptuneEngine
    private let onChange: () -> Void

    private let editor: WavetableEditor
    private let exportButton = CapsuleButton(title: "Export WAV…", style: .neutral, fontSize: 13, height: 30)

    // Export state.
    private var exporting = false
    private var exportFile: AVAudioFile?
    private var exportURL: URL?

    init(engine: ChiptuneEngine, onChange: @escaping () -> Void) {
        self.engine = engine
        self.onChange = onChange
        self.editor = WavetableEditor(engine: engine, onChange: onChange)
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        build()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func build() {
        // --- Section captions --- (the live scope lives persistently to the right of the panels)
        let waveCap = panelCaption("Wave (ch3) — drag to draw")
        let exportCap = panelCaption("Export")

        // --- Wavetable editor + presets ---
        editor.setAccessibilityLabel("Wave channel wavetable. Drag to draw the waveform")

        let sineBtn = CapsuleButton(title: "Sine", style: .neutral, fontSize: 11, height: 24)
        let sawBtn = CapsuleButton(title: "Saw", style: .neutral, fontSize: 11, height: 24)
        let sqrBtn = CapsuleButton(title: "Square", style: .neutral, fontSize: 11, height: 24)
        sineBtn.onClick = { [weak self] in self?.editor.loadSine() }
        sawBtn.onClick = { [weak self] in self?.editor.loadSaw() }
        sqrBtn.onClick = { [weak self] in self?.editor.loadSquare() }
        let presets = NSStackView(views: [sineBtn, sawBtn, sqrBtn])
        presets.orientation = .horizontal
        presets.alignment = .centerY
        presets.distribution = .fillEqually
        presets.spacing = 8
        presets.translatesAutoresizingMaskIntoConstraints = false

        // --- Export ---
        exportButton.onClick = { [weak self] in self?.beginExport() }

        for v in [waveCap, exportCap, editor, presets, exportButton] {
            v.translatesAutoresizingMaskIntoConstraints = false
            addSubview(v)
        }

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 210),

            // Wavetable section (left). 16pt insets; caption above a 340×150 editor + presets.
            waveCap.topAnchor.constraint(equalTo: topAnchor, constant: 16),
            waveCap.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            editor.topAnchor.constraint(equalTo: waveCap.bottomAnchor, constant: 6),
            editor.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            editor.widthAnchor.constraint(equalToConstant: 340),
            editor.heightAnchor.constraint(equalToConstant: 150),
            presets.topAnchor.constraint(equalTo: editor.bottomAnchor, constant: 6),
            presets.leadingAnchor.constraint(equalTo: editor.leadingAnchor),
            presets.trailingAnchor.constraint(equalTo: editor.trailingAnchor),
            presets.heightAnchor.constraint(equalToConstant: 24),

            // Export section (right). ~30pt gap after the editor; caption above the button.
            exportCap.topAnchor.constraint(equalTo: topAnchor, constant: 16),
            exportCap.leadingAnchor.constraint(equalTo: editor.trailingAnchor, constant: 30),
            exportButton.topAnchor.constraint(equalTo: exportCap.bottomAnchor, constant: 6),
            exportButton.leadingAnchor.constraint(equalTo: editor.trailingAnchor, constant: 30),
            exportButton.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -16),
            exportButton.widthAnchor.constraint(equalToConstant: 140),
            exportButton.heightAnchor.constraint(equalToConstant: 30),
        ])
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // The wavetable may have changed via lane menus / harvest while hidden — refresh on show.
        if window != nil { editor.reload() }
    }

    // MARK: Export

    private func beginExport() {
        guard !exporting else { return }

        let panel = NSSavePanel()
        if let wav = UTType(filenameExtension: "wav") {
            panel.allowedContentTypes = [wav]
        }
        panel.nameFieldStringValue = "t3d-tunes.wav"
        panel.canCreateDirectories = true

        let finish: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard let self, response == .OK, let url = panel.url else { return }
            self.runExport(to: url)
        }
        if let win = window {
            panel.beginSheetModal(for: win, completionHandler: finish)
        } else {
            finish(panel.runModal())
        }
    }

    private func runExport(to url: URL) {
        engine.startAudioIfNeeded()

        // The output tap delivers stereo float at the chip's sample rate (the engine's audio
        // graph runs at APU.sampleRate). Create the file with that format so every captured
        // buffer is accepted, then write each one straight through in the tap callback (a
        // single writer thread, which AVAudioFile requires).
        guard let fmt = AVAudioFormat(standardFormatWithSampleRate: APU.sampleRate, channels: 2),
              let file = try? AVAudioFile(forWriting: url, settings: fmt.settings) else { return }

        exporting = true
        exportURL = url
        exportFile = file
        exportButton.title = "Recording…"

        engine.installOutputTap { [weak self] buf, _ in
            guard let self, self.exporting, let f = self.exportFile,
                  buf.floatChannelData != nil else { return }
            try? f.write(from: buf)
        }

        if !engine.isPlaying { engine.play() }

        // Record one loop (plus a small tail) then tear down.
        let dur = engine.loopSeconds + 0.3
        DispatchQueue.main.asyncAfter(deadline: .now() + dur) { [weak self] in
            self?.finishExport()
        }
    }

    private func finishExport() {
        guard exporting else { return }
        engine.removeOutputTap()
        exporting = false
        exportFile = nil // closes the file (ARC releases the AVAudioFile)
        exportURL = nil

        // Brief confirmation, restored after ~1.2s. asyncAfter's DispatchTime deadline is
        // monotonic (uptime-based), not wall-clock Date().
        exportButton.title = "Saved ✓"
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            guard let self, !self.exporting else { return }
            self.exportButton.title = "Export WAV…"
        }
    }
}
