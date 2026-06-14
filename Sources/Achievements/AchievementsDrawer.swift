// T3d Boy — the achievements drawer.
//
// A self-contained ~360pt-wide NSView the host pins to the RIGHT of the emulator
// viewport. It renders entirely from `Achievements.shared.gameState`, re-rendering
// on `.achievementsChanged`. The host sizes/positions it, animates the window
// widening, and wires the chevron handle + toast separately.
//
// Public surface for the host:
//   • init() — drop-in NSView, Auto Layout friendly (intrinsic width 360).
//   • func focus(onAchievement id: UInt32) — scroll to + flash that card.
//
// States handled (from RAGameState.identification / .connection):
//   .noGame                       → empty state
//   .unrecognised                 → friendly "not in DB yet" + link
//   .recognised + .loggedOut      → full read-only list + sign-in banner
//   .recognised + .loggedIn       → full feature set
//   gameState.errorMessage != nil → non-blocking error chip in the header

import Cocoa

final class AchievementsDrawer: NSView {

    // MARK: - Public API

    /// Scrolls to and briefly highlights the card for `id` (toast click-through).
    func focus(onAchievement id: UInt32) {
        guard let row = rowIndex(forAchievement: id) else { return }
        // Make sure the section the card lives in is expanded.
        if let section = sectionContaining(achievement: id), collapsedSections.contains(section) {
            collapsedSections.remove(section)
            rebuildRows()
        }
        guard let r = rowIndex(forAchievement: id) else { return }
        tableView.scrollRowToVisible(r)
        if let cell = tableView.view(atColumn: 0, row: r, makeIfNecessary: true) as? AchievementCardView {
            cell.flashHighlight()
        }
        _ = row
    }

    // MARK: - Sort modes

    private enum SortMode: Int {
        case defaultOrder, lockedFirst, byPoints, recentlyUnlocked
    }
    private var sortMode: SortMode = .defaultOrder

    // MARK: - Row model (header + section dividers + cards interleaved)

    private enum Row {
        case section(key: String, title: String, unlocked: Int, total: Int, collapsed: Bool)
        case card(RAAchievement)
    }

    // MARK: - Subviews

    private let header = AchievementsHeaderView()
    private let signInBanner = SignInBanner()
    private let toolbar = NSView()
    private let searchField = NSSearchField()
    private let sortDropdown = PillDropdown(
        items: ["Default", "Locked first", "By points", "Recently unlocked"],
        titlePrefix: "Sort: ")
    private let tableView = NSTableView()
    private let scroll = NSScrollView()
    private let emptyView = EmptyStateView()

    // MARK: - State

    private var rows: [Row] = []
    private var collapsedSections = Set<String>()
    private var searchText = ""
    private var observer: NSObjectProtocol?

