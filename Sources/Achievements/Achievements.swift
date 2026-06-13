// T3d Boy — RetroAchievements façade (the achievement subsystem's entry point).
//
// The rest of the emulator depends ONLY on this small surface. The subsystem is
// fully optional: if rc_client can't initialise (or the network is unreachable),
// `isAvailable` stays false and every call is a safe no-op, so the emulator runs
// exactly as it does today.
//
// Threading: rc_client is single-threaded. Everything here runs on the MAIN queue
// — the host calls doFrame() on the main queue once per emulated frame, server
// responses are marshalled back to the main queue (see RAServer), and rc_client
// events fire synchronously inside do_frame. So all access is main-queue serial.

import Foundation
import rcheevos

final class Achievements {
    static let shared = Achievements()

    private var client: OpaquePointer? // rc_client_t*
    private(set) var isAvailable = false

    /// The published, UI-facing snapshot. Always read/written on the main queue.
    private(set) var gameState: RAGameState = .empty
    /// The logged-in account, or nil when logged out.
    private(set) var account: RAAccount?

    private let tokenStore: RATokenStoring = KeychainTokenStore()

    /// Whether RA hardcore mode is requested. We default OFF; the host opts in.
    private var hardcoreRequested = false
    /// Set when the user disables hardcore for the current run only (escape hatch).
    private var hardcoreSessionDisabled = false
    /// Whether unofficial achievements should be loaded (off by default).
    private var unofficialEnabled = false

    /// Console id of the game currently being / last loaded (for hashing & summary).
    private var currentConsole: UInt32 = UInt32(RC_CONSOLE_GAMEBOY)

    /// The most recently loaded ROM, retained so signing in can trigger the full
    /// (authenticated) load of a game that was only hash-recognised while logged out.
    private var lastROM: [UInt8]?
    private var lastCGB = false

    private init() {}

    // MARK: - Ownership
    //
    // rc_client holds exactly one game at a time, so exactly one piece of UI "owns"
    // the runtime: the frontmost game window while playing, or the library while
    // browsing (preview). Whoever claims ownership is responsible for loading its
    // game and releasing on teardown. A playing game outranks a library preview —
    // the library checks `owner` before claiming so it never clobbers a live session.
    private(set) weak var owner: AnyObject?

    /// Claim the runtime for `o`. Returns true if ownership changed (caller should
    /// (re)load its game); false if `o` already owned it.
    @discardableResult
    func claimOwnership(_ o: AnyObject) -> Bool {
        if owner === o { return false }
        owner = o
        return true
    }

    /// Release ownership if `o` currently holds it.
    func resignOwnership(_ o: AnyObject) {
        if owner === o { owner = nil }
    }

    func isOwner(_ o: AnyObject) -> Bool { owner === o }

    var isLoggedIn: Bool {
        guard let client else { return false }
        return rc_client_get_user_info(client) != nil
    }

    /// True once rc_client has a fully loaded (authenticated) game.
    var isGameLoaded: Bool {
        guard let client else { return false }
        return rc_client_is_game_loaded(client) != 0
    }

    // MARK: - Lifecycle

    /// Create the rc_client and its callbacks. Idempotent; safe to call repeatedly.
    func start() {
        guard client == nil else { return }
        guard let c = rc_client_create(RAMemory.callback, RAServer.callback) else {
            isAvailable = false
            return
        }
        client = c
        isAvailable = true

        rc_client_set_hardcore_enabled(c, hardcoreRequested ? 1 : 0)
        rc_client_set_unofficial_enabled(c, unofficialEnabled ? 1 : 0)
        // We only read memory inside do_frame, never in the background.
        rc_client_set_allow_background_memory_reads(c, 0)
        rc_client_set_event_handler(c, Achievements.eventHandler)

        rebuildState()
    }

    func stop() {
        if let c = client {
            rc_client_unload_game(c)
            rc_client_destroy(c)
        }
        client = nil
        isAvailable = false
        account = nil
        gameState = .empty
    }

    // MARK: - Game load / unload

