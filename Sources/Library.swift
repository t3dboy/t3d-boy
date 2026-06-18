// T3d Boy — ROM library: list of ROMs with auto-generated title-screen art

import Cocoa
import CryptoKit
import ImageIO

// Generates and caches "box art" by booting each ROM headlessly in the
// emulator core and capturing its title screen.
final class ThumbnailStore {
    static let shared = ThumbnailStore()

    private let dir: URL
    private var cache = [URL: CGImage]()
    private let queue = DispatchQueue(label: "t3dboy.thumbnails", qos: .userInitiated)

    init() {
        dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("T3d Boy/Thumbnails", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    private func cacheFile(for rom: URL) -> URL {
        let size = (try? FileManager.default.attributesOfItem(atPath: rom.path))?[.size] as? Int ?? 0
        let key = "\(rom.path):\(size):v2" // v2: CGB-aware core renders color art
        let hex = Insecure.MD5.hash(data: Data(key.utf8))
            .map { String(format: "%02x", $0) }.joined()
        return dir.appendingPathComponent(hex + ".png")
    }

    func art(for rom: URL, completion: @escaping (CGImage?) -> Void) {
        if let img = cache[rom] {
            completion(img)
            return
        }
        let file = cacheFile(for: rom)
        queue.async {
            var image: CGImage?
            if let src = CGImageSourceCreateWithURL(file as CFURL, nil) {
                image = CGImageSourceCreateImageAtIndex(src, 0, nil)
            } else if let bytes = try? ROMLoader.load(url: rom) {
                image = Self.titleScreen(rom: bytes)
                if let image { writePNG(image, to: file) }
            }
            DispatchQueue.main.async {
                if let image { self.cache[rom] = image }
                completion(image)
            }
        }
    }

    // MARK: - Batch generation (onboarding scan / File menu)

    private var cancelScan = false

    func missingCount(for roms: [URL]) -> Int {
        roms.filter { !FileManager.default.fileExists(atPath: cacheFile(for: $0).path) }.count
    }

    func cancelGeneration() {
        cancelScan = true
    }

    // Generates art for every ROM without a cached thumbnail, in parallel.
    // progress/completion fire on the main queue; completion's Bool reports
    // whether the run was cancelled.
    func generateMissing(for roms: [URL],
                         progress: @escaping (Int, Int) -> Void,
                         completion: @escaping (Bool) -> Void) {
        cancelScan = false
        let missing = roms.filter {
            !FileManager.default.fileExists(atPath: cacheFile(for: $0).path)
        }
        let total = missing.count
        guard total > 0 else {
            DispatchQueue.main.async { completion(false) }
            return
        }
        let files = missing.map { cacheFile(for: $0) }
        DispatchQueue.global(qos: .userInitiated).async {
            let workers = max(2, ProcessInfo.processInfo.activeProcessorCount - 1)
            let semaphore = DispatchSemaphore(value: workers)
            let group = DispatchGroup()
            let lock = NSLock()
            var done = 0
            for (rom, file) in zip(missing, files) {
                if self.cancelScan { break }
                semaphore.wait()
                group.enter()
                DispatchQueue.global(qos: .userInitiated).async {
                    defer { semaphore.signal(); group.leave() }
                    guard !self.cancelScan else { return }
                    if let bytes = try? ROMLoader.load(url: rom),
                       let image = Self.titleScreen(rom: bytes) {
                        writePNG(image, to: file)
                    }
                    lock.lock()
                    done += 1
                    let d = done
                    lock.unlock()
                    DispatchQueue.main.async { progress(d, total) }
                }
            }
            group.wait()
            let cancelled = self.cancelScan
            DispatchQueue.main.async { completion(cancelled) }
        }
    }

    // Boot the ROM and let it run to its title screen. A single Start tap
    // partway through skips past copyright/intro screens on most games.
    static func titleScreen(rom: [UInt8], frames: Int = 700, tapAt: Int = 300) -> CGImage? {
        let gb = GameBoy(rom: rom)
        for frame in 0 ..< frames {
            gb.mmu.joypad.set(.start, pressed: frame >= tapAt && frame < tapAt + 5)
            gb.runFrame()
        }
        return makeImage(from: gb.mmu.ppu.framebuffer)
    }
}

// Classifies ROMs as Game Boy vs Game Boy Color by the CGB flag in the
// cartridge header (byte 0x143), with a persistent JSON cache so each
// zip is only inspected once.
final class ROMCatalog {
    enum Kind: String { case gb, gbc }

    static let shared = ROMCatalog()

    private let file: URL
    private var cache: [String: String]
    private let queue = DispatchQueue(label: "t3dboy.catalog", qos: .userInitiated)

    init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("T3d Boy", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        file = dir.appendingPathComponent("catalog.json")
        if let data = try? Data(contentsOf: file),
           let dict = try? JSONSerialization.jsonObject(with: data) as? [String: String] {
            cache = dict
        } else {
            cache = [:]
        }
    }

    private func key(for rom: URL) -> String {
        let size = (try? FileManager.default.attributesOfItem(atPath: rom.path))?[.size] as? Int ?? 0
        return "\(rom.path):\(size)"
    }

    func kind(for rom: URL) -> Kind? {
        cache[key(for: rom)].flatMap(Kind.init)
    }

    // Classify any unknown ROMs in the background; `progress` fires on the
    // main queue periodically and once at the end.
    func classify(_ roms: [URL], progress: @escaping () -> Void) {
        let unknown = roms.filter { kind(for: $0) == nil }
        guard !unknown.isEmpty else { return }
        queue.async {
            var done = 0
            for rom in unknown {
                var kind = Kind.gb
                if let bytes = try? ROMLoader.load(url: rom), bytes.count > 0x143 {
                    kind = bytes[0x143] & 0x80 != 0 ? .gbc : .gb
                }
                let k = self.key(for: rom)
                DispatchQueue.main.sync { self.cache[k] = kind.rawValue }
                done += 1
                if done % 20 == 0 {
                    self.save()
                    DispatchQueue.main.async(execute: progress)
                }
            }
            self.save()
            DispatchQueue.main.async(execute: progress)
        }
    }

    private func save() {
        let snapshot = DispatchQueue.main.sync { cache }
        if let data = try? JSONSerialization.data(withJSONObject: snapshot, options: [.sortedKeys]) {
            try? data.write(to: file)
        }
    }
}

// Per-system ROM folders, persisted in UserDefaults. Migrates the legacy
// single-folder setting to both systems so existing installs keep working.
enum ROMFolders {
    enum System { case gb, gbc }

    private static let gbKey = "romFolderGB"
    private static let gbcKey = "romFolderGBC"
    private static let legacyKey = "romFolder"

    static func migrateIfNeeded() {
        let d = UserDefaults.standard
        guard d.string(forKey: gbKey) == nil, d.string(forKey: gbcKey) == nil,
              let legacy = d.string(forKey: legacyKey) else { return }
        d.set(legacy, forKey: gbKey)
        d.set(legacy, forKey: gbcKey)
    }

    private static func key(_ system: System) -> String {
        system == .gb ? gbKey : gbcKey
    }

    static func folder(_ system: System) -> URL? {
        guard let path = UserDefaults.standard.string(forKey: key(system)),
              FileManager.default.fileExists(atPath: path) else { return nil }
        return URL(fileURLWithPath: path)
    }

    static func setFolder(_ url: URL, for system: System) {
        UserDefaults.standard.set(url.path, forKey: key(system))
    }

    static var isConfigured: Bool {
        folder(.gb) != nil || folder(.gbc) != nil
    }

    // Both tabs resolve to one physical directory → classify-by-header splits
    // them; distinct directories → each tab shows its own folder's contents.
    static var sharesFolder: Bool {
        guard let gb = folder(.gb), let gbc = folder(.gbc) else { return false }
        return gb == gbc
    }
}

// Favourited ROMs, persisted by path in UserDefaults
enum Favourites {
    private static let key = "favourites"

    static func all() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: key) ?? [])
    }
    static func isFavourite(_ url: URL) -> Bool {
        all().contains(url.path)
    }
    static func toggle(_ url: URL) {
        var set = all()
        if set.contains(url.path) { set.remove(url.path) } else { set.insert(url.path) }
        UserDefaults.standard.set(Array(set).sorted(), forKey: key)
    }
}

