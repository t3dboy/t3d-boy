// T3d Boy — game window: emulator view, keyboard input, frame timer,
// audio output, pause, save states

import AVFoundation
import Cocoa
import CryptoKit

final class EmulatorView: NSView {
    var joypad: Joypad?

    // Hardcore dim + Worm Light overlays — confined to THIS view (the Game Boy
    // screen), never the rest of the display. The worm-light *angle* is adjusted
    // on the library artwork, not here, so gameplay stays uncluttered.
    private var effects: ScreenEffects!

    override var acceptsFirstResponder: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.magnificationFilter = .nearest
        layer?.backgroundColor = NSColor(srgbRed: 0.61, green: 0.74, blue: 0.06, alpha: 1).cgColor
        effects = ScreenEffects(host: layer!)
        effects.layout(bounds)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        effects.layout(bounds)
    }

    func applyEffects(dim: Float, worm: Bool) {
        effects.apply(dimOpacity: dim, wormOn: worm)
    }

    func present(_ framebuffer: [UInt32]) {
        layer?.contents = makeImage(from: framebuffer)
    }

    override func keyDown(with event: NSEvent) {
        if event.isARepeat { return }
        if event.keyCode == 49 { // Space = pause
            NSApp.sendAction(#selector(GameWindowController.togglePause(_:)), to: nil, from: self)
            return
        }
        if !handle(event.keyCode, pressed: true) { super.keyDown(with: event) }
    }
    override func keyUp(with event: NSEvent) {
        if event.keyCode == 49 { return }
        if !handle(event.keyCode, pressed: false) { super.keyUp(with: event) }
    }
    override func flagsChanged(with event: NSEvent) {
        // Shift = Select
        joypad?.set(.selectBtn, pressed: event.modifierFlags.contains(.shift))
    }

    private func handle(_ keyCode: UInt16, pressed: Bool) -> Bool {
        guard let joypad else { return false }
        switch keyCode {
        case 123: joypad.set(.left, pressed: pressed)
        case 124: joypad.set(.right, pressed: pressed)
        case 125: joypad.set(.down, pressed: pressed)
        case 126: joypad.set(.up, pressed: pressed)
        case 6:   joypad.set(.a, pressed: pressed) // Z key
        case 7:   joypad.set(.b, pressed: pressed) // X key
        case 36, 76: joypad.set(.start, pressed: pressed) // Return / Enter
        default: return false
        }
        return true
    }
}

final class GameWindowController: NSWindowController, NSWindowDelegate, NSMenuItemValidation {
    private let gb: GameBoy
    private let emulatorView: EmulatorView
    private var frameTimer: Timer?
    private var audioEngine: AVAudioEngine?
    private let baseTitle: String
    private let romHash: String
    private let romURL: URL
    private var paused = false
    private var bootFrame = 0
    private var bootDone = false
    private var sessionStart: Date?
    private var framesSinceFlush = 0
    private var hardcoreFrameCounter = 0
    var onClose: (() -> Void)?