    /// Identify and load a ROM. Hashing + identification happen inside rcheevos.
    /// Safe to call when logged out — a read-only achievement list still loads.
    func loadGame(rom: [UInt8], cgb: Bool) {
        guard let client else { return }
        currentConsole = UInt32(cgb ? RC_CONSOLE_GAMEBOY_COLOR : RC_CONSOLE_GAMEBOY)
        // Remember the ROM so a later sign-in can trigger the full load.
        lastROM = rom
        lastCGB = cgb

        // Show a "loading / no game yet" placeholder immediately.
        gameState = .empty
        gameState.consoleBadge = cgb ? "GBC" : "GB"
        publish()

        guard isLoggedIn else {
            // rc_client refuses to load a game until a user is signed in (it returns
            // RC_LOGIN_REQUIRED before hashing), and RA's achievement-list endpoint
            // needs auth. But the hash→game_id lookup is public, so we resolve the
            // hash directly to tell the user whether this ROM is recognised and
            // invite them to sign in for the full list.
            resolveHashLoggedOut(rom: rom, cgb: cgb)
            return
        }

        rom.withUnsafeBufferPointer { buf in
            _ = rc_client_begin_identify_and_load_game(
                client, currentConsole, nil,
                buf.baseAddress, buf.count,
                Achievements.loadGameCallback, nil)
        }
    }