// Image view that scales pixel art without smoothing
final class ArtView: NSView {
    // Same dim + worm-light overlays as the game window, so the box art is a
    // live preview of what Hardcore Lighting / Worm Light will look like — AND the
    // place where the worm-light angle is adjusted (a draggable bulb handle),
    // so gameplay stays uncluttered. Dragging here updates the angle everywhere,
    // including any live game, via the .screenEffectsChanged notification.
    private var effects: ScreenEffects!
    private let goosenecLayer = CAShapeLayer()
    private let bulbLayer = CALayer()
    private var wormVisible = false
    private var draggingLight = false
    private var bulbPoint = CGPoint.zero
    private let grabRadius: CGFloat = 30

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.magnificationFilter = .nearest
        layer?.contentsGravity = .resizeAspect
        layer?.cornerRadius = theme.skinned ? 7 : 14
        layer?.masksToBounds = true
        layer?.backgroundColor = theme.surfaceScreen.cgColor
        layer?.borderWidth = 1
        layer?.borderColor = theme.controlEdge.cgColor
        effects = ScreenEffects(host: layer!)
        effects.layout(bounds)
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
        setAccessibilityLabel("Box art")

        goosenecLayer.fillColor = NSColor.clear.cgColor
        goosenecLayer.strokeColor = NSColor(srgbRed: 1, green: 0.85, blue: 0.55, alpha: 0.45).cgColor
        goosenecLayer.lineWidth = 2
        goosenecLayer.lineCap = .round
        goosenecLayer.isHidden = true
        layer?.addSublayer(goosenecLayer)

        bulbLayer.bounds = CGRect(x: 0, y: 0, width: 15, height: 15)
        bulbLayer.cornerRadius = 7.5
        bulbLayer.backgroundColor = NSColor(srgbRed: 1, green: 0.9, blue: 0.62, alpha: 0.72).cgColor
        bulbLayer.borderColor = NSColor(srgbRed: 1, green: 0.97, blue: 0.86, alpha: 0.95).cgColor
        bulbLayer.borderWidth = 1.5
        bulbLayer.shadowColor = NSColor(srgbRed: 1, green: 0.82, blue: 0.45, alpha: 1).cgColor
        bulbLayer.shadowRadius = 7
        bulbLayer.shadowOpacity = 0.85
        bulbLayer.shadowOffset = .zero
        bulbLayer.isHidden = true
        layer?.addSublayer(bulbLayer)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        effects.layout(bounds)
        updateHandlePosition()
    }

    func applyEffects(dim: Float, worm: Bool) {
        effects.apply(dimOpacity: dim, wormOn: worm)
        setWormHandle(visible: worm)
    }

    var image: CGImage? {
        didSet { layer?.contents = image }
    }

    // MARK: - Worm-light angle handle

    private func setWormHandle(visible: Bool) {
        wormVisible = visible
        goosenecLayer.isHidden = !visible
        bulbLayer.isHidden = !visible
        if visible { updateHandlePosition() }
    }

    private func updateHandlePosition() {
        let p = CGPoint(x: bounds.width * CGFloat(WormLight.sourceX),
                        y: bounds.height * (1 - CGFloat(WormLight.sourceY)))
        bulbPoint = p
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        bulbLayer.position = p
        let pivot = CGPoint(x: bounds.width * 0.5, y: bounds.height) // clips on at top-centre
        let path = CGMutablePath()
        path.move(to: pivot)
        path.addLine(to: p)
        goosenecLayer.path = path
        CATransaction.commit()
    }

    private func setBulbActive(_ active: Bool) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        bulbLayer.transform = CATransform3DMakeScale(active ? 1.35 : 1, active ? 1.35 : 1, 1)
        bulbLayer.opacity = active ? 1 : 0.85
        CATransaction.commit()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: bounds, options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect],
            owner: self))
    }

    private func nearHandle(_ event: NSEvent) -> Bool {
        let p = convert(event.locationInWindow, from: nil)
        return hypot(p.x - bulbPoint.x, p.y - bulbPoint.y) <= grabRadius
    }

    override func mouseMoved(with event: NSEvent) {
        guard wormVisible, !draggingLight else { return }
        (nearHandle(event) ? NSCursor.openHand : NSCursor.arrow).set()
    }

    override func mouseDown(with event: NSEvent) {
        if wormVisible, nearHandle(event) {
            draggingLight = true
            setBulbActive(true)
            NSCursor.closedHand.set()
        } else {
            super.mouseDown(with: event)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard draggingLight else { super.mouseDragged(with: event); return }
        let p = convert(event.locationInWindow, from: nil)
        WormLight.setSource(x: Float(p.x / bounds.width),
                            y: Float(1 - p.y / bounds.height)) // notifies → re-renders everywhere
    }

    override func mouseUp(with event: NSEvent) {
        if draggingLight {
            draggingLight = false
            setBulbActive(false)
            NSCursor.openHand.set()
        } else {
            super.mouseUp(with: event)
        }
    }
}

// List row: name on the left, play time + review score on the right,
// hairline separator underneath
final class ROMCellView: NSTableCellView {
    let nameLabel = NSTextField(labelWithString: "")
    let statLabel = NSTextField(labelWithString: "")
    private let separator = NSView()

