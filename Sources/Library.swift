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
        layer?.cornerRadius = 14
        layer?.masksToBounds = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.15).cgColor
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.cgColor
        effects = ScreenEffects(host: layer!)
        effects.layout(bounds)

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
    private let separator = NSBox()

    init() {
        super.init(frame: .zero)
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.font = .systemFont(ofSize: 13)
        statLabel.font = .monospacedDigitSystemFont(ofSize: 10.5, weight: .regular)
        statLabel.textColor = .secondaryLabelColor
        statLabel.alignment = .right
        statLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        statLabel.setContentHuggingPriority(.required, for: .horizontal)
        separator.boxType = .separator

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
            separator.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }
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
    private let tabs = PillTabBar(titles: ["Game Boy", "Game Boy Color", "Favourites"])
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
    // "Lighting" housing under the artwork
    private let effectsHousing = NSView()
    private let hardcoreSwitch = NSSwitch()
    private let wormSwitch = NSSwitch()
    private var effectsTimer: Timer?

    // Achievements drawer: tucked off the right edge, popped out via the handle to
    // browse the selected game's achievements before playing.
    private let achievementsDrawer = AchievementsDrawer()
    private let drawerHandle = DrawerHandle()
    private var drawerOpen = false
    private let drawerWidth: CGFloat = 360
    private var drawerWidthConstraint: NSLayoutConstraint!
    private var previewTimer: Timer?
    private var previewedURL: URL?
    private var raIdleTimer: Timer?

    var onPlay: ((URL) -> Void)?

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 860, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        window.title = "T3d Boy — ROM Library"
        window.minSize = NSSize(width: 720, height: 540)
        super.init(window: window)
        window.delegate = self
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
        let divider = NSBox()
        divider.boxType = .separator
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
        let artTop = artView.topAnchor.constraint(equalTo: content.topAnchor, constant: 24)
        artTop.priority = .defaultLow

        NSLayoutConstraint.activate([
            tabs.topAnchor.constraint(equalTo: content.topAnchor, constant: 10),
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
            folderBar.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -12),

            folderBarLabel.leadingAnchor.constraint(equalTo: folderBar.leadingAnchor, constant: 10),
            folderBarLabel.centerYAnchor.constraint(equalTo: folderBar.centerYAnchor),
            folderBarLabel.trailingAnchor.constraint(
                lessThanOrEqualTo: folderBarButton.leadingAnchor, constant: -6),
            folderBarButton.trailingAnchor.constraint(equalTo: folderBar.trailingAnchor, constant: -5),
            folderBarButton.centerYAnchor.constraint(equalTo: folderBar.centerYAnchor),

            divider.leadingAnchor.constraint(equalTo: scroll.trailingAnchor, constant: 1),
            divider.topAnchor.constraint(equalTo: content.topAnchor, constant: 10),
            divider.bottomAnchor.constraint(equalTo: folderBar.topAnchor, constant: -8),

            rightArea.leadingAnchor.constraint(equalTo: scroll.trailingAnchor),
            rightArea.trailingAnchor.constraint(equalTo: achievementsDrawer.leadingAnchor),

            // Drawer fills the space to the right of the detail pane; 0-wide when closed.
            achievementsDrawer.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            achievementsDrawer.topAnchor.constraint(equalTo: content.topAnchor),
            achievementsDrawer.bottomAnchor.constraint(equalTo: content.bottomAnchor),

            // Chevron handle sits on the boundary between the detail pane and drawer.
            drawerHandle.trailingAnchor.constraint(equalTo: rightArea.trailingAnchor, constant: -2),
            drawerHandle.centerYAnchor.constraint(equalTo: content.centerYAnchor),
            drawerHandle.widthAnchor.constraint(equalToConstant: 24),
            drawerHandle.heightAnchor.constraint(equalToConstant: 70),

            // Lighting housing sits flush at the bottom of the detail column
            effectsHousing.leadingAnchor.constraint(equalTo: rightArea.leadingAnchor, constant: 24),
            effectsHousing.trailingAnchor.constraint(equalTo: rightArea.trailingAnchor, constant: -24),
            effectsHousing.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -14),

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
            artView.topAnchor.constraint(greaterThanOrEqualTo: content.topAnchor, constant: 24),
            artView.centerXAnchor.constraint(equalTo: rightArea.centerXAnchor),
            artView.widthAnchor.constraint(equalTo: artView.heightAnchor, multiplier: 10.0 / 9.0),
            artView.widthAnchor.constraint(lessThanOrEqualTo: rightArea.widthAnchor, constant: -48),

            emptyLabel.centerXAnchor.constraint(equalTo: rightArea.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: content.centerYAnchor),
        ])

        // Toggled between 0 (closed) and drawerWidth (open); window width follows.
        drawerWidthConstraint = achievementsDrawer.widthAnchor.constraint(equalToConstant: 0)
        drawerWidthConstraint.isActive = true

        refreshFolderBarColor()
    }

    private func refreshFolderBarColor() {
        (window?.contentView?.effectiveAppearance ?? NSApp.effectiveAppearance)
            .performAsCurrentDrawingAppearance {
                let tint = NSColor.labelColor.withAlphaComponent(0.06).cgColor
                folderBar.layer?.backgroundColor = tint
                effectsHousing.layer?.backgroundColor = tint
            }
    }

    // MARK: - Lighting housing (Hardcore / Worm Light toggles + hints)

    private func buildEffectsHousing() {
        effectsHousing.wantsLayer = true
        effectsHousing.layer?.cornerRadius = 10
        effectsHousing.translatesAutoresizingMaskIntoConstraints = false

        func title(_ s: String) -> NSTextField {
            let t = NSTextField(labelWithString: s)
            t.font = .systemFont(ofSize: 13, weight: .semibold)
            t.translatesAutoresizingMaskIntoConstraints = false
            return t
        }
        func hint(_ s: String) -> NSTextField {
            let t = NSTextField(wrappingLabelWithString: s)
            t.font = .systemFont(ofSize: 11)
            t.textColor = .secondaryLabelColor
            t.translatesAutoresizingMaskIntoConstraints = false
            return t
        }
        let hcTitle = title("Hardcore Lighting")
        let hcHint = hint("Automatically dim the T3d Boy display based on ambient lighting")
        let wlTitle = title("Worm Light")
        let wlHint = hint("Shine a warm ’90s clip-on light down over the screen")
        let divider = NSBox()
        divider.boxType = .separator
        divider.translatesAutoresizingMaskIntoConstraints = false

        for sw in [hardcoreSwitch, wormSwitch] {
            sw.controlSize = .small
            sw.target = self
            sw.translatesAutoresizingMaskIntoConstraints = false
        }
        hardcoreSwitch.action = #selector(hardcoreToggled)
        wormSwitch.action = #selector(wormToggled)

        for v in [hcTitle, hcHint, wlTitle, wlHint, divider, hardcoreSwitch, wormSwitch] {
            effectsHousing.addSubview(v)
        }
        let pad: CGFloat = 12
        NSLayoutConstraint.activate([
            hcTitle.topAnchor.constraint(equalTo: effectsHousing.topAnchor, constant: 11),
            hcTitle.leadingAnchor.constraint(equalTo: effectsHousing.leadingAnchor, constant: pad),
            hardcoreSwitch.centerYAnchor.constraint(equalTo: hcTitle.centerYAnchor),
            hardcoreSwitch.trailingAnchor.constraint(equalTo: effectsHousing.trailingAnchor, constant: -pad),

            hcHint.topAnchor.constraint(equalTo: hcTitle.bottomAnchor, constant: 3),
            hcHint.leadingAnchor.constraint(equalTo: effectsHousing.leadingAnchor, constant: pad),
            hcHint.trailingAnchor.constraint(equalTo: effectsHousing.trailingAnchor, constant: -pad),

            divider.topAnchor.constraint(equalTo: hcHint.bottomAnchor, constant: 11),
            divider.leadingAnchor.constraint(equalTo: effectsHousing.leadingAnchor, constant: pad),
            divider.trailingAnchor.constraint(equalTo: effectsHousing.trailingAnchor, constant: -pad),

            wlTitle.topAnchor.constraint(equalTo: divider.bottomAnchor, constant: 11),
            wlTitle.leadingAnchor.constraint(equalTo: effectsHousing.leadingAnchor, constant: pad),
            wormSwitch.centerYAnchor.constraint(equalTo: wlTitle.centerYAnchor),
            wormSwitch.trailingAnchor.constraint(equalTo: effectsHousing.trailingAnchor, constant: -pad),

            wlHint.topAnchor.constraint(equalTo: wlTitle.bottomAnchor, constant: 3),
            wlHint.leadingAnchor.constraint(equalTo: effectsHousing.leadingAnchor, constant: pad),
            wlHint.trailingAnchor.constraint(equalTo: effectsHousing.trailingAnchor, constant: -pad),
            wlHint.bottomAnchor.constraint(equalTo: effectsHousing.bottomAnchor, constant: -11),
        ])
        syncEffectsUI()
    }

    // Switch states + the art preview, kept in step with the global toggles
    private func syncEffectsUI() {
        hardcoreSwitch.state = HardcoreLighting.isEnabled ? .on : .off
        wormSwitch.state = WormLight.isEnabled ? .on : .off
        applyArtEffects()
    }

    // Live preview: dim the box art per ambient light, plus the worm-light glow
    private func applyArtEffects() {
        let dim = HardcoreLighting.isEnabled ? HardcoreLighting.currentDimOpacity() : 0
        artView.applyEffects(dim: dim, worm: WormLight.isEnabled)
    }

    @objc private func hardcoreToggled() {
        HardcoreLighting.isEnabled = (hardcoreSwitch.state == .on) // posts .screenEffectsChanged
    }

    @objc private func wormToggled() {
        WormLight.isEnabled = (wormSwitch.state == .on)
    }

    // Loads both per-system folders from preferences and refreshes the view.
    func reload() {
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
        let (seconds, plays) = PlayStats.shared.stats(for: rom)
        var parts = [
            "⏱ \(PlayStats.format(seconds: seconds))",
            "▶ \(plays) \(plays == 1 ? "play" : "plays")",
        ]
        if let score = Popularity.score(for: rom) {
            parts.append("♥ \(score)/100")
        }
        statsLabel.stringValue = parts.joined(separator: "   ·   ")
    }

    /// Re-apply appearance-dependent colours after a dark/light switch (driven from
    /// Preferences ▸ Appearance now that the library no longer hosts the toggle).
    func refreshForAppearance() {
        refreshFolderBarColor()
    }

    // Reflects the active tab's folder, reading as part of that tab
    private func updateFolderBar() {
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
        cell.nameLabel.stringValue = star + rowTitle(for: rom)

        var stats: [String] = []
        let seconds = PlayStats.shared.seconds(for: rom)
        if seconds > 0 { stats.append(PlayStats.format(seconds: seconds)) }
        if let score = Popularity.score(for: rom) { stats.append("♥ \(score)") }
        cell.statLabel.stringValue = stats.joined(separator: " · ")
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard tableView.selectedRow >= 0, tableView.selectedRow < roms.count else { return }
        let rom = roms[tableView.selectedRow]
        lastSelectedPath = rom.path
        UserDefaults.standard.set(rom.path, forKey: Self.lastSelectedKey)
        titleLabel.stringValue = displayName(rom, stripTags: true)
        updateFavButton(for: rom)
        updateStats(for: rom)
        artView.image = nil
        ThumbnailStore.shared.art(for: rom) { [weak self] image in
            guard let self,
                  self.tableView.selectedRow >= 0,
                  self.tableView.selectedRow < self.roms.count,
                  self.roms[self.tableView.selectedRow] == rom else { return }
            self.artView.image = image
        }
        schedulePreview(immediate: false) // refresh the achievements drawer for the new pick
    }

    // MARK: - Actions

    @objc private func playSelected() {
        guard tableView.selectedRow >= 0, tableView.selectedRow < roms.count else { return }
        onPlay?(roms[tableView.selectedRow])
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

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
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
        if Achievements.shared.isOwner(self) {
            Achievements.shared.unloadGame()
            RAMemory.mmu = nil
            Achievements.shared.resignOwnership(self)
            previewedURL = nil
        }
    }
}