    /// Logged-out recognition: resolve the ROM hash via RA's public hash endpoint
    /// (no credentials) and flip identification to .recognised / .unrecognised so the
    /// drawer can show the "sign in to view achievements" invitation.
    private func resolveHashLoggedOut(rom: [UInt8], cgb: Bool) {
        guard let hash = RAHash.hash(rom: rom, cgb: cgb) else {
            gameState.identification = .unrecognised
            rebuildState()
            return
        }

        var apiReq = rc_api_request_t()
        var params = rc_api_resolve_hash_request_t()
        let initOK: Int32 = hash.withCString { h in
            params.game_hash = h
            return rc_api_init_resolve_hash_request(&apiReq, &params)
        }
        guard initOK == RC_OK, let urlPtr = apiReq.url else {
            rc_api_destroy_request(&apiReq)
            gameState.identification = .unrecognised
            rebuildState()
            return
        }
        let urlStr = String(cString: urlPtr)
        let post = apiReq.post_data.map { String(cString: $0) }
        let contentType = apiReq.content_type.map { String(cString: $0) }
        rc_api_destroy_request(&apiReq)

        guard let url = URL(string: urlStr) else {
            gameState.identification = .unrecognised
            rebuildState()
            return
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = 30
        if let post, !post.isEmpty {
            req.httpMethod = "POST"
            req.httpBody = post.data(using: .utf8)
            if let contentType { req.setValue(contentType, forHTTPHeaderField: "Content-Type") }
        }
        if RAServer.verboseLogging {
            print("[RA] \(req.httpMethod ?? "GET") resolve_hash \(hash)")
        }

        URLSession.shared.dataTask(with: req) { [weak self] data, response, error in
            let status = Int32((response as? HTTPURLResponse)?.statusCode ?? 0)
            var gameId: UInt32 = 0
            var transportFailed = (error != nil)
            if !transportFailed {
                let payload = data ?? Data()
                payload.withUnsafeBytes { raw in
                    var sresp = rc_api_server_response_t()
                    sresp.body = raw.bindMemory(to: CChar.self).baseAddress
                    sresp.body_length = payload.count
                    sresp.http_status_code = status
                    var hresp = rc_api_resolve_hash_response_t()
                    if rc_api_process_resolve_hash_server_response(&hresp, &sresp) == RC_OK {
                        gameId = hresp.game_id
                    } else {
                        transportFailed = true
                    }
                    rc_api_destroy_resolve_hash_response(&hresp)
                }
            }
            DispatchQueue.main.async {
                guard let self else { return }
                if transportFailed {
                    self.gameState.errorMessage = "Couldn't reach RetroAchievements"
                    self.gameState.identification = .unrecognised
                } else {
                    self.gameState.identification = gameId != 0 ? .recognised : .unrecognised
                }
                if RAServer.verboseLogging {
                    print("[RA] resolve_hash → gameId=\(gameId) identification=\(self.gameState.identification) transportFailed=\(transportFailed)")
                }
                self.rebuildState()
            }
        }.resume()
    }

    func unloadGame() {
        guard let client else { return }
        rc_client_unload_game(client)
        lastROM = nil
        gameState = .empty
        publish()
    }

    /// Tell rcheevos the emulator was reset (resets achievement/leaderboard state).
    func reset() {
        guard let client else { return }
        rc_client_reset(client)
        rebuildState()
    }

    /// Process one emulated frame. Host calls this on the main queue, once per
    /// frame, only while emulation is running (not paused).
    func doFrame() {
        guard let client else { return }
        rc_client_do_frame(client)
    }

    /// Process the periodic queue while paused (keeps server retries flowing).
    func idle() {
        guard let client else { return }
        rc_client_idle(client)
    }

    /// Lightweight reachability probe: an unauthenticated resolve_hash round-trip.
    /// Invokes completion(true) on the main queue if RA's server answered at all.
    func testConnection(completion: @escaping (Bool) -> Void) {
        var apiReq = rc_api_request_t()
        var params = rc_api_resolve_hash_request_t()
        let probe = String(repeating: "0", count: 32)
        let initOK: Int32 = probe.withCString { h in
            params.game_hash = h
            return rc_api_init_resolve_hash_request(&apiReq, &params)
        }
        guard initOK == RC_OK, let urlPtr = apiReq.url,
              let url = URL(string: String(cString: urlPtr)) else {
            rc_api_destroy_request(&apiReq)
            DispatchQueue.main.async { completion(false) }
            return
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = 15
        if let post = apiReq.post_data.map({ String(cString: $0) }), !post.isEmpty {
            req.httpMethod = "POST"
            req.httpBody = post.data(using: .utf8)
            if let ct = apiReq.content_type.map({ String(cString: $0) }) {
                req.setValue(ct, forHTTPHeaderField: "Content-Type")
            }
        }
        rc_api_destroy_request(&apiReq)
        URLSession.shared.dataTask(with: req) { _, response, error in
            let ok = error == nil
                && ((response as? HTTPURLResponse).map { $0.statusCode < 500 } ?? false)
            DispatchQueue.main.async { completion(ok) }
        }.resume()
    }

    // MARK: - Authentication

    func login(username: String, password: String,
               completion: @escaping (Result<Void, Error>) -> Void) {
        guard let client else {
            completion(.failure(RAError.unavailable)); return
        }
        let box = LoginBox(completion: completion)
        let userdata = Unmanaged.passRetained(box).toOpaque()
        username.withCString { u in
            password.withCString { p in
                _ = rc_client_begin_login_with_password(
                    client, u, p, Achievements.loginCallback, userdata)
            }
        }
    }

    /// Attempt a silent login using the token saved in the Keychain.
    func loginWithStoredToken(completion: @escaping (Result<Void, Error>) -> Void) {
        guard let client else { completion(.failure(RAError.unavailable)); return }
        guard let cred = tokenStore.load() else {
            completion(.failure(RAError.noStoredToken)); return
        }
        let box = LoginBox(completion: completion)
        let userdata = Unmanaged.passRetained(box).toOpaque()
        cred.username.withCString { u in
            cred.token.withCString { t in
                _ = rc_client_begin_login_with_token(
                    client, u, t, Achievements.loginCallback, userdata)
            }
        }
    }

    func logout() {
        if let client { rc_client_logout(client) }
        tokenStore.clear()
        account = nil
        rebuildState()
    }

    /// Opt into / out of hardcore mode. Enabling it with a game loaded raises an
    /// RC_CLIENT_EVENT_RESET; the host should reset the emulator in response.
    /// An explicit toggle clears any session-only override.
    func setHardcore(_ enabled: Bool) {
        hardcoreRequested = enabled
        hardcoreSessionDisabled = false
        guard let client else { return }
        rc_client_set_hardcore_enabled(client, enabled ? 1 : 0)
        rebuildState()
    }

    /// Escape hatch: turn hardcore off for the rest of this run without changing the
    /// saved preference, so a restricted action (e.g. loading a save state) can
    /// proceed. rcheevos drops to softcore; the next launch restores the preference.
    func disableHardcoreForSession() {
        hardcoreSessionDisabled = true
        guard let client else { return }
        rc_client_set_hardcore_enabled(client, 0)
        rebuildState()
    }

    /// True when the requested action must be blocked because hardcore is active.
    /// The host uses this to gate save-state load, rewind, cheats, speed-up, etc.
    func hardcoreBlocks(_ action: RAHardcoreAction) -> Bool {
        guard let client, rc_client_get_hardcore_enabled(client) != 0 else { return false }
        return action.blockedInHardcore
    }

    // MARK: - C callbacks (non-capturing)

    private static let loadGameCallback: rc_client_callback_t = { result, errorMessage, _, _ in
        // Always runs on the main queue (server responses are marshalled there).
        Achievements.shared.handleLoadResult(result: result, errorMessage: errorMessage)
    }

    private static let loginCallback: rc_client_callback_t = { result, errorMessage, _, userdata in
        guard let userdata else { return }
        let box = Unmanaged<LoginBox>.fromOpaque(userdata).takeRetainedValue()
        let a = Achievements.shared
        if result == RC_OK {
            a.persistTokenAfterLogin()
            a.rebuildState()
            box.completion(.success(()))
            // A game that was only hash-recognised while logged out can now be
            // fully loaded (achievement list, unlocks) under the authenticated user.
            if !a.isGameLoaded, let rom = a.lastROM {
                a.loadGame(rom: rom, cgb: a.lastCGB)
            }
        } else {
            let msg = errorMessage.map { String(cString: $0) } ?? "Login failed"
            a.rebuildState()
            box.completion(.failure(RAError.server(msg)))
        }
    }

    private static let eventHandler: rc_client_event_handler_t = { event, _ in
        guard let event else { return }
        Achievements.shared.handle(event: event.pointee)
    }

    // MARK: - Result / event handling (main queue)

    private func handleLoadResult(result: Int32, errorMessage: UnsafePointer<CChar>?) {
        guard let client else { return }
        if result == RC_OK {
            if rc_client_get_game_info(client) != nil {
                gameState.identification = rc_client_is_game_loaded(client) != 0
                    ? .recognised : .unrecognised
            }
        } else if result == RC_NO_GAME_LOADED || rc_client_get_game_info(client) == nil {
            gameState.identification = .unrecognised
        } else {
            // Network/other error: leave list empty, surface a non-blocking chip.
            gameState.identification = .unrecognised
            gameState.errorMessage = errorMessage.map { String(cString: $0) }
        }
        rebuildState()
    }

    private func handle(event: rc_client_event_t) {
        switch event.type {
        case UInt32(RC_CLIENT_EVENT_ACHIEVEMENT_TRIGGERED):
            if let ach = event.achievement {
                let id = ach.pointee.id
                NotificationCenter.default.post(
                    name: .achievementUnlocked, object: nil, userInfo: ["id": id])
            }
            rebuildState()

        case UInt32(RC_CLIENT_EVENT_GAME_COMPLETED):
            // userInfo keys match AchievementToast's expectations (type/title/...).
            postEvent(["type": "mastery",
                       "title": gameState.title,
                       "hardcore": gameState.hardcore,
                       "badgeURL": gameState.boxArtURL as Any])
            rebuildState()

        case UInt32(RC_CLIENT_EVENT_SUBSET_COMPLETED):
            postEvent(["type": "mastery", "title": gameState.title,
                       "hardcore": gameState.hardcore])
            rebuildState()

        case UInt32(RC_CLIENT_EVENT_LEADERBOARD_STARTED):
            if let lb = event.leaderboard {
                postEvent(["type": "leaderboardStart",
                           "id": lb.pointee.id,
                           "title": lb.pointee.title.map { String(cString: $0) } ?? ""])
            }
            rebuildState()

        case UInt32(RC_CLIENT_EVENT_LEADERBOARD_SUBMITTED):
            if let lb = event.leaderboard {
                let value = lb.pointee.tracker_value.map { String(cString: $0) } ?? ""
                postEvent(["type": "leaderboardSubmit",
                           "id": lb.pointee.id,
                           "title": lb.pointee.title.map { String(cString: $0) } ?? "",
                           "value": value])
            }
            rebuildState()

        case UInt32(RC_CLIENT_EVENT_LEADERBOARD_FAILED):
            if let lb = event.leaderboard {
                postEvent(["type": "leaderboardCancel",
                           "id": lb.pointee.id,
                           "title": lb.pointee.title.map { String(cString: $0) } ?? ""])
            }
            rebuildState()

        case UInt32(RC_CLIENT_EVENT_LEADERBOARD_TRACKER_SHOW),
             UInt32(RC_CLIENT_EVENT_LEADERBOARD_TRACKER_HIDE),
             UInt32(RC_CLIENT_EVENT_LEADERBOARD_TRACKER_UPDATE):
            rebuildState()

        case UInt32(RC_CLIENT_EVENT_ACHIEVEMENT_CHALLENGE_INDICATOR_SHOW),
             UInt32(RC_CLIENT_EVENT_ACHIEVEMENT_CHALLENGE_INDICATOR_HIDE),
             UInt32(RC_CLIENT_EVENT_ACHIEVEMENT_PROGRESS_INDICATOR_SHOW),
             UInt32(RC_CLIENT_EVENT_ACHIEVEMENT_PROGRESS_INDICATOR_HIDE),
             UInt32(RC_CLIENT_EVENT_ACHIEVEMENT_PROGRESS_INDICATOR_UPDATE):
            rebuildState()

        case UInt32(RC_CLIENT_EVENT_RESET):
            // Hardcore was enabled mid-game: the host must reset the emulator.
            postEvent(["type": "reset"])

        case UInt32(RC_CLIENT_EVENT_SERVER_ERROR):
            let msg = event.server_error?.pointee.error_message.map { String(cString: $0) }
            gameState.errorMessage = msg ?? "Server error"
            postEvent(["type": "serverError", "message": gameState.errorMessage ?? ""])
            publish()

        case UInt32(RC_CLIENT_EVENT_DISCONNECTED):
            gameState.connection = .offline
            postEvent(["type": "disconnected"])
            publish()

        case UInt32(RC_CLIENT_EVENT_RECONNECTED):
            rebuildState()

        default:
            break
        }
    }

    private func postEvent(_ info: [AnyHashable: Any]) {
        NotificationCenter.default.post(name: .achievementEvent, object: nil, userInfo: info)
    }

    // MARK: - Token persistence

    private func persistTokenAfterLogin() {
        guard let client, let info = rc_client_get_user_info(client) else { return }
        let username = info.pointee.username.map { String(cString: $0) }
            ?? (info.pointee.display_name.map { String(cString: $0) } ?? "")
        guard let tokenPtr = info.pointee.token else { return }
        let token = String(cString: tokenPtr)
        guard !username.isEmpty, !token.isEmpty else { return }
        tokenStore.save(RACredential(username: username, token: token))
    }

    // MARK: - State assembly

    /// Rebuild `gameState` and `account` from rc_client, then publish.
    private func rebuildState() {
        guard let client else {
            gameState = .empty
            account = nil
            publish()
            return
        }

        var state = RAGameState.empty

        // Account / connection.
        if let user = rc_client_get_user_info(client) {
            let name = user.pointee.display_name.map { String(cString: $0) }
                ?? (user.pointee.username.map { String(cString: $0) } ?? "")
            account = RAAccount(username: name,
                                avatarURL: Self.userImageURL(user),
                                points: Int(user.pointee.score))
            state.connection = .loggedIn
        } else {
            account = nil
            state.connection = .loggedOut
        }
        if state.connection == .loggedIn, gameState.connection == .offline {
            // A DISCONNECTED event sets offline; keep it until RECONNECTED.
            state.connection = .offline
        }

        state.hardcore = rc_client_get_hardcore_enabled(client) != 0

        // Game. rc_client returns a dummy game record for an unidentified ROM, so
        // distinguish "recognised" via rc_client_is_game_loaded.
        if let game = rc_client_get_game_info(client) {
            state.title = game.pointee.title.map { String(cString: $0) } ?? ""
            state.boxArtURL = Self.gameImageURL(game)
            state.identification = rc_client_is_game_loaded(client) != 0 ? .recognised : .unrecognised
        } else {
            // No game record at all: keep whatever the load result decided (noGame
            // initially, or unrecognised after a failed identify).
            state.identification = gameState.identification
        }
        state.consoleBadge = currentConsole == UInt32(RC_CONSOLE_GAMEBOY_COLOR) ? "GBC" : "GB"

        // Achievements + summary.
        if rc_client_is_game_loaded(client) != 0 {
            state.achievements = Self.collectAchievements(client)

            var summary = rc_client_user_game_summary_t()
            rc_client_get_user_game_summary(client, &summary)
            state.unlockedCount = Int(summary.num_unlocked_achievements)
            state.totalCount = Int(summary.num_core_achievements)
            state.pointsEarned = Int(summary.points_unlocked)
            state.pointsTotal = Int(summary.points_core)

            // Rich presence.
            if rc_client_has_rich_presence(client) != 0 {
                var buf = [CChar](repeating: 0, count: 256)
                let n = rc_client_get_rich_presence_message(client, &buf, buf.count)
                if n > 0 { state.richPresence = String(cString: buf) }
            }

            state.leaderboards = Self.collectLeaderboardTrackers(client)
        }

        // Preserve a transient error chip across rebuilds (cleared on next load).
        if state.errorMessage == nil { state.errorMessage = gameState.errorMessage }

        gameState = state
        publish()
    }

    private static func collectAchievements(_ client: OpaquePointer) -> [RAAchievement] {
        let category = RC_CLIENT_ACHIEVEMENT_CATEGORY_CORE_AND_UNOFFICIAL
        let grouping = RC_CLIENT_ACHIEVEMENT_LIST_GROUPING_PROGRESS
        guard let list = rc_client_create_achievement_list(client, Int32(category), Int32(grouping))
        else { return [] }
        defer { rc_client_destroy_achievement_list(list) }

        var result: [RAAchievement] = []
        let buckets = list.pointee.buckets
        for b in 0 ..< Int(list.pointee.num_buckets) {
            let bucket = buckets![b]
            let bucketType = bucket.bucket_type
            for i in 0 ..< Int(bucket.num_achievements) {
                guard let a = bucket.achievements?[i] else { continue }
                result.append(mapAchievement(a.pointee, bucketType: bucketType))
            }
        }
        return result
    }

    private static func mapAchievement(_ a: rc_client_achievement_t,
                                       bucketType: UInt8) -> RAAchievement {
        let unlock: RAUnlock
        if a.state == UInt8(RC_CLIENT_ACHIEVEMENT_STATE_UNLOCKED) {
            unlock = (a.unlocked & UInt8(RC_CLIENT_ACHIEVEMENT_UNLOCKED_HARDCORE)) != 0
                ? .unlockedHardcore : .unlockedSoftcore
        } else {
            unlock = .locked
        }

        let category: RACategory = a.category == UInt8(RC_CLIENT_ACHIEVEMENT_CATEGORY_UNOFFICIAL)
            ? .unofficial : .core

        let primed = bucketType == UInt8(RC_CLIENT_ACHIEVEMENT_BUCKET_ACTIVE_CHALLENGE)

        var measuredPercent: Float? = nil
        var measuredProgress: String? = nil
        if unlock == .locked, a.measured_percent > 0 {
            measuredPercent = a.measured_percent / 100.0
            let progress = withUnsafeBytes(of: a.measured_progress) { raw -> String in
                String(cString: raw.bindMemory(to: CChar.self).baseAddress!)
            }
            if !progress.isEmpty { measuredProgress = progress }
        }

        var unlockTime: Date? = nil
        if a.unlock_time != 0 { unlockTime = Date(timeIntervalSince1970: TimeInterval(a.unlock_time)) }

        let lockedURL = a.badge_locked_url.map { String(cString: $0) }
            ?? achievementImageURL(a, state: Int32(RC_CLIENT_ACHIEVEMENT_STATE_INACTIVE))
        let unlockedURL = a.badge_url.map { String(cString: $0) }
            ?? achievementImageURL(a, state: Int32(RC_CLIENT_ACHIEVEMENT_STATE_UNLOCKED))

        return RAAchievement(
            id: a.id,
            title: a.title.map { String(cString: $0) } ?? "",
            detail: a.description.map { String(cString: $0) } ?? "",
            points: Int(a.points),
            badgeURLLocked: lockedURL,
            badgeURLUnlocked: unlockedURL,
            state: unlock,
            category: category,
            isMissable: a.type == UInt8(RC_CLIENT_ACHIEVEMENT_TYPE_MISSABLE),
            isProgression: a.type == UInt8(RC_CLIENT_ACHIEVEMENT_TYPE_PROGRESSION),
            isWinCondition: a.type == UInt8(RC_CLIENT_ACHIEVEMENT_TYPE_WIN),
            measuredPercent: measuredPercent,
            measuredProgress: measuredProgress,
            isPrimed: primed,
            unlockTime: unlockTime)
    }

    private static func collectLeaderboardTrackers(_ client: OpaquePointer) -> [RALeaderboardTracker] {
        // Only the actively-tracking leaderboards have a visible tracker value.
        let grouping = RC_CLIENT_LEADERBOARD_LIST_GROUPING_TRACKING
        guard let list = rc_client_create_leaderboard_list(client, Int32(grouping))
        else { return [] }
        defer { rc_client_destroy_leaderboard_list(list) }

        var result: [RALeaderboardTracker] = []
        let buckets = list.pointee.buckets
        for b in 0 ..< Int(list.pointee.num_buckets) {
            let bucket = buckets![b]
            guard bucket.bucket_type == UInt8(RC_CLIENT_LEADERBOARD_BUCKET_ACTIVE) else { continue }
            for i in 0 ..< Int(bucket.num_leaderboards) {
                guard let lb = bucket.leaderboards?[i] else { continue }
                let value = lb.pointee.tracker_value.map { String(cString: $0) } ?? ""
                result.append(RALeaderboardTracker(
                    id: lb.pointee.id,
                    title: lb.pointee.title.map { String(cString: $0) } ?? "",
                    value: value))
            }
        }
        return result
    }

    // MARK: - Image URL helpers

    private static func userImageURL(_ user: UnsafePointer<rc_client_user_t>) -> String? {
        if let url = user.pointee.avatar_url { return String(cString: url) }
        var buf = [CChar](repeating: 0, count: 256)
        return rc_client_user_get_image_url(user, &buf, buf.count) == RC_OK
            ? String(cString: buf) : nil
    }

    private static func gameImageURL(_ game: UnsafePointer<rc_client_game_t>) -> String? {
        if let url = game.pointee.badge_url { return String(cString: url) }
        var buf = [CChar](repeating: 0, count: 256)
        return rc_client_game_get_image_url(game, &buf, buf.count) == RC_OK
            ? String(cString: buf) : nil
    }

    private static func achievementImageURL(_ a: rc_client_achievement_t, state: Int32) -> String? {
        var copy = a
        var buf = [CChar](repeating: 0, count: 256)
        let ok = rc_client_achievement_get_image_url(&copy, state, &buf, buf.count)
        return ok == RC_OK ? String(cString: buf) : nil
    }

    // MARK: - Publish

    private func publish() {
        // Always on the main queue (all entry points are main-queue).
        NotificationCenter.default.post(name: .achievementsChanged, object: nil)
    }

    // Boxed completion handler so we can round-trip through a C void* userdata.
    private final class LoginBox {
        let completion: (Result<Void, Error>) -> Void
        init(completion: @escaping (Result<Void, Error>) -> Void) { self.completion = completion }
    }
}

/// Actions the host may want to gate while RA hardcore is active.
enum RAHardcoreAction {
    case loadSaveState
    case rewind
    case cheat
    case slowMotion
    case fastForward   // RA permits fast-forward; listed for completeness

    var blockedInHardcore: Bool {
        switch self {
        case .loadSaveState, .rewind, .cheat, .slowMotion: return true
        case .fastForward: return false
        }
    }
}

enum RAError: Error, CustomStringConvertible {
    case unavailable
    case noStoredToken
    case server(String)

    var description: String {
        switch self {
        case .unavailable: return "RetroAchievements is unavailable."
        case .noStoredToken: return "No saved RetroAchievements login."
        case .server(let m): return m
        }
    }
}
