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
    }
    required init?(coder: NSCoder) { fatalError() }

    var image: CGImage? {
        didSet { layer?.contents = image }
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

final class LibraryWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    private var allRoms: [URL] = []
    private var gbRoms: [URL] = []
    private var gbcRoms: [URL] = []
    private var roms: [URL] = []
    private var nameCounts: [String: Int] = [:]
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
    private let darkSwitch = NSSwitch()

    var onPlay: ((URL) -> Void)?
    var onToggleDark: ((Bool) -> Void)?

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 520),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        window.title = "T3d Boy — ROM Library"
        window.minSize = NSSize(width: 700, height: 440)
        super.init(window: window)
        buildUI()
        window.center()
        NotificationCenter.default.addObserver(
            forName: PlayStats.changed, object: nil, queue: .main
        ) { [weak self] _ in
            self?.refreshSelectedStats()
            self?.tableView.reloadData() // keep per-row stats current
        }
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

        let darkLabel = NSTextField(labelWithString: "Dark Mode")
        darkLabel.font = .systemFont(ofSize: 12)
        darkLabel.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(darkLabel)

        darkSwitch.target = self
        darkSwitch.action = #selector(darkToggled)
        darkSwitch.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(darkSwitch)

        // Right-column layout guide spanning from the list to the window edge
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
            folderBar.centerYAnchor.constraint(equalTo: darkSwitch.centerYAnchor),

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
            rightArea.trailingAnchor.constraint(equalTo: content.trailingAnchor),

            playButton.bottomAnchor.constraint(equalTo: darkSwitch.topAnchor, constant: -14),
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

            darkSwitch.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            darkSwitch.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -14),
            darkLabel.trailingAnchor.constraint(equalTo: darkSwitch.leadingAnchor, constant: -8),
            darkLabel.centerYAnchor.constraint(equalTo: darkSwitch.centerYAnchor),
        ])
        refreshFolderBarColor()
    }

    private func refreshFolderBarColor() {
        (window?.contentView?.effectiveAppearance ?? NSApp.effectiveAppearance)
            .performAsCurrentDrawingAppearance {
                folderBar.layer?.backgroundColor =
                    NSColor.labelColor.withAlphaComponent(0.06).cgColor
            }
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
        applyFilter(keepSelection: false)
        ROMCatalog.shared.classify(allRoms) { [weak self] in
            self?.applyFilter(keepSelection: true)
        }
    }

    // Filter into the active tab. Each non-Favourites tab draws from its own
    // system folder; when both tabs share one folder, the CGB header flag
    // splits them. Unclassified ROMs show until the background scan settles.
    private func applyFilter(keepSelection: Bool) {
        let selectedURL: URL? = keepSelection && tableView.selectedRow >= 0
            && tableView.selectedRow < roms.count ? roms[tableView.selectedRow] : nil

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
        } else if let selectedURL, let idx = roms.firstIndex(of: selectedURL) {
            tableView.selectRowIndexes([idx], byExtendingSelection: false)
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

    func setDarkSwitch(on: Bool) {
        darkSwitch.state = on ? .on : .off
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

    @objc private func darkToggled() {
        onToggleDark?(darkSwitch.state == .on)
    }
}
