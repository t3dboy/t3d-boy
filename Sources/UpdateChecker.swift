// T3d Boy — lightweight update checker (check & notify).
//
// Asks the GitHub Releases API whether a newer version has shipped and compares it to
// the running bundle version. We never download or install anything automatically: the
// user clicks Download in the prompt, which opens the .dmg in their browser. The check
// is HTTPS-only, sends a User-Agent (GitHub requires one), and is fully opt-out from
// Preferences ▸ Appearance. "Skip this version" suppresses reminders for one release;
// future releases still notify.

import Foundation

enum UpdateChecker {
    /// The public repo the releases live in.
    static let releasesAPI  = "https://api.github.com/repos/t3dboy/t3d-boy/releases/latest"
    static let releasesPage = "https://github.com/t3dboy/t3d-boy/releases/latest"

    struct Release {
        let version: String      // normalised, no leading "v"
        let displayName: String  // release title
        let notes: String        // release body (markdown)
        let pageURL: URL
        let dmgURL: URL?         // the .dmg asset, if the release has one
    }

    enum Outcome {
        case upToDate
        case available(Release)
        case failed(String)
    }

    // MARK: - Settings (UserDefaults-backed)

    private static let defaults = UserDefaults.standard
    private enum Key {
        static let autoCheck = "update.autoCheck"
        static let skipped   = "update.skippedVersion"
        static let lastCheck = "update.lastCheck"
    }

    static func registerDefaults() {
        defaults.register(defaults: [Key.autoCheck: true])
    }

    /// Whether to check on launch. On by default; toggled in Preferences ▸ Appearance.
    static var autoCheckEnabled: Bool {
        get { defaults.bool(forKey: Key.autoCheck) }
        set { defaults.set(newValue, forKey: Key.autoCheck) }
    }

    /// The version the user asked to stop being reminded about.
    static var skippedVersion: String? {
        get { defaults.string(forKey: Key.skipped) }
        set { defaults.set(newValue, forKey: Key.skipped) }
    }

    /// The running app version (CFBundleShortVersionString), normalised.
    static var currentVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
        return normalise(v)
    }

    // MARK: - Checking

    /// Check GitHub for a newer release. `force` bypasses the auto-check throttle and is
    /// used by the manual "Check for Updates…" menu item. Completion fires on the main queue.
    static func check(force: Bool, completion: @escaping (Outcome) -> Void) {
        if !force {
            let last = defaults.double(forKey: Key.lastCheck)
            let now = Date().timeIntervalSince1970
            // Don't pester on every relaunch — auto-check at most twice a day.
            if last > 0, now - last < 12 * 3600 { completion(.upToDate); return }
        }
        guard let url = URL(string: releasesAPI), url.scheme == "https" else {
            completion(.failed("Couldn't build the update URL.")); return
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = 15
        req.setValue("T3dBoy/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        URLSession.shared.dataTask(with: req) { data, response, error in
            defaults.set(Date().timeIntervalSince1970, forKey: Key.lastCheck)
            func done(_ o: Outcome) { DispatchQueue.main.async { completion(o) } }

            if let error { done(.failed(error.localizedDescription)); return }
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  let data,
                  let payload = try? JSONDecoder().decode(GitHubRelease.self, from: data)
            else { done(.failed("Couldn't read the latest release.")); return }

            let latest = normalise(payload.tag_name)
            guard !latest.isEmpty else { done(.failed("No release found.")); return }
            if compare(latest, currentVersion) <= 0 { done(.upToDate); return }

            // Prefer the .dmg asset; fall back to the release page. HTTPS only.
            let dmgURL = payload.assets?
                .first { $0.name.lowercased().hasSuffix(".dmg") }
                .flatMap { URL(string: $0.browser_download_url) }
                .flatMap { $0.scheme == "https" ? $0 : nil }
            let page = URL(string: payload.html_url).flatMap { $0.scheme == "https" ? $0 : nil }
                ?? URL(string: releasesPage)!

            done(.available(Release(
                version: latest,
                displayName: (payload.name?.isEmpty == false) ? payload.name! : "T3d Boy \(latest)",
                notes: payload.body ?? "",
                pageURL: page,
                dmgURL: dmgURL)))
        }.resume()
    }

    /// A sample release for previewing the update prompt without a real newer build.
    /// Triggered by the `T3DBOY_UPDATE_PREVIEW` environment variable on launch.
    static var isPreview: Bool { ProcessInfo.processInfo.environment["T3DBOY_UPDATE_PREVIEW"] != nil }
    static var previewRelease: Release {
        Release(
            version: "9.9.9",
            displayName: "T3d Boy 9.9.9",
            notes: """
            ## What's new

            - **Sample feature** — this is a preview of the update prompt, so you can see
              how release notes look here.
            - Faster boot chime and a couple of palette tweaks.
            - Fixed a rare hang when loading some MBC5 saves.

            ### Under the hood
            - Tidied the audio ring buffer.

            Full changelog: https://github.com/t3dboy/t3d-boy/blob/main/CHANGELOG.md
            """,
            pageURL: URL(string: releasesPage)!,
            dmgURL: nil)
    }

    // MARK: - Version helpers

    static func normalise(_ s: String) -> String {
        var v = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if v.first == "v" || v.first == "V" { v.removeFirst() }
        return v
    }

    /// Compare dotted numeric versions. Returns -1 if a<b, 0 if equal, 1 if a>b.
    static func compare(_ a: String, _ b: String) -> Int {
        let pa = a.split(separator: ".").map { Int($0.prefix { $0.isNumber }) ?? 0 }
        let pb = b.split(separator: ".").map { Int($0.prefix { $0.isNumber }) ?? 0 }
        for i in 0 ..< max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0
            let y = i < pb.count ? pb[i] : 0
            if x != y { return x < y ? -1 : 1 }
        }
        return 0
    }

    // MARK: - GitHub JSON

    private struct GitHubRelease: Decodable {
        let tag_name: String
        let name: String?
        let body: String?
        let html_url: String
        let assets: [Asset]?
        struct Asset: Decodable { let name: String; let browser_download_url: String }
    }
}