    init() {
        super.init(frame: .zero)
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.font = theme.skinned ? .rounded(13, .regular) : .systemFont(ofSize: 13)
        nameLabel.textColor = theme.textListIdle
        statLabel.font = theme.skinned
            ? .monospacedSystemFont(ofSize: 10, weight: .regular)
            : .monospacedDigitSystemFont(ofSize: 10.5, weight: .regular)
        statLabel.textColor = theme.textMuted
        statLabel.alignment = .right
        statLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        statLabel.setContentHuggingPriority(.required, for: .horizontal)
        separator.wantsLayer = true
        separator.layer?.backgroundColor = theme.lineHair.cgColor

        for v in [nameLabel, statLabel, separator] {
            v.translatesAutoresizingMaskIntoConstraints = false
            addSubview(v)
        }
        textField = nameLabel // selection highlight recolors the name
        NSLayoutConstraint.activate([
            nameLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            nameLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            nameLabel.trailingAnchor.constraint(
                lessThanOrEqualTo: statLabel.leadingAnchor, constant: -8),
            statLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            statLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            separator.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            separator.heightAnchor.constraint(equalToConstant: 1),
            separator.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    /// Recolour the title/stats so they stay legible on the themed selection fill.
    /// Driven by the row's selection state (not `backgroundStyle`/emphasis), so a
    /// selected row stays readable even when the window isn't key.
    func applySelection(_ selected: Bool) {
        guard theme.skinned else { return } // classic uses the native emphasis recolour
        nameLabel.textColor = selected ? theme.onLight : theme.textListIdle
        statLabel.textColor = selected ? NSColor.white.withAlphaComponent(0.7) : theme.textMuted
    }
}

/// Table row view that draws the theme's selection treatment (a solid/tinted fill with
/// an accent left border in skinned themes, the system highlight otherwise) and keeps
/// its cell's text legible against that fill regardless of window focus.
final class ThemedRowView: NSTableRowView {
    override var isSelected: Bool {
        get { super.isSelected }
        set { super.isSelected = newValue; restyleCell() }
    }
    override func didAddSubview(_ subview: NSView) {
        super.didAddSubview(subview)
        restyleCell()
    }
    private func restyleCell() {
        for v in subviews { (v as? ROMCellView)?.applySelection(isSelected) }
    }
    override func drawSelection(in dirtyRect: NSRect) {
        guard isSelected else { return }
        guard theme.skinned else { super.drawSelection(in: dirtyRect); return }
        theme.selection.setFill()
        bounds.fill()
        theme.selectionEdge.setFill()
        NSRect(x: 0, y: 0, width: 3, height: bounds.height).fill()
    }
}

final class LibraryWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate, NSWindowDelegate {
    private var allRoms: [URL] = []
    private var gbRoms: [URL] = []
    private var gbcRoms: [URL] = []
    private var roms: [URL] = []
    private var nameCounts: [String: Int] = [:]
    // Remembered across window close/reopen and app launches.
    private var lastSelectedPath: String? = UserDefaults.standard.string(forKey: lastSelectedKey)
    private static let lastSelectedKey = "library.lastSelectedROM"
    private let tabs = PillTabBar(titles: LibraryWindowController.tabTitles())

    /// Console-tab labels. Engineer's keys are narrow and uppercase, so the middle tab
    /// is shortened to "Color" to avoid clipping "GAME BOY COLOR".
    private static func tabTitles() -> [String] {
        theme.id == "engineer"
            ? ["Game Boy", "Color", "Favourites"]
            : ["Game Boy", "Game Boy Color", "Favourites"]
    }
    private let tableView = NSTableView()
    private let favButton = CapsuleButton(title: "☆ Favourite", style: .neutral)
    private let sortPopup = PillDropdown(
        items: ["Name (A–Z)", "Most popular by reviews", "Most played"], titlePrefix: "Sort: ")
    private let artView = ArtView(frame: .zero)
    private let titleLabel = NSTextField(labelWithString: "")
    private let statsLabel = NSTextField(labelWithString: "")
    // Folder strip attached under the tabs (per active system)
    private let folderBar = NSView()
    private let folderBarLabel = NSTextField(labelWithString: "")
    private let folderBarButton = CapsuleButton(
        title: "Change", style: .neutral, fontSize: 11, height: 24)
    private let playButton = CapsuleButton(title: "▶  Play", style: .prominent)
    private let emptyLabel = NSTextField(labelWithString: "")
    // Warm background behind the ROM list (skinned themes only)
    private let listPanel = NSView()
    private let listDivider = NSView()
    // "Lighting" housing under the artwork
    private let effectsHousing = NSView()
    private let hardcoreSwitch = SettingToggle()
    private let wormSwitch = SettingToggle()
    private let lcdSwitch = SettingToggle()
    private let t3dLightSwitch = SettingToggle()
    private var wormRow: NSView?
    private var t3dLightRow: NSView?
    private var effectsTimer: Timer?

    // Achievements drawer: tucked off the right edge, popped out via the handle to
    // browse the selected game's achievements before playing.
    private let achievementsDrawer = AchievementsDrawer()
    private let drawerHandle = DrawerHandle()
    private var drawerOpen = false
    private let drawerWidth: CGFloat = 360
    private var drawerWidthConstraint: NSLayoutConstraint!

    // T3d Tunes — the bottom drawer (the sound chip as an instrument). Opening it grows
    // the window taller downward (like the achievements drawer grows it wider); open both
    // and it's taller still, with the looper spreading into the extra width.
    private let chiptunesDrawer = ChiptunesDrawer()
    private var chiptunesOpen = false
    private var chiptunesHeightConstraint: NSLayoutConstraint!
    private let chiptunesBaseHeight: CGFloat = 300
    private let chiptunesBonusHeight: CGFloat = 60 // extra room when the achievements drawer is open
    private var barHeight: CGFloat { ChiptunesDrawer.barHeight } // the always-visible launcher bar
    /// Drawer height when closed (just the bar) and open (bar + instrument).
    private var chiptunesClosedHeight: CGFloat { barHeight }
    private var chiptunesOpenHeight: CGFloat { barHeight + chiptunesBaseHeight + (drawerOpen ? chiptunesBonusHeight : 0) }
    /// The library body sits above the chiptunes drawer; bottom-anchored chrome hangs off
    /// the drawer's top edge (0-height when closed, so the layout is unchanged).
    private var bodyBottom: NSLayoutYAxisAnchor { chiptunesDrawer.topAnchor }
    private var previewTimer: Timer?
    private var previewedURL: URL?
    private var raIdleTimer: Timer?

    var onPlay: ((URL, NSRect) -> Void)?

    /// The Engineer theme wraps the library in device chrome (I/O bar, header plate,
    /// trim) and needs extra vertical room.
    private var isEngineer: Bool { theme.id == "engineer" }
    /// Liquid Glass makes the whole window see-through (behind-window vibrancy), so the
    /// Mac desktop shows through the app and the glass controls refract it.
    private var isLiquidGlass: Bool { theme.id == "liquidglass" }
    private var topInset: CGFloat { isEngineer ? 130 : 10 }
    private var bottomInset: CGFloat { isEngineer ? 34 : 12 }

    init() {
        let engineer = ThemeManager.shared.current.id == "engineer"
        // The always-visible T3d Tunes bar sits at the bottom, so add its height to keep
        // the library's own space unchanged.
        let bar = ChiptunesDrawer.barHeight
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 880, height: (engineer ? 740 : 600) + bar),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        window.title = "T3d Boy — ROM Library"
        window.minSize = NSSize(width: 760, height: (engineer ? 700 : 540) + bar)
        super.init(window: window)
        window.delegate = self
        // Don't let macOS restore a stale saved frame over our themed size — the Engineer
        // theme needs a wider/taller window than the others, and restoration was clobbering it.
        window.isRestorable = false
        buildUI()
        window.center()
        NotificationCenter.default.addObserver(
            forName: PlayStats.changed, object: nil, queue: .main
        ) { [weak self] _ in
            self?.refreshSelectedStats()
            self?.tableView.reloadData() // keep per-row stats current
        }
        // Keep the housing switches + art preview in sync when toggled elsewhere
        NotificationCenter.default.addObserver(
            forName: .screenEffectsChanged, object: nil, queue: .main
        ) { [weak self] _ in self?.syncEffectsUI() }

        // Re-read ambient light a few times a second so the art preview dims
        // live as the room (and the user's screen brightness) changes
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.applyArtEffects()
        }
        RunLoop.main.add(timer, forMode: .common)
        effectsTimer = timer
    }
    required init?(coder: NSCoder) { fatalError() }

    private func buildUI() {
        guard let content = window?.contentView else { return }
        content.wantsLayer = true

        // T3d Tunes drawer pinned to the bottom, 0-height when closed (so the layout
        // above is unchanged); the library's bottom chrome hangs off its top edge
        // (`bodyBottom`), so opening it grows the window taller downward.
        content.addSubview(chiptunesDrawer)
        chiptunesDrawer.onToggle = { [weak self] in self?.toggleChiptunes() }
        chiptunesHeightConstraint = chiptunesDrawer.heightAnchor.constraint(equalToConstant: chiptunesClosedHeight)
        NSLayoutConstraint.activate([
            chiptunesDrawer.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            chiptunesDrawer.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            chiptunesDrawer.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            chiptunesHeightConstraint,
        ])

        // Warm list-pane background sits behind everything (skinned themes only).
        listPanel.wantsLayer = true
        listPanel.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(listPanel)

        // Tabs above the list: Game Boy / Game Boy Color / Favourites
        tabs.onChange = { [weak self] _ in self?.tabChanged() }
        tabs.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(tabs)

        // Folder strip: shows the active tab's ROM folder, reading as part of
        // that tab. Changes per system; hidden meaning on Favourites.
        folderBar.wantsLayer = true
        folderBar.layer?.cornerRadius = 7
        folderBar.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(folderBar)

        folderBarLabel.font = .systemFont(ofSize: 11)
        folderBarLabel.textColor = .secondaryLabelColor
        folderBarLabel.lineBreakMode = .byTruncatingMiddle
        folderBarLabel.translatesAutoresizingMaskIntoConstraints = false
        folderBar.addSubview(folderBarLabel)

        folderBarButton.onClick = { [weak self] in self?.changeCurrentFolder() }
        folderBarButton.translatesAutoresizingMaskIntoConstraints = false
        folderBar.addSubview(folderBarButton)

        // Sort selector under the folder strip, same width as the tab bar
        sortPopup.selectedIndex = UserDefaults.standard.integer(forKey: "sortMode")
        sortPopup.onChange = { [weak self] _ in self?.sortChanged() }
        sortPopup.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(sortPopup)

        // Left: ROM list
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("rom"))
        column.title = "ROMs"
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.rowHeight = 38
        tableView.intercellSpacing = NSSize(width: 0, height: 0)
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.doubleAction = #selector(playSelected)
        tableView.style = .inset

        let scroll = NSScrollView()
        scroll.documentView = tableView
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        tableView.backgroundColor = .clear
        scroll.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(scroll)

        // Right: art + title + play
        artView.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(artView)

        titleLabel.font = .systemFont(ofSize: 22, weight: .bold)
        titleLabel.alignment = .center
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(titleLabel)

        statsLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        statsLabel.textColor = .secondaryLabelColor
        statsLabel.alignment = .center
        statsLabel.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(statsLabel)

        playButton.onClick = { [weak self] in self?.playSelected() }
        playButton.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(playButton)

        favButton.onClick = { [weak self] in self?.toggleFavourite() }
        favButton.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(favButton)

        emptyLabel.alignment = .center
        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyLabel.isHidden = true
        content.addSubview(emptyLabel)

        // Hairline divider between the list and the detail pane
        let divider = listDivider
        divider.wantsLayer = true
        divider.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(divider)

        buildEffectsHousing()
        content.addSubview(effectsHousing)

        // Achievements drawer + handle, pinned past the right edge of the detail pane.
        // Collapsed (width 0) by default; popping it out widens the window rightward.
        achievementsDrawer.translatesAutoresizingMaskIntoConstraints = false
        achievementsDrawer.wantsLayer = true
        achievementsDrawer.layer?.masksToBounds = true // clip cleanly when collapsed
        drawerHandle.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(achievementsDrawer)
        content.addSubview(drawerHandle)
        drawerHandle.onToggle = { [weak self] in self?.toggleDrawer() }

        // Right-column layout guide spanning from the list to the drawer's edge
        let rightArea = NSLayoutGuide()
        content.addLayoutGuide(rightArea)

        // The art keeps the Game Boy screen's 10:9 aspect and sizes itself
        // bottom-up so the title/play button never collide with the bottom bar
        let artTop = artView.topAnchor.constraint(equalTo: content.topAnchor, constant: topInset + 14)
        artTop.priority = .defaultLow

        NSLayoutConstraint.activate([
            tabs.topAnchor.constraint(equalTo: content.topAnchor, constant: topInset),
            tabs.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 10),
            tabs.widthAnchor.constraint(equalToConstant: 296),

            sortPopup.topAnchor.constraint(equalTo: tabs.bottomAnchor, constant: 8),
            sortPopup.leadingAnchor.constraint(equalTo: tabs.leadingAnchor),
            sortPopup.widthAnchor.constraint(equalTo: tabs.widthAnchor),

            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            scroll.topAnchor.constraint(equalTo: sortPopup.bottomAnchor, constant: 10),
            scroll.widthAnchor.constraint(equalToConstant: 308),
            scroll.bottomAnchor.constraint(equalTo: folderBar.topAnchor, constant: -8),

            // Folder strip sits below the list, showing the active tab's folder
            folderBar.leadingAnchor.constraint(equalTo: tabs.leadingAnchor),
            folderBar.widthAnchor.constraint(equalTo: tabs.widthAnchor),
            folderBar.heightAnchor.constraint(equalToConstant: 30),
            folderBar.bottomAnchor.constraint(equalTo: bodyBottom, constant: -bottomInset),

            folderBarLabel.leadingAnchor.constraint(equalTo: folderBar.leadingAnchor, constant: 10),
            folderBarLabel.centerYAnchor.constraint(equalTo: folderBar.centerYAnchor),
            folderBarLabel.trailingAnchor.constraint(
                lessThanOrEqualTo: folderBarButton.leadingAnchor, constant: -6),
            folderBarButton.trailingAnchor.constraint(equalTo: folderBar.trailingAnchor, constant: -5),
            folderBarButton.centerYAnchor.constraint(equalTo: folderBar.centerYAnchor),

            divider.leadingAnchor.constraint(equalTo: scroll.trailingAnchor, constant: 1),
            divider.widthAnchor.constraint(equalToConstant: 1),
            divider.topAnchor.constraint(equalTo: content.topAnchor, constant: topInset),
            divider.bottomAnchor.constraint(equalTo: folderBar.topAnchor, constant: -8),

            // List-pane background spans the whole left column behind the list chrome.
            listPanel.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            listPanel.topAnchor.constraint(equalTo: content.topAnchor),
            listPanel.bottomAnchor.constraint(equalTo: bodyBottom),
            listPanel.trailingAnchor.constraint(equalTo: scroll.trailingAnchor),

            rightArea.leadingAnchor.constraint(equalTo: scroll.trailingAnchor),
            rightArea.trailingAnchor.constraint(equalTo: achievementsDrawer.leadingAnchor),

            // Drawer fills the space to the right of the detail pane; 0-wide when closed.
            achievementsDrawer.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            achievementsDrawer.topAnchor.constraint(equalTo: content.topAnchor),
            achievementsDrawer.bottomAnchor.constraint(equalTo: bodyBottom),

            // Chevron handle sits on the boundary between the detail pane and drawer. Pin
            // its centre to the library body (the achievements drawer spans top→bodyBottom),
            // not the whole window — so it doesn't drift when the chiptunes drawer opens.
            drawerHandle.trailingAnchor.constraint(equalTo: rightArea.trailingAnchor, constant: -2),
            drawerHandle.centerYAnchor.constraint(equalTo: achievementsDrawer.centerYAnchor),
            drawerHandle.widthAnchor.constraint(equalToConstant: 24),
            drawerHandle.heightAnchor.constraint(equalToConstant: 70),

            // Lighting housing sits flush at the bottom of the detail column
            effectsHousing.leadingAnchor.constraint(equalTo: rightArea.leadingAnchor, constant: 24),
            effectsHousing.trailingAnchor.constraint(equalTo: rightArea.trailingAnchor, constant: -24),
            effectsHousing.bottomAnchor.constraint(equalTo: bodyBottom, constant: -(bottomInset + 2)),

            playButton.bottomAnchor.constraint(equalTo: effectsHousing.topAnchor, constant: -16),
            playButton.centerXAnchor.constraint(equalTo: rightArea.centerXAnchor, constant: -55),
            playButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 140),

            favButton.leadingAnchor.constraint(equalTo: playButton.trailingAnchor, constant: 12),
            favButton.centerYAnchor.constraint(equalTo: playButton.centerYAnchor),

            statsLabel.bottomAnchor.constraint(equalTo: playButton.topAnchor, constant: -10),
            statsLabel.leadingAnchor.constraint(equalTo: rightArea.leadingAnchor, constant: 24),
            statsLabel.trailingAnchor.constraint(equalTo: rightArea.trailingAnchor, constant: -24),

            titleLabel.bottomAnchor.constraint(equalTo: statsLabel.topAnchor, constant: -6),
            titleLabel.leadingAnchor.constraint(equalTo: rightArea.leadingAnchor, constant: 24),
            titleLabel.trailingAnchor.constraint(equalTo: rightArea.trailingAnchor, constant: -24),

            artView.bottomAnchor.constraint(equalTo: titleLabel.topAnchor, constant: -16),
            artTop,
            artView.topAnchor.constraint(greaterThanOrEqualTo: content.topAnchor, constant: topInset + 14),
            artView.centerXAnchor.constraint(equalTo: rightArea.centerXAnchor),
            artView.widthAnchor.constraint(equalTo: artView.heightAnchor, multiplier: 10.0 / 9.0),
            artView.widthAnchor.constraint(lessThanOrEqualTo: rightArea.widthAnchor, constant: -48),

            emptyLabel.centerXAnchor.constraint(equalTo: rightArea.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: content.centerYAnchor),
        ])

        // Toggled between 0 (closed) and drawerWidth (open); window width follows.
        drawerWidthConstraint = achievementsDrawer.widthAnchor.constraint(equalToConstant: 0)
        drawerWidthConstraint.isActive = true

        if isEngineer { addEngineerChrome(content) }
        if isLiquidGlass { applyGlassBackdrop() }

        // Keep the chiptunes drawer on top of any theme chrome (e.g. the Engineer trim) so
        // the bar stays clickable and the drawer covers cleanly.
        content.addSubview(chiptunesDrawer, positioned: .above, relativeTo: nil)

        styleChrome()
    }

    /// Device flair for the Engineer theme: I/O bar, engraved header plate + speaker
    /// grille, bottom trim, and the LIBRARY label with the live total-minutes LED.
    private func addEngineerChrome(_ content: NSView) {
        let ioBar = EngineerIOBar()
        let plate = EngineerHeaderPlate()
        let trim = EngineerTrim()
        for v in [ioBar, plate, trim] { content.addSubview(v) }

        // The header plate + grille give the content a small natural fitting width; the
        // window show-path sizes to that and collapses the detail column. Hold a real
        // minimum width so the device keeps its intended proportions.
        content.widthAnchor.constraint(greaterThanOrEqualToConstant: 868).isActive = true

        // "LIBRARY 一覧" label + the red-LED total-minutes read-out, above the tabs.
        let libLabel = NSTextField(labelWithString: "LIBRARY")
        libLabel.font = .monospacedSystemFont(ofSize: 8, weight: .medium)
        libLabel.textColor = theme.textSecondary
        let kata = NSTextField(labelWithString: "一覧")
        kata.font = .monospacedSystemFont(ofSize: 8, weight: .medium)
        kata.textColor = theme.accent
        let labelRow = NSStackView(views: [libLabel, kata])
        labelRow.spacing = 5
        labelRow.translatesAutoresizingMaskIntoConstraints = false
        let minutes = MinutesLED()
        content.addSubview(labelRow); content.addSubview(minutes)

        NSLayoutConstraint.activate([
            ioBar.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            ioBar.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            ioBar.topAnchor.constraint(equalTo: content.topAnchor),

            plate.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            plate.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            plate.topAnchor.constraint(equalTo: ioBar.bottomAnchor),

            trim.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            trim.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            trim.bottomAnchor.constraint(equalTo: bodyBottom),

            labelRow.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            labelRow.topAnchor.constraint(equalTo: plate.bottomAnchor, constant: 10),
            minutes.trailingAnchor.constraint(equalTo: tabs.trailingAnchor),
            minutes.centerYAnchor.constraint(equalTo: labelRow.centerYAnchor),
        ])
    }

    /// Makes the window see-through for Liquid Glass via per-pixel transparency: the
    /// window is non-opaque with a clear background and the panels are translucent, so the
    /// real desktop shows through the chrome — but opaque content (the box art) stays
    /// solid, unlike a window-wide opacity which would dim everything.
    private func applyGlassBackdrop() {
        guard let window else { return }
        window.isOpaque = false
        window.backgroundColor = .clear
        window.titlebarAppearsTransparent = true
    }

    /// Applies the active theme's surfaces, fonts and colours to the window chrome.
    /// Called on build and whenever the theme or appearance changes.
    private func styleChrome() {
        window?.title = theme.cased("T3d Boy — ROM Library")
        // Liquid Glass: a uniform 25%-opaque glass film across the whole window (so the
        // chrome is a bit visible, ~75% see-through), with the desktop showing through.
        window?.backgroundColor = isLiquidGlass ? NSColor(white: 1, alpha: 0.25)
            : (theme.skinned ? theme.surfaceWindow : .windowBackgroundColor)

        titleLabel.font = theme.fontDetailTitle
        titleLabel.textColor = theme.textPrimary
        statsLabel.font = theme.skinned
            ? .monospacedSystemFont(ofSize: 11, weight: .regular)
            : .monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        statsLabel.textColor = theme.textMuted
        emptyLabel.textColor = theme.textMuted
        folderBarLabel.font = theme.fontCaption
        folderBarLabel.textColor = theme.textMuted

        (window?.contentView?.effectiveAppearance ?? NSApp.effectiveAppearance)
            .performAsCurrentDrawingAppearance {
                let panelTint = theme.skinned ? theme.surfacePanel
                    : NSColor.labelColor.withAlphaComponent(0.06)
                listPanel.layer?.backgroundColor = theme.skinned ? theme.surfacePanel.cgColor : NSColor.clear.cgColor
                folderBar.layer?.backgroundColor = (theme.skinned ? theme.surfaceFooter : panelTint).cgColor
                effectsHousing.layer?.backgroundColor = panelTint.cgColor
                listDivider.layer?.backgroundColor = theme.lineHard.cgColor
                effectsHousing.layer?.borderWidth = theme.skinned ? 1 : 0
                effectsHousing.layer?.borderColor = theme.lineHard.cgColor
                folderBar.layer?.cornerRadius = theme.skinned ? theme.radiusMedium : 7
                effectsHousing.layer?.cornerRadius = theme.skinned ? theme.radiusMedium : 10
            }
        tableView.reloadData()
    }

    // MARK: - Lighting housing (Hardcore / Worm Light toggles + hints)

    private func buildEffectsHousing() {
        effectsHousing.wantsLayer = true
        effectsHousing.layer?.cornerRadius = 10
        effectsHousing.translatesAutoresizingMaskIntoConstraints = false

        hardcoreSwitch.onToggle = { HardcoreLighting.isEnabled = $0 } // posts .screenEffectsChanged
        wormSwitch.onToggle = { WormLight.isEnabled = $0 }
        lcdSwitch.onToggle = { LCDGhosting.isEnabled = $0 }
        t3dLightSwitch.onToggle = { T3dBoyLight.isEnabled = $0 }
        hardcoreSwitch.setAccessibilityName("Hardcore Lighting. Automatically dim the display to ambient light")
        wormSwitch.setAccessibilityName("Worm Light. A warm clip-on light over the screen")
        lcdSwitch.setAccessibilityName("T3d LCD Real Feel. Emulates an old LCD's pixel persistence")
        t3dLightSwitch.setAccessibilityName("T3d Boy Light. Only popular in Japan, an electroluminescent teal blue glowing display")

        // Laid out 2 × 2 now that there are four effects.
        let wormRowView = effectRow("Worm Light", "Shine a warm ’90s clip-on light down over the screen", wormSwitch)
        wormRow = wormRowView
        // Hardcore Lighting needs an ambient-light reading; on devices without it, offer
        // an info pill instead of the toggle and make sure it isn't left switched on.
        let hcSupported = HardcoreLighting.isSupported
        if !hcSupported && HardcoreLighting.isEnabled { HardcoreLighting.isEnabled = false }
        let hcRow = effectRow("Hardcore Lighting",
                              "Automatically dim the T3d Boy display based on ambient lighting",
                              hcSupported ? hardcoreSwitch : nil,
                              footer: hcSupported ? nil : ThemedUI.infoPill("Not compatible with this device"),
                              dim: !hcSupported)
        let topRow = NSStackView(views: [hcRow, wormRowView])
        let t3dLightRowView = effectRow("T3d Boy Light",
                                        "Only popular in Japan, an electroluminescent teal blue glowing display",
                                        t3dLightSwitch)
        t3dLightRow = t3dLightRowView
        let bottomRow = NSStackView(views: [
            effectRow("T3d LCD Real Feel™", "Faithfully emulates an old LCD's pixel persistence", lcdSwitch),
            t3dLightRowView,
        ])
        for row in [topRow, bottomRow] {
            row.orientation = .horizontal
            row.distribution = .fillEqually
            row.spacing = 18
        }
        let grid = NSStackView(views: [topRow, bottomRow])
        grid.orientation = .vertical
        grid.alignment = .leading
        grid.spacing = 14
        grid.translatesAutoresizingMaskIntoConstraints = false
        effectsHousing.addSubview(grid)
        let pad: CGFloat = 12
        NSLayoutConstraint.activate([
            grid.topAnchor.constraint(equalTo: effectsHousing.topAnchor, constant: 11),
            grid.leadingAnchor.constraint(equalTo: effectsHousing.leadingAnchor, constant: pad),
            grid.trailingAnchor.constraint(equalTo: effectsHousing.trailingAnchor, constant: -pad),
            grid.bottomAnchor.constraint(equalTo: effectsHousing.bottomAnchor, constant: -11),
        ])
        topRow.widthAnchor.constraint(equalTo: grid.widthAnchor).isActive = true
        bottomRow.widthAnchor.constraint(equalTo: grid.widthAnchor).isActive = true
        syncEffectsUI()
    }

    /// One effect row: title + an optional trailing accessory (the toggle), a greyed
    /// hint underneath, and an optional `footer` (e.g. a "not compatible" pill) below the
    /// hint. `dim` greys the title for unavailable options.
    private func effectRow(_ titleText: String, _ hintText: String, _ accessory: NSView? = nil,
                           footer: NSView? = nil, dim: Bool = false) -> NSView {
        let title = NSTextField(labelWithString: theme.cased(titleText))
        title.font = theme.skinned ? .rounded(13, .regular) : .systemFont(ofSize: 13, weight: .semibold)
        title.textColor = dim ? theme.textFaint : theme.textSecondary
        let hint = NSTextField(wrappingLabelWithString: theme.cased(hintText))
        hint.font = theme.fontCaption
        hint.textColor = theme.textFaint
        hint.preferredMaxLayoutWidth = 180 // half-width grid cell
        let container = NSView()
        for v in [title, hint, accessory, footer].compactMap({ $0 }) {
            v.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(v)
        }
        var cs = [
            title.topAnchor.constraint(equalTo: container.topAnchor),
            title.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            hint.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 3),
            hint.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            hint.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor),
        ]
        if let accessory {
            cs += [
                accessory.centerYAnchor.constraint(equalTo: title.centerYAnchor),
                accessory.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                accessory.leadingAnchor.constraint(greaterThanOrEqualTo: title.trailingAnchor, constant: 8),
            ]
        } else {
            cs.append(title.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor))
        }
        if let footer {
            cs += [
                footer.topAnchor.constraint(equalTo: hint.bottomAnchor, constant: 6),
                footer.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                footer.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor),
                footer.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            ]
        } else {
            cs.append(hint.bottomAnchor.constraint(equalTo: container.bottomAnchor))
        }
        NSLayoutConstraint.activate(cs)
        return container
    }

    /// T3d Boy Light is a Game Boy–only effect — the Game Boy Light never existed for the
    /// Game Boy Color. So for a GBC pick we turn the option off (deselect it) and disable
    /// its toggle; for a Game Boy game it's available again.
    private func updateT3dLightAvailability(for rom: URL) {
        let isGBC = ROMCatalog.shared.kind(for: rom) == .gbc
        if isGBC && T3dBoyLight.isEnabled { T3dBoyLight.isEnabled = false } // posts .screenEffectsChanged
        t3dLightSwitch.isEnabled = !isGBC
        t3dLightRow?.alphaValue = isGBC ? 0.4 : 1
    }

    // Switch states + the art preview, kept in step with the global toggles
    private func syncEffectsUI() {
        hardcoreSwitch.isOn = HardcoreLighting.isEnabled
        wormSwitch.isOn = WormLight.isEnabled
        lcdSwitch.isOn = LCDGhosting.isEnabled
        t3dLightSwitch.isOn = T3dBoyLight.isEnabled
        applyArtEffects()
    }

    // Live preview: dim the box art per ambient light, plus the worm-light glow
    private func applyArtEffects() {
        let dim = HardcoreLighting.isEnabled ? HardcoreLighting.currentDimOpacity() : 0
        artView.applyEffects(dim: dim, worm: WormLight.isEnabled)
    }

    // Loads both per-system folders from preferences and refreshes the view.
    func reload() {
        if DemoMode.isActive { // screenshot mode: made-up titles, no real ROMs
            gbRoms = DemoMode.urls; gbcRoms = []; allRoms = DemoMode.urls
            nameCounts = [:]
            applyFilter(keepSelection: false, restoreLast: false)
            return
        }
        let gbFolder = ROMFolders.folder(.gb)
        let gbcFolder = ROMFolders.folder(.gbc)
        gbRoms = gbFolder.map { ROMLoader.romFiles(in: $0) } ?? []
        gbcRoms = (gbcFolder != nil && gbcFolder == gbFolder)
            ? gbRoms
            : (gbcFolder.map { ROMLoader.romFiles(in: $0) } ?? [])

        // Union (deduped) for favourites, name-collision detection, classification
        var seen = Set<String>()
        allRoms = (gbRoms + gbcRoms).filter { seen.insert($0.path).inserted }

        // Names that collide once region/revision tags are stripped keep
        // their full file names so different releases stay tellable apart
        nameCounts = [:]
        for rom in allRoms {
            nameCounts[displayName(rom, stripTags: true).lowercased(), default: 0] += 1
        }
        applyFilter(keepSelection: false, restoreLast: true)
        ROMCatalog.shared.classify(allRoms) { [weak self] in
            self?.applyFilter(keepSelection: true)
        }
    }

    /// Offscreen render of the (demo) library window to a PNG, for the README
    /// marketing shot. Renders the layer-backed content tree directly, so it needs
    /// no screen-recording permission. Requires `DemoMode.isActive`.
    @discardableResult
    func renderDemoShot(to url: URL, scale: CGFloat = 2.0) -> Bool {
        guard let window = window, let content = window.contentView else { return false }
        // Clean art: no lighting effects on the box-art preview.
        HardcoreLighting.isEnabled = false
        WormLight.isEnabled = false
        T3dBoyLight.isEnabled = false

        window.setContentSize(NSSize(width: 880, height: 600))
        reload()

        // Force a full layout + display pass so every layer has committed contents
        // (table rows, the boot-screen art, the themed toggles).
        content.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        content.display()

        let bounds = content.bounds
        guard bounds.width > 0, bounds.height > 0,
              let layer = content.layer,
              let ctx = CGContext(
                data: nil,
                width: Int(bounds.width * scale), height: Int(bounds.height * scale),
                bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return false }
        ctx.scaleBy(x: scale, y: scale)
        layer.render(in: ctx)
        guard let image = ctx.makeImage() else { return false }
        return writePNG(image, to: url)
    }

    // Filter into the active tab. Each non-Favourites tab draws from its own
    // system folder; when both tabs share one folder, the CGB header flag
    // splits them. Unclassified ROMs show until the background scan settles.
    private func applyFilter(keepSelection: Bool, restoreLast: Bool = false) {
        // Prefer the live selection; otherwise fall back to the remembered ROM so a
        // window reopen (or relaunch) lands back on the game you were looking at.
        let liveSelection: String? = keepSelection && tableView.selectedRow >= 0
            && tableView.selectedRow < roms.count ? roms[tableView.selectedRow].path : nil
        let desiredPath = liveSelection ?? (restoreLast ? lastSelectedPath : nil)

        if tabs.selectedIndex == 2 {
            let favs = Favourites.all()
            roms = allRoms.filter { favs.contains($0.path) }
        } else {
            let wantGBC = tabs.selectedIndex == 1
            let source = wantGBC ? gbcRoms : gbRoms
            if ROMFolders.sharesFolder {
                let wanted: ROMCatalog.Kind = wantGBC ? .gbc : .gb
                roms = source.filter { rom in
                    guard let kind = ROMCatalog.shared.kind(for: rom) else { return true }
                    return kind == wanted
                }
            } else {
                roms = source
            }
        }

        // Apply the chosen sort (lists arrive name-sorted from reload)
        switch sortPopup.selectedIndex {
        case 1: // Most popular by reviews: scored first, descending, then A–Z
            roms = roms.enumerated().sorted {
                let sa = Popularity.score(for: $0.element) ?? -1
                let sb = Popularity.score(for: $1.element) ?? -1
                return sa != sb ? sa > sb : $0.offset < $1.offset
            }.map { $0.element }
        case 2: // Most played, descending, then A–Z
            roms = roms.enumerated().sorted {
                let sa = PlayStats.shared.seconds(for: $0.element)
                let sb = PlayStats.shared.seconds(for: $1.element)
                return sa != sb ? sa > sb : $0.offset < $1.offset
            }.map { $0.element }
        default:
            break
        }

        let gbCount = ROMFolders.sharesFolder
            ? allRoms.filter { ROMCatalog.shared.kind(for: $0) == .gb }.count : gbRoms.count
        let gbcCount = ROMFolders.sharesFolder
            ? allRoms.filter { ROMCatalog.shared.kind(for: $0) == .gbc }.count : gbcRoms.count
        let favCount = allRoms.filter { Favourites.isFavourite($0) }.count
        tabs.setTooltips([
            "\(gbCount) Game Boy ROMs",
            "\(gbcCount) Game Boy Color ROMs",
            "\(favCount) favourites",
        ])

        updateFolderBar()

        if tabs.selectedIndex == 2 {
            emptyLabel.stringValue = "No favourites yet.\nSelect a ROM and press ☆ Favourite."
        } else {
            let name = tabs.selectedIndex == 1 ? "Game Boy Color" : "Game Boy"
            let system: ROMFolders.System = tabs.selectedIndex == 1 ? .gbc : .gb
            emptyLabel.stringValue = ROMFolders.folder(system) == nil
                ? "No \(name) folder set yet.\nUse “Choose…” above to pick one."
                : "No games found in your\n\(name) folder."
        }

        tableView.reloadData()
        let empty = roms.isEmpty
        emptyLabel.isHidden = !empty
        favButton.isHidden = empty
        statsLabel.isHidden = empty
        artView.isHidden = empty
        titleLabel.isHidden = empty
        playButton.isEnabled = !empty
        if empty {
            titleLabel.stringValue = ""
            artView.image = nil
        } else if let desiredPath, let idx = roms.firstIndex(where: { $0.path == desiredPath }) {
            tableView.selectRowIndexes([idx], byExtendingSelection: false)
            tableView.scrollRowToVisible(idx)
        } else {
            tableView.selectRowIndexes([0], byExtendingSelection: false)
            tableView.scrollRowToVisible(0)
        }
    }

    @objc private func tabChanged() {
        applyFilter(keepSelection: false)
    }

    @objc private func sortChanged() {
        UserDefaults.standard.set(sortPopup.selectedIndex, forKey: "sortMode")
        applyFilter(keepSelection: true)
        tableView.scrollRowToVisible(max(0, tableView.selectedRow))
    }

    private func refreshSelectedStats() {
        guard tableView.selectedRow >= 0, tableView.selectedRow < roms.count else { return }
        updateStats(for: roms[tableView.selectedRow])
    }

    private func updateStats(for rom: URL) {
        let (seconds, plays, score): (Int, Int, Int?)
        if let g = DemoMode.isActive ? DemoMode.game(for: rom) : nil {
            (seconds, plays, score) = (g.seconds, g.plays, g.score)
        } else {
            let s = PlayStats.shared.stats(for: rom)
            (seconds, plays, score) = (s.seconds, s.plays, Popularity.score(for: rom))
        }
        var parts = [
            "⏱ \(PlayStats.format(seconds: seconds))",
            "▶ \(plays) \(plays == 1 ? "play" : "plays")",
        ]
        if let score { parts.append("♥ \(score)/100") }
        statsLabel.stringValue = parts.joined(separator: "   ·   ")
    }

    /// Re-apply appearance-dependent colours after a dark/light switch (driven from
    /// Preferences ▸ Appearance now that the library no longer hosts the toggle).
    func refreshForAppearance() {
        styleChrome()
    }

    // Reflects the active tab's folder, reading as part of that tab
    private func updateFolderBar() {
        if DemoMode.isActive {
            folderBarLabel.stringValue = "📁  ~/Games/Game Boy"
            folderBarButton.isHidden = false
            folderBarButton.title = "Change"
            return
        }
        if tabs.selectedIndex == 2 {
            folderBarLabel.stringValue = "★  Favourites from both libraries"
            folderBarButton.isHidden = true
            return
        }
        folderBarButton.isHidden = false
        let system: ROMFolders.System = tabs.selectedIndex == 1 ? .gbc : .gb
        let name = tabs.selectedIndex == 1 ? "Game Boy Color" : "Game Boy"
        if let folder = ROMFolders.folder(system) {
            folderBarLabel.stringValue = "📁  " + folder.path
            folderBarButton.title = "Change"
        } else {
            folderBarLabel.stringValue = "📁  No \(name) folder set"
            folderBarButton.title = "Choose…"
        }
    }

    // Display name: filename without extension or region/revision tags
    private func displayName(_ url: URL, stripTags: Bool) -> String {
        var name = url.deletingPathExtension().lastPathComponent
        if stripTags {
            name = name.replacingOccurrences(
                of: #"\s*[\(\[][^\)\]]*[\)\]]"#, with: "", options: .regularExpression)
        }
        return name
    }

    // MARK: - Table

    func numberOfRows(in tableView: NSTableView) -> Int { roms.count }

    private func rowTitle(for rom: URL) -> String {
        let stripped = displayName(rom, stripTags: true)
        if nameCounts[stripped.lowercased(), default: 0] > 1 {
            return displayName(rom, stripTags: false)
        }
        return stripped
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?,
                   row: Int) -> NSView? {
        let id = NSUserInterfaceItemIdentifier("cell")
        let cell = tableView.makeView(withIdentifier: id, owner: nil) as? ROMCellView ?? {
            let c = ROMCellView()
            c.identifier = id
            return c
        }()
        let rom = roms[row]
        let star = Favourites.isFavourite(rom) ? "★ " : ""
        cell.nameLabel.stringValue = star + theme.cased(rowTitle(for: rom))

        var stats: [String] = []
        if let g = DemoMode.isActive ? DemoMode.game(for: rom) : nil {
            if g.seconds > 0 { stats.append(PlayStats.format(seconds: g.seconds)) }
            stats.append("♥ \(g.score)")
        } else {
            let seconds = PlayStats.shared.seconds(for: rom)
            if seconds > 0 { stats.append(PlayStats.format(seconds: seconds)) }
            if let score = Popularity.score(for: rom) { stats.append("♥ \(score)") }
        }
        cell.statLabel.stringValue = stats.joined(separator: " · ")
        return cell
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        let id = NSUserInterfaceItemIdentifier("themedRow")
        return tableView.makeView(withIdentifier: id, owner: nil) as? ThemedRowView ?? {
            let v = ThemedRowView(); v.identifier = id; return v
        }()
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard tableView.selectedRow >= 0, tableView.selectedRow < roms.count else { return }
        let rom = roms[tableView.selectedRow]
        lastSelectedPath = rom.path
        UserDefaults.standard.set(rom.path, forKey: Self.lastSelectedKey)
        let name = displayName(rom, stripTags: true)
        titleLabel.stringValue = theme.cased(name)
        artView.setAccessibilityLabel("Box art for \(name)")
        updateFavButton(for: rom)
        updateStats(for: rom)
        updateT3dLightAvailability(for: rom)
        chiptunesDrawer.selectedROM = rom
        artView.image = nil
        if DemoMode.isActive {
            artView.image = DemoMode.art // the T3d Boy boot screen as box art
        } else {
            ThumbnailStore.shared.art(for: rom) { [weak self] image in
                guard let self,
                      self.tableView.selectedRow >= 0,
                      self.tableView.selectedRow < self.roms.count,
                      self.roms[self.tableView.selectedRow] == rom else { return }
                self.artView.image = image
            }
        }
        schedulePreview(immediate: false) // refresh the achievements drawer for the new pick
    }

    // MARK: - Actions

    @objc private func playSelected() {
        guard tableView.selectedRow >= 0, tableView.selectedRow < roms.count else { return }
        onPlay?(roms[tableView.selectedRow], artScreenRect())
    }

    /// The box-art view's rect in screen coordinates, so the game can zoom out of it.
    private func artScreenRect() -> NSRect {
        guard let window, !artView.isHidden else { return .zero }
        let inWindow = artView.convert(artView.bounds, to: nil)
        return window.convertToScreen(inWindow)
    }

    @objc private func changeCurrentFolder() {
        let system: ROMFolders.System = tabs.selectedIndex == 1 ? .gbc : .gb
        changeFolder(for: system)
    }

    // Invoked from the File menu — acts on the active tab's system
    func changeFolderForCurrentTab() {
        changeCurrentFolder()
    }

    private func changeFolder(for system: ROMFolders.System) {
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
            guard response == .OK, let url = panel.url else { return }
            ROMFolders.setFolder(url, for: system)
            self?.reload()
        }
    }

    private func updateFavButton(for rom: URL) {
        favButton.title = Favourites.isFavourite(rom) ? "★ Unfavourite" : "☆ Favourite"
    }

    @objc private func toggleFavourite() {
        guard tableView.selectedRow >= 0, tableView.selectedRow < roms.count else { return }
        let rom = roms[tableView.selectedRow]
        Favourites.toggle(rom)
        if tabs.selectedIndex == 2 {
            // Unfavouriting inside the Favourites tab removes the row
            applyFilter(keepSelection: true)
        } else {
            let row = tableView.selectedRow
            tableView.reloadData()
            tableView.selectRowIndexes([row], byExtendingSelection: false)
            updateFavButton(for: rom)
        }
    }

    // MARK: - Achievements drawer

    // MARK: - T3d Tunes drawer

    private func toggleChiptunes() { setChiptunes(open: !chiptunesOpen, animated: true) }

    private func setChiptunes(open: Bool, animated: Bool) {
        guard open != chiptunesOpen, let window else { return }
        chiptunesOpen = open
        chiptunesDrawer.setExpanded(open)
        let target: CGFloat = open ? chiptunesOpenHeight : chiptunesClosedHeight

        var f = window.frame
        let delta = target - chiptunesHeightConstraint.constant
        f.size.height += delta
        f.origin.y -= delta // keep the top edge fixed; the window grows downward
        if open, let vis = window.screen?.visibleFrame, f.origin.y < vis.minY {
            f.origin.y = vis.minY // stay on-screen if it would run off the bottom
        }

        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.22
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                chiptunesHeightConstraint.animator().constant = target
                window.animator().setFrame(f, display: true)
            }
        } else {
            chiptunesHeightConstraint.constant = target
            window.setFrame(f, display: true)
        }

        if open {
            chiptunesDrawer.activate(rom: currentSelectedROM())
        } else {
            chiptunesDrawer.suspend()
        }
    }

    private func currentSelectedROM() -> URL? {
        guard tableView.selectedRow >= 0, tableView.selectedRow < roms.count else { return nil }
        return roms[tableView.selectedRow]
    }

    private func toggleDrawer() { setDrawer(open: !drawerOpen, animated: true) }

    private func setDrawer(open: Bool, animated: Bool) {
        guard open != drawerOpen, let window else { return }
        drawerOpen = open
        drawerHandle.isExpanded = open

        var f = window.frame
        f.size.width += open ? drawerWidth : -drawerWidth // grow/shrink rightward, top-left fixed
        if open, let vis = window.screen?.visibleFrame, f.maxX > vis.maxX {
            f.origin.x = max(vis.minX, vis.maxX - f.size.width) // slide left to stay on-screen
        }
        // If the chiptunes drawer is open, it grows taller when the achievements drawer is —
        // adjust its height and the window together for the "even larger" feel.
        var chipTarget = chiptunesHeightConstraint.constant
        if chiptunesOpen {
            chipTarget = barHeight + chiptunesBaseHeight + (open ? chiptunesBonusHeight : 0)
            let hDelta = chipTarget - chiptunesHeightConstraint.constant
            f.size.height += hDelta
            f.origin.y -= hDelta
        }

        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.2
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                drawerWidthConstraint.animator().constant = open ? drawerWidth : 0
                if chiptunesOpen { chiptunesHeightConstraint.animator().constant = chipTarget }
                window.animator().setFrame(f, display: true)
            }
        } else {
            drawerWidthConstraint.constant = open ? drawerWidth : 0
            if chiptunesOpen { chiptunesHeightConstraint.constant = chipTarget }
            window.setFrame(f, display: true)
        }

        if open {
            startIdlePump()
            schedulePreview(immediate: true)
        } else {
            stopIdlePump()
        }
    }

    /// rc_client drives its async loads (resolve hash → fetch game data → session)
    /// through rc_client_idle(); the game window pumps it per frame, so while the
    /// library owns the runtime we pump it here too, otherwise previews never finish.
    private func startIdlePump() {
        guard raIdleTimer == nil else { return }
        let t = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self, Achievements.shared.isOwner(self) else { return }
            Achievements.shared.idle()
        }
        RunLoop.main.add(t, forMode: .common)
        raIdleTimer = t
    }

    private func stopIdlePump() {
        raIdleTimer?.invalidate()
        raIdleTimer = nil
    }

    /// Debounce loading the selected game into the RA runtime for preview, so
    /// arrowing quickly through the list doesn't fire a request per row.
    private func schedulePreview(immediate: Bool) {
        previewTimer?.invalidate()
        guard drawerOpen else { return } // only do the work while the drawer is visible
        previewTimer = Timer.scheduledTimer(
            withTimeInterval: immediate ? 0 : 0.35, repeats: false
        ) { [weak self] _ in self?.previewSelectedAchievements() }
    }

    private func previewSelectedAchievements() {
        guard drawerOpen, Achievements.shared.isAvailable else { return }
        // Never clobber an actively-playing game's session.
        if let owner = Achievements.shared.owner, owner !== self { return }
        guard tableView.selectedRow >= 0, tableView.selectedRow < roms.count else { return }
        let url = roms[tableView.selectedRow]
        if previewedURL == url, Achievements.shared.isOwner(self) { return } // already shown

        Achievements.shared.claimOwnership(self)
        RAMemory.mmu = nil // preview only — no live memory hook
        previewedURL = url
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let rom = try? ROMLoader.load(url: url) else { return }
            let cgb = rom.count > 0x143 && (rom[0x143] & 0x80) != 0
            DispatchQueue.main.async {
                guard let self, Achievements.shared.isOwner(self), self.previewedURL == url
                else { return }
                Achievements.shared.loadGame(rom: rom, cgb: cgb)
            }
        }
    }

    // MARK: - NSWindowDelegate

    func windowDidBecomeKey(_ notification: Notification) {
        resumeDrawerIfNeeded()
    }

    private var hasSizedOnce = false

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        // The show path shrinks the window below our themed size (and even below minSize);
        // force the intended size on first appearance, then leave it to the user.
        if !hasSizedOnce, let window {
            hasSizedOnce = true
            let target = NSSize(width: 880, height: (isEngineer ? 740 : 600) + chiptunesClosedHeight)
            window.setContentSize(target)
            window.center()
            DispatchQueue.main.async { [weak window] in
                guard let window, abs(window.frame.width - target.width) > 1 else { return }
                window.setContentSize(target); window.center()
            }
        }
        resumeDrawerIfNeeded() // reopening from the Dock tears down on close; rebuild
    }

    /// When the window is shown or refocused with the drawer open, restart the RA idle
    /// pump and re-preview the selection — both are torn down in `windowWillClose`, so
    /// without this the drawer comes back empty after a close + Dock reopen.
    private func resumeDrawerIfNeeded() {
        guard drawerOpen else { return }
        startIdlePump()
        schedulePreview(immediate: true)
    }

    func windowWillClose(_ notification: Notification) {
        previewTimer?.invalidate()
        stopIdlePump()
        chiptunesDrawer.suspend() // stop the chiptune audio engine
        if Achievements.shared.isOwner(self) {
            Achievements.shared.unloadGame()
            RAMemory.mmu = nil
            Achievements.shared.resignOwnership(self)
            previewedURL = nil
        }
    }
}
