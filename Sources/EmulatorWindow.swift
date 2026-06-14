// T3d Boy — game window: emulator view, keyboard input, frame timer,
// audio output, pause, save states

import AVFoundation
import Cocoa
import CryptoKit

final class EmulatorView: NSView {
    var joypad: Joypad?
    var onMouseMoved: (() -> Void)?   // host reveals the auto-hiding control bar

    // Hardcore dim + Worm Light overlays — confined to THIS view (the Game Boy
    // screen), never the rest of the display. The worm-light *angle* is adjusted
    // on the library artwork, not here, so gameplay stays uncluttered.
    private var effects: ScreenEffects!

    override var acceptsFirstResponder: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.magnificationFilter = .nearest
        // Scale the framebuffer to fit the view (pixel-perfect, aspect-preserved) so
        // the screen can grow to the focused play size, zoom, and go fullscreen.
        layer?.contentsGravity = .resizeAspect
        layer?.backgroundColor = NSColor.black.cgColor
        effects = ScreenEffects(host: layer!)
        effects.layout(bounds)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        effects.layout(bounds)
    }

    private var tracking: NSTrackingArea?
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = tracking { removeTrackingArea(t) }
        let t = NSTrackingArea(rect: bounds,
                               options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect],
                               owner: self)
        addTrackingArea(t); tracking = t
    }
    override func mouseMoved(with event: NSEvent) { onMouseMoved?() }

    func applyEffects(dim: Float, worm: Bool) {
        effects.apply(dimOpacity: dim, wormOn: worm)
    }

    private var previousFrame: [UInt32]?

    func present(_ framebuffer: [UInt32]) {
        // T3d LCD Real Feel: blend with the previous frame so flicker-based effects
        // resolve to a steady ~50% (per-byte average, no cross-channel overflow).
        if LCDGhosting.isEnabled, let prev = previousFrame, prev.count == framebuffer.count {
            var blended = [UInt32](repeating: 0, count: framebuffer.count)
            for i in 0 ..< framebuffer.count {
                let a = framebuffer[i], b = prev[i]
                blended[i] = (a & b) &+ (((a ^ b) >> 1) & 0x7F7F_7F7F)
            }
            layer?.contents = makeImage(from: blended)
        } else {
            layer?.contents = makeImage(from: framebuffer)
        }
        previousFrame = framebuffer
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
    private let rom: [UInt8]
    private let sourceRect: NSRect?   // box-art screen rect to zoom out of, if any
    private var dimWindow: NSWindow?  // dims everything behind the focused game
    // Achievements drawer (slides out to the right; widens the window)
    private let drawer = AchievementsDrawer()
    private let handle = DrawerHandle()
    private var drawerOpen = false
    private let screenWidth: CGFloat = 160 * 5   // focused play size (5×), screen scales to fit
    private let drawerWidth: CGFloat = 360
    private var drawerWidthConstraint: NSLayoutConstraint!
    // Optional FPS counter (with a mini T3d) in the screen's top-right corner.
    private let fpsOverlay = NSView()
    private let fpsMascot = MascotView(frame: .zero)
    private let fpsLabel = NSTextField(labelWithString: "–")
    private var fpsFrames = 0
    private var fpsClock = Date()
    // Auto-hiding in-game control bar (lighting / full screen / exit).
    private let controlBar = GameControlBar()
    private var controlsHideTimer: Timer?
    private var hoveringControls = false
    var onClose: (() -> Void)?

    init(rom: [UInt8], title: String, url: URL, sourceRect: NSRect? = nil) {
        gb = GameBoy(rom: rom)
        self.rom = rom
        self.sourceRect = sourceRect
        romURL = url
        baseTitle = "T3d Boy — \(title)"
        romHash = Insecure.MD5.hash(data: Data(rom))
            .map { String(format: "%02x", $0) }.joined()

        let rect = NSRect(x: 0, y: 0, width: 160 * 5, height: 144 * 5) // focused play size
        emulatorView = EmulatorView(frame: rect)

        let container = NSView(frame: rect)
        let window = NSWindow(
            contentRect: rect,
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        window.title = baseTitle
        // Clean, chrome-free focus view: no visible title bar or traffic lights —
        // the in-game control bar provides Exit / Full Screen instead.
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.backgroundColor = .black
        window.collectionBehavior.insert(.fullScreenPrimary)
        window.acceptsMouseMovedEvents = true // reveal the control bar on movement
        for b in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            window.standardWindowButton(b)?.isHidden = true
        }
        window.contentView = container
        super.init(window: window)

        setUpContent(container)
        window.delegate = self
        emulatorView.joypad = gb.mmu.joypad

        PlayStats.shared.recordPlay(url)
        startTimer()
        startAudio()
        applyEffects() // apply current dim/worm-light immediately on open

        // Toggling either effect (from any window or the menu) updates this window
        NotificationCenter.default.addObserver(
            forName: .screenEffectsChanged, object: nil, queue: .main
        ) { [weak self] _ in
            self?.applyEffects()
            self?.controlBar.refreshStates()
        }
    }

    func windowDidEnterFullScreen(_ notification: Notification) { controlBar.setFullScreen(true) }
    func windowDidExitFullScreen(_ notification: Notification) { controlBar.setFullScreen(false) }
    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Launch / exit choreography

    /// Power on: appear at the box-art's spot, click the switch, then expand to the
    /// focused play size while everything behind dims. Replaces a plain showWindow.
    func launch() {
        guard let window else { return }
        window.makeFirstResponder(emulatorView)
        let target = centeredFocusedFrame()

        let dim = makeDimWindow()
        dimWindow = dim
        // Start from the box art if we have it, else a small centred seed.
        let start = (sourceRect?.width ?? 0) > 4
            ? sourceRect!
            : target.insetBy(dx: target.width * 0.42, dy: target.height * 0.42)
        window.setFrame(start, display: false)

        dim.alphaValue = 0
        dim.orderFront(nil)
        window.makeKeyAndOrderFront(nil)
        dim.order(.below, relativeTo: window.windowNumber)
        Sounds.playPowerSwitch()

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.42
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().setFrame(target, display: true)
            dim.animator().alphaValue = 0.6
        }, completionHandler: { [weak self] in
            guard let self else { return }
            self.revealControls() // flash the controls so the player knows they're there
            if RASettings.showDrawerByDefault && !self.drawerOpen {
                self.setDrawer(open: true, animated: true)
            }
        })
    }

    /// Power off: shrink back toward the box art while the dim fades, then close.
    func exitFocus() {
        guard let window else { close(); return }
        let back = (sourceRect?.width ?? 0) > 4
            ? sourceRect!
            : window.frame.insetBy(dx: window.frame.width * 0.42, dy: window.frame.height * 0.42)
        Sounds.playPowerSwitch()
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.3
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            window.animator().setFrame(back, display: true)
            window.animator().alphaValue = 0
            dimWindow?.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.close()
        })
    }

    private func centeredFocusedFrame() -> NSRect {
        guard let window, let screen = window.screen ?? NSScreen.main else {
            return window?.frame ?? .zero
        }
        var f = window.frameRect(forContentRect: NSRect(x: 0, y: 0, width: screenWidth, height: screenHeight))
        f.origin.x = screen.visibleFrame.midX - f.width / 2
        f.origin.y = screen.visibleFrame.midY - f.height / 2
        return f
    }

    private func makeDimWindow() -> NSWindow {
        let union = NSScreen.screens.reduce(NSRect.zero) { $0.union($1.frame) }
        let w = NSWindow(contentRect: union, styleMask: .borderless, backing: .buffered, defer: false)
        w.isOpaque = false
        w.backgroundColor = .black
        w.alphaValue = 0
        w.hasShadow = false
        w.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        return w
    }

    // MARK: - Achievements drawer hosting

    private func setUpContent(_ container: NSView) {
        for v in [emulatorView, drawer, handle] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(v)
        }
        drawer.wantsLayer = true
        drawer.layer?.masksToBounds = true // clip cleanly when collapsed
        NSLayoutConstraint.activate([
            // Emulator fills the screen area (left of the drawer); scales to fit.
            emulatorView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            emulatorView.topAnchor.constraint(equalTo: container.topAnchor),
            emulatorView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            emulatorView.trailingAnchor.constraint(equalTo: drawer.leadingAnchor),
            // Drawer fills the space to the right; 0-wide when closed.
            drawer.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            drawer.topAnchor.constraint(equalTo: container.topAnchor),
            drawer.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            // Chevron tab on the screen's right edge.
            handle.trailingAnchor.constraint(equalTo: emulatorView.trailingAnchor, constant: -2),
            handle.centerYAnchor.constraint(equalTo: emulatorView.centerYAnchor),
        ])
        drawerWidthConstraint = drawer.widthAnchor.constraint(equalToConstant: 0)
        drawerWidthConstraint.isActive = true
        handle.onToggle = { [weak self] in self?.toggleDrawer() }
        setUpFPSOverlay(in: container)
        setUpControlBar(in: container)
    }

    private func setUpControlBar(in container: NSView) {
        controlBar.translatesAutoresizingMaskIntoConstraints = false
        controlBar.alphaValue = 0
        controlBar.isHidden = true
        container.addSubview(controlBar)
        NSLayoutConstraint.activate([
            controlBar.centerXAnchor.constraint(equalTo: emulatorView.centerXAnchor),
            controlBar.bottomAnchor.constraint(equalTo: emulatorView.bottomAnchor, constant: -16),
        ])
        controlBar.onToggleHardcore = { HardcoreLighting.isEnabled.toggle() }
        controlBar.onToggleWorm = { WormLight.isEnabled.toggle() }
        controlBar.onFullScreen = { [weak self] in self?.window?.toggleFullScreen(nil) }
        controlBar.onExit = { [weak self] in self?.exitFocus() }
        let hoverHandler: (Bool) -> Void = { [weak self] hovering in
            guard let self else { return }
            self.hoveringControls = hovering
            if hovering { self.controlsHideTimer?.invalidate(); self.revealControls() }
            else { self.scheduleHideControls() }
        }
        controlBar.onHoverChange = hoverHandler
        handle.onHoverChange = hoverHandler
        emulatorView.onMouseMoved = { [weak self] in self?.revealControls() }

        // The drawer reveal handle auto-hides with the rest of the chrome.
        handle.alphaValue = 0
        handle.isHidden = true
    }

    // The handle stays put while the drawer is open (it's the close affordance);
    // otherwise it hides with the control bar.
    private func revealControls() {
        controlBar.isHidden = false
        handle.isHidden = false
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            controlBar.animator().alphaValue = 1
            handle.animator().alphaValue = 1
        }
        scheduleHideControls()
    }

    private func scheduleHideControls() {
        controlsHideTimer?.invalidate()
        guard !hoveringControls else { return }
        controlsHideTimer = Timer.scheduledTimer(withTimeInterval: 2.6, repeats: false) { [weak self] _ in
            guard let self, !self.hoveringControls else { return }
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.4
                self.controlBar.animator().alphaValue = 0
                if !self.drawerOpen { self.handle.animator().alphaValue = 0 }
            }, completionHandler: { [weak self] in
                guard let self else { return }
                if self.controlBar.alphaValue < 0.05 { self.controlBar.isHidden = true }
                if !self.drawerOpen, self.handle.alphaValue < 0.05 { self.handle.isHidden = true }
            })
        }
    }

    // Small FPS readout pinned to the screen's top-right: a mini blinking T3d next
    // to the frame rate, on a translucent pill so it stays legible over any game.
    private func setUpFPSOverlay(in container: NSView) {
        fpsOverlay.wantsLayer = true
        fpsOverlay.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.45).cgColor
        fpsOverlay.layer?.cornerRadius = 5
        fpsOverlay.translatesAutoresizingMaskIntoConstraints = false
        fpsMascot.translatesAutoresizingMaskIntoConstraints = false
        fpsLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
        fpsLabel.textColor = .white
        fpsLabel.translatesAutoresizingMaskIntoConstraints = false

        fpsOverlay.addSubview(fpsMascot)
        fpsOverlay.addSubview(fpsLabel)
        container.addSubview(fpsOverlay) // above the emulator view, top-right

        NSLayoutConstraint.activate([
            fpsOverlay.topAnchor.constraint(equalTo: emulatorView.topAnchor, constant: 6),
            fpsOverlay.trailingAnchor.constraint(equalTo: emulatorView.trailingAnchor, constant: -6),
            fpsOverlay.heightAnchor.constraint(equalTo: fpsMascot.heightAnchor, constant: 8),

            fpsMascot.leadingAnchor.constraint(equalTo: fpsOverlay.leadingAnchor, constant: 4),
            fpsMascot.centerYAnchor.constraint(equalTo: fpsOverlay.centerYAnchor),
            fpsMascot.widthAnchor.constraint(equalToConstant: 16),
            fpsMascot.heightAnchor.constraint(equalToConstant: 16),

            fpsLabel.leadingAnchor.constraint(equalTo: fpsMascot.trailingAnchor, constant: 4),
            fpsLabel.trailingAnchor.constraint(equalTo: fpsOverlay.trailingAnchor, constant: -5),
            fpsLabel.centerYAnchor.constraint(equalTo: fpsOverlay.centerYAnchor),
        ])

        fpsOverlay.isHidden = !RASettings.showFPS
        NotificationCenter.default.addObserver(
            forName: .raSettingsChanged, object: nil, queue: .main
        ) { [weak self] _ in self?.fpsOverlay.isHidden = !RASettings.showFPS }
    }

    @objc func toggleDrawer() { setDrawer(open: !drawerOpen, animated: true) }

    private func setDrawer(open: Bool, animated: Bool) {
        guard open != drawerOpen, let window else { return }
        drawerOpen = open
        handle.isExpanded = open
        if open { // pin the handle visible while the panel is open (it's the close button)
            controlsHideTimer?.invalidate()
            handle.isHidden = false
            handle.alphaValue = 1
        } else {
            scheduleHideControls() // collapsed → rejoin the auto-hide cycle
        }

        var f = window.frame
        f.size.width += open ? drawerWidth : -drawerWidth // grow/shrink rightward
        if open, let vis = window.screen?.visibleFrame, f.maxX > vis.maxX {
            f.origin.x = max(vis.minX, vis.maxX - f.size.width) // slide left to stay on-screen
        }
        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.2
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                drawerWidthConstraint.animator().constant = open ? drawerWidth : 0
                window.animator().setFrame(f, display: true)
            }
        } else {
            drawerWidthConstraint.constant = open ? drawerWidth : 0
            window.setFrame(f, display: true)
        }
    }

    /// Bring this window's drawer forward focused on an achievement (toast click-through).
    func openDrawerAndFocus(_ id: UInt32) {
        window?.makeKeyAndOrderFront(nil)
        if !drawerOpen { setDrawer(open: true, animated: true) }
        drawer.focus(onAchievement: id)
    }

    private var screenHeight: CGFloat { 144 * 5 }

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
            // FPS readout: averaged over ~0.5s so the number doesn't flicker.
            if self.bootDone, !self.fpsOverlay.isHidden {
                self.fpsFrames += 1
                let elapsed = Date().timeIntervalSince(self.fpsClock)
                if elapsed >= 0.5 {
                    self.fpsLabel.stringValue = String(Int((Double(self.fpsFrames) / elapsed).rounded()))
                    self.fpsFrames = 0
                    self.fpsClock = Date()
                }
            }
            // Tick the achievement runtime once per emulated frame (this window
            // only if it owns RA). idle() during boot keeps server work flowing.
            if Achievements.shared.isOwner(self) {
                if self.bootDone { Achievements.shared.doFrame() }
                else { Achievements.shared.idle() }
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
        let dim = HardcoreLighting.isEnabled ? HardcoreLighting.currentDimOpacity() : 0
        emulatorView.applyEffects(dim: dim, worm: WormLight.isEnabled)
    }

    @objc func toggleHardcoreLighting(_ sender: Any?) {
        HardcoreLighting.isEnabled.toggle() // notification re-applies to all windows
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
        dimWindow?.orderOut(nil)
        dimWindow = nil
        flushPlaytime(stop: true)
        frameTimer?.invalidate()
        frameTimer = nil
        audioEngine?.stop()
        audioEngine = nil
        if GamepadManager.shared.joypad === gb.mmu.joypad {
            GamepadManager.shared.joypad = nil
        }
        if Achievements.shared.isOwner(self) {
            Achievements.shared.unloadGame()
            RAMemory.mmu = nil
            Achievements.shared.resignOwnership(self)
        }
        onClose?()
    }

    // The frontmost game window owns both the controller and the achievement runtime
    func windowDidBecomeKey(_ notification: Notification) {
        GamepadManager.shared.joypad = gb.mmu.joypad
        updateControllerStatus()
        claimAchievements()
    }

    // Point the RA runtime at this window's game (reloads if it's a different game)
    private func claimAchievements() {
        guard Achievements.shared.claimOwnership(self) else { return }
        RAMemory.mmu = gb.mmu
        Achievements.shared.loadGame(rom: rom, cgb: gb.cgb)
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
        let slot = sender.tag
        // Hardcore mode forbids loading save states. Offer the session escape hatch.
        if Achievements.shared.hardcoreBlocks(.loadSaveState) {
            promptHardcoreBlocked(action: "Loading a save state") { [weak self] in
                self?.performLoadState(slot: slot)
            }
            return
        }
        performLoadState(slot: slot)
    }

    private func performLoadState(slot: Int) {
        guard let data = try? Data(contentsOf: stateURL(slot: slot)),
              let snap = try? PropertyListDecoder().decode(Snapshot.self, from: data) else {
            NSSound.beep()
            return
        }
        gb.restore(snap)
        bootDone = true // loading a state skips any boot animation in progress
        emulatorView.present(gb.mmu.ppu.framebuffer)
    }

    /// Shared hardcore-block dialog: explains the restriction and lets the player
    /// drop to softcore for this session so the action can proceed.
    private func promptHardcoreBlocked(action: String, proceed: @escaping () -> Void) {
        guard let window else { return }
        let alert = NSAlert()
        alert.messageText = "\(action) is disabled in hardcore mode"
        alert.informativeText = """
        RetroAchievements hardcore mode blocks save-state loads, rewind, slow-motion, \
        and cheats. You can turn hardcore off for this session to continue — your saved \
        preference is kept, and hardcore returns next time you launch T3d Boy.
        """
        alert.addButton(withTitle: "Disable Hardcore for This Session")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { response in
            guard response == .alertFirstButtonReturn else { return }
            Achievements.shared.disableHardcoreForSession()
            proceed()
        }
    }

    // MARK: - Menu validation (slot timestamps, pause/resume title)

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(togglePause(_:)):
            menuItem.title = paused ? "Resume" : "Pause"
            return true
        case #selector(toggleHardcoreLighting(_:)):
            menuItem.state = HardcoreLighting.isEnabled ? .on : .off
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