    // MARK: - Init

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = (theme.skinned ? theme.surfacePanel : .clear).cgColor
        build()
        observer = NotificationCenter.default.addObserver(
            forName: .achievementsChanged, object: nil, queue: .main
        ) { [weak self] _ in self?.render() }
        render()
    }
    required init?(coder: NSCoder) { fatalError() }

    deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 360, height: NSView.noIntrinsicMetric)
    }

    // MARK: - Layout

    private func build() {
        let widthC = widthAnchor.constraint(equalToConstant: 360)
        widthC.priority = .defaultHigh
        widthC.isActive = true

        for v in [header, signInBanner, toolbar, scroll, emptyView] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            addSubview(v)
        }

        // Toolbar: search + sort.
        searchField.placeholderString = "Search achievements"
        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.target = self
        searchField.action = #selector(searchChanged)
        searchField.sendsSearchStringImmediately = false
        searchField.sendsWholeSearchString = false
        sortDropdown.onChange = { [weak self] idx in
            self?.sortMode = SortMode(rawValue: idx) ?? .defaultOrder
            self?.rebuildRows()
        }
        sortDropdown.translatesAutoresizingMaskIntoConstraints = false
        toolbar.addSubview(searchField)
        toolbar.addSubview(sortDropdown)

        // Table of interleaved section headers + cards.
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("card"))
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.intercellSpacing = NSSize(width: 0, height: 8)
        tableView.backgroundColor = .clear
        tableView.selectionHighlightStyle = .none
        tableView.dataSource = self
        tableView.delegate = self
        tableView.usesAutomaticRowHeights = true
        tableView.style = .plain

        scroll.documentView = tableView
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.automaticallyAdjustsContentInsets = false
        scroll.contentInsets = NSEdgeInsets(top: 2, left: 0, bottom: 8, right: 0)

        signInBanner.onSignInHintTapped = { [weak self] in self?.openSignInHelp() }
        emptyView.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: topAnchor),
            header.leadingAnchor.constraint(equalTo: leadingAnchor),
            header.trailingAnchor.constraint(equalTo: trailingAnchor),

            signInBanner.topAnchor.constraint(equalTo: header.bottomAnchor),
            signInBanner.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            signInBanner.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),

            toolbar.topAnchor.constraint(equalTo: signInBanner.bottomAnchor, constant: 8),
            toolbar.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            toolbar.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            toolbar.heightAnchor.constraint(equalToConstant: 28),

            searchField.leadingAnchor.constraint(equalTo: toolbar.leadingAnchor),
            searchField.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),
            searchField.widthAnchor.constraint(equalTo: toolbar.widthAnchor, multiplier: 0.5,
                                               constant: -4),
            sortDropdown.trailingAnchor.constraint(equalTo: toolbar.trailingAnchor),
            sortDropdown.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),
            sortDropdown.leadingAnchor.constraint(equalTo: searchField.trailingAnchor, constant: 8),

            scroll.topAnchor.constraint(equalTo: toolbar.bottomAnchor, constant: 8),
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor),

            emptyView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            emptyView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),
            emptyView.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    // MARK: - Render from gameState

    private func render() {
        let state = Achievements.shared.gameState
        header.apply(state)

        let recognised = state.identification == .recognised
        let loggedOut = state.connection == .loggedOut

        switch state.identification {
        case .noGame:
            showEmpty("No game loaded",
                      "Achievements appear here when you load a game with RetroAchievements support.")
            return
        case .unrecognised:
            showEmpty("Game not recognised",
                      "This game isn’t in the RetroAchievements database yet.",
                      linkTitle: "Browse RetroAchievements.org",
                      linkURL: "https://retroachievements.org")
            return
        case .recognised:
            break
        }

        // Recognised → show list. Sign-in banner only when logged out.
        emptyView.isHidden = true
        scroll.isHidden = false
        toolbar.isHidden = false
        signInBanner.isHidden = !(recognised && loggedOut)
        signInBanner.alphaValue = signInBanner.isHidden ? 0 : 1

        rebuildRows()
    }

    private func showEmpty(_ title: String, _ message: String,
                           linkTitle: String? = nil, linkURL: String? = nil) {
        emptyView.configure(title: title, message: message, linkTitle: linkTitle, linkURL: linkURL)
        emptyView.isHidden = false
        scroll.isHidden = true
        toolbar.isHidden = true
        signInBanner.isHidden = true
    }

    // MARK: - Row building (filter → sort → group into sections)

    private func filteredAchievements() -> [RAAchievement] {
        let all = Achievements.shared.gameState.achievements
        guard !searchText.isEmpty else { return all }
        let q = searchText.lowercased()
        return all.filter {
            $0.title.lowercased().contains(q) || $0.detail.lowercased().contains(q)
        }
    }

    private func sorted(_ list: [RAAchievement]) -> [RAAchievement] {
        switch sortMode {
        case .defaultOrder:
            return list
        case .lockedFirst:
            return list.enumerated().sorted {
                let la = $0.element.state == .locked ? 0 : 1
                let lb = $1.element.state == .locked ? 0 : 1
                return la != lb ? la < lb : $0.offset < $1.offset
            }.map { $0.element }
        case .byPoints:
            return list.enumerated().sorted {
                $0.element.points != $1.element.points
                    ? $0.element.points > $1.element.points
                    : $0.offset < $1.offset
            }.map { $0.element }
        case .recentlyUnlocked:
            return list.enumerated().sorted {
                let ta = $0.element.unlockTime ?? .distantPast
                let tb = $1.element.unlockTime ?? .distantPast
                return ta != tb ? ta > tb : $0.offset < $1.offset
            }.map { $0.element }
        }
    }

    // Group cards into collapsible Core / Unofficial sections.
    private func rebuildRows() {
        let list = sorted(filteredAchievements())
        let core = list.filter { $0.category == .core }
        let unofficial = list.filter { $0.category == .unofficial }

        var newRows: [Row] = []
        func appendSection(key: String, title: String, items: [RAAchievement]) {
            guard !items.isEmpty else { return }
            let unlocked = items.filter { $0.state != .locked }.count
            let collapsed = collapsedSections.contains(key)
            // Only show a section header if there is more than one section.
            newRows.append(.section(key: key, title: title,
                                    unlocked: unlocked, total: items.count, collapsed: collapsed))
            if !collapsed { for a in items { newRows.append(.card(a)) } }
        }
        // If only Core exists, still show a single section header for the unlock count.
        appendSection(key: "core", title: "Core", items: core)
        appendSection(key: "unofficial", title: "Unofficial", items: unofficial)

        rows = newRows
        tableView.reloadData()
    }

    // MARK: - Helpers for focus()

    private func rowIndex(forAchievement id: UInt32) -> Int? {
        rows.firstIndex {
            if case let .card(a) = $0 { return a.id == id }
            return false
        }
    }

    private func sectionContaining(achievement id: UInt32) -> String? {
        let all = Achievements.shared.gameState.achievements
        guard let a = all.first(where: { $0.id == id }) else { return nil }
        return a.category == .core ? "core" : "unofficial"
    }

    // MARK: - Actions

    @objc private func searchChanged() {
        searchText = searchField.stringValue.trimmingCharacters(in: .whitespaces)
        rebuildRows()
    }

    private func toggleSection(_ key: String) {
        if collapsedSections.contains(key) { collapsedSections.remove(key) }
        else { collapsedSections.insert(key) }
        rebuildRows()
    }

    private func openSignInHelp() {
        // Open the in-app RetroAchievements login (Preferences ▸ Achievements ▸ Account),
        // not the website — that's where the user actually signs in.
        let app = NSApp.delegate as? AppDelegate
        app?.showPreferences(nil)
        app?.preferences?.selectSection(0) // Achievements (Account) is the first tab
    }
}

// MARK: - Table data source / delegate

extension AchievementsDrawer: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?,
                   row: Int) -> NSView? {
        switch rows[row] {
        case let .section(key, title, unlocked, total, collapsed):
            let id = NSUserInterfaceItemIdentifier("section")
            let view = tableView.makeView(withIdentifier: id, owner: nil) as? SectionHeaderView ?? {
                let v = SectionHeaderView(); v.identifier = id; return v
            }()
            view.configure(title: title, unlocked: unlocked, total: total, collapsed: collapsed)
            view.onToggle = { [weak self] in self?.toggleSection(key) }
            return view
        case let .card(achievement):
            let id = NSUserInterfaceItemIdentifier("card")
            let view = tableView.makeView(withIdentifier: id, owner: nil) as? AchievementCardView ?? {
                let v = AchievementCardView(); v.identifier = id; return v
            }()
            let readOnly = Achievements.shared.gameState.connection == .loggedOut
            view.configure(achievement, readOnly: readOnly)
            return view
        }
    }

    // Selection disabled; cards aren't selectable rows.
    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool { false }
}