    init(rom: [UInt8], title: String, url: URL) {
        gb = GameBoy(rom: rom)
        romURL = url
        baseTitle = "T3d Boy — \(title)"
        romHash = Insecure.MD5.hash(data: Data(rom))
            .map { String(format: "%02x", $0) }.joined()

        let scale: CGFloat = 4
        let rect = NSRect(x: 0, y: 0, width: 160 * scale, height: 144 * scale)
        emulatorView = EmulatorView(frame: rect)

        let window = NSWindow(
            contentRect: rect,
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered, defer: false)
        window.title = baseTitle
        window.contentView = emulatorView
        super.init(window: window)

        window.delegate = self
        window.center()
        emulatorView.joypad = gb.mmu.joypad

        PlayStats.shared.recordPlay(url)
        startTimer()
        startAudio()
        applyEffects() // apply current dim/worm-light immediately on open

        // Toggling either effect (from any window or the menu) updates this window
        NotificationCenter.default.addObserver(
            forName: .screenEffectsChanged, object: nil, queue: .main
        ) { [weak self] _ in self?.applyEffects() }
    }
    required init?(coder: NSCoder) { fatalError() }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        window?.makeFirstResponder(emulatorView)
    }

    private func startTimer() {
        sessionStart = Date()
        let timer = Timer(timeInterval: 1.0 / 59.73, repeats: true) { [weak self] _ in
            guard let self else { return }
            if self.bootDone {
                self.gb.runFrame()
                self.emulatorView.present(self.gb.mmu.ppu.framebuffer)
            } else {
                self.tickBoot()
            }
            self.framesSinceFlush += 1
            if self.framesSinceFlush >= 1800 { // ~30s: persist play time
                self.flushPlaytime(stop: false)
            }
            self.hardcoreFrameCounter += 1
            if self.hardcoreFrameCounter >= 30 { // ~2 Hz: re-read ambient light
                self.hardcoreFrameCounter = 0
                self.applyEffects()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        frameTimer = timer
    }

    // MARK: - Screen effects (Hardcore dim + Worm Light), emulator-only

    private func applyEffects() {
        let dim = Hardcore.isEnabled ? Hardcore.currentDimOpacity() : 0
        emulatorView.applyEffects(dim: dim, worm: WormLight.isEnabled)
    }

    @objc func toggleHardcore(_ sender: Any?) {
        Hardcore.isEnabled.toggle() // notification re-applies to all windows
    }

    @objc func toggleWormLight(_ sender: Any?) {
        WormLight.isEnabled.toggle()
    }

    private func flushPlaytime(stop: Bool) {
        framesSinceFlush = 0
        if let start = sessionStart {
            PlayStats.shared.addTime(romURL, seconds: Date().timeIntervalSince(start))
        }
        sessionStart = stop ? nil : Date()
    }

    private func tickBoot() {
        let apu = gb.mmu.apu
        BootScreen.dingStep(apu, bootFrame: bootFrame)
        apu.step(GameBoy.cyclesPerFrame) // generate the chime's audio samples
        apu.flush()
        emulatorView.present(BootScreen.frame(bootFrame, cgb: gb.cgb))
        bootFrame += 1
        if bootFrame >= BootScreen.totalFrames { bootDone = true }
    }

    private func startAudio() {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: APU.sampleRate,
                                         channels: 2) else { return }
        let ring = gb.mmu.apu.ring
        let engine = AVAudioEngine()
        let source = AVAudioSourceNode(format: format) { _, _, frameCount, abl -> OSStatus in
            let bufs = UnsafeMutableAudioBufferListPointer(abl)
            guard bufs.count >= 2,
                  let l = bufs[0].mData?.assumingMemoryBound(to: Float.self),
                  let r = bufs[1].mData?.assumingMemoryBound(to: Float.self) else { return noErr }
            ring.readDeinterleaved(left: l, right: r, frames: Int(frameCount))
            return noErr
        }
        engine.attach(source)
        engine.connect(source, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = 1.0
        do {
            try engine.start()
            audioEngine = engine
        } catch {
            audioEngine = nil // no audio device; play silently
        }
    }

    func windowWillClose(_ notification: Notification) {
        flushPlaytime(stop: true)
        frameTimer?.invalidate()
        frameTimer = nil
        audioEngine?.stop()
        audioEngine = nil
        if GamepadManager.shared.joypad === gb.mmu.joypad {
            GamepadManager.shared.joypad = nil
        }
        onClose?()
    }

    // The frontmost game window owns the controller
    func windowDidBecomeKey(_ notification: Notification) {
        GamepadManager.shared.joypad = gb.mmu.joypad
        updateControllerStatus()
    }

    func updateControllerStatus() {
        if let name = GamepadManager.shared.currentControllerName {
            window?.subtitle = "🎮 \(name)"
        } else {
            window?.subtitle = ""
        }
    }

    // MARK: - Pause

    @objc func togglePause(_ sender: Any?) {
        paused.toggle()
        if paused {
            flushPlaytime(stop: true) // paused time doesn't count as play time
            frameTimer?.invalidate()
            frameTimer = nil
            audioEngine?.pause()
            window?.title = "⏸ " + baseTitle
        } else {
            startTimer()
            try? audioEngine?.start()
            window?.title = baseTitle
        }
    }

    // MARK: - Save states

    private func stateURL(slot: Int) -> URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory,
                                           in: .userDomainMask)[0]
            .appendingPathComponent("T3d Boy/SaveStates/\(romHash)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("slot\(slot).t3dstate")
    }

    @objc func saveState(_ sender: NSMenuItem) {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        do {
            let data = try encoder.encode(gb.snapshot())
            try data.write(to: stateURL(slot: sender.tag))
        } catch {
            NSSound.beep()
        }
    }

    @objc func loadState(_ sender: NSMenuItem) {
        guard let data = try? Data(contentsOf: stateURL(slot: sender.tag)),
              let snap = try? PropertyListDecoder().decode(Snapshot.self, from: data) else {
            NSSound.beep()
            return
        }
        gb.restore(snap)
        bootDone = true // loading a state skips any boot animation in progress
        emulatorView.present(gb.mmu.ppu.framebuffer)
    }

    // MARK: - Menu validation (slot timestamps, pause/resume title)

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(togglePause(_:)):
            menuItem.title = paused ? "Resume" : "Pause"
            return true
        case #selector(toggleHardcore(_:)):
            menuItem.state = Hardcore.isEnabled ? .on : .off
            return true
        case #selector(toggleWormLight(_:)):
            menuItem.state = WormLight.isEnabled ? .on : .off
            return true
        case #selector(saveState(_:)), #selector(loadState(_:)):
            let url = stateURL(slot: menuItem.tag)
            let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
            if let date = attrs?[.modificationDate] as? Date {
                let fmt = DateFormatter()
                fmt.dateStyle = .short
                fmt.timeStyle = .short
                menuItem.title = "Slot \(menuItem.tag) — \(fmt.string(from: date))"
            } else {
                menuItem.title = "Slot \(menuItem.tag)" +
                    (menuItem.action == #selector(loadState(_:)) ? " — empty" : "")
            }
            return menuItem.action == #selector(saveState(_:))
                || FileManager.default.fileExists(atPath: url.path)
        default:
            return true
        }
    }
}
