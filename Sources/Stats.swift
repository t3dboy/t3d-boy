// T3d Boy — per-ROM play statistics: total time played and play count.
// Stored as JSON keyed by ROM path, same convention as Favourites.

import Foundation

final class PlayStats {
    static let shared = PlayStats()
    static let changed = Notification.Name("T3dBoyStatsChanged")

    private let file: URL
    private var entries: [String: [String: Double]]

    init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("T3d Boy", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        file = dir.appendingPathComponent("stats.json")
        if let data = try? Data(contentsOf: file),
           let dict = try? JSONSerialization.jsonObject(with: data) as? [String: [String: Double]] {
            entries = dict
        } else {
            entries = [:]
        }
    }

    func stats(for url: URL) -> (seconds: Int, plays: Int) {
        let e = entries[url.path]
        return (Int(e?["seconds"] ?? 0), Int(e?["plays"] ?? 0))
    }

    func seconds(for url: URL) -> Int {
        stats(for: url).seconds
    }

    /// Total seconds played across every ROM and system. Drives the Engineer theme's
    /// LED minutes read-out, which accumulates as you play.
    var totalSeconds: Int {
        Int(entries.values.reduce(0) { $0 + ($1["seconds"] ?? 0) })
    }

    func recordPlay(_ url: URL) {
        var e = entries[url.path] ?? [:]
        e["plays"] = (e["plays"] ?? 0) + 1
        entries[url.path] = e
        save()
    }

    func addTime(_ url: URL, seconds: Double) {
        guard seconds > 0 else { return }
        var e = entries[url.path] ?? [:]
        e["seconds"] = (e["seconds"] ?? 0) + seconds
        entries[url.path] = e
        save()
    }

    private func save() {
        if let data = try? JSONSerialization.data(withJSONObject: entries, options: [.sortedKeys]) {
            try? data.write(to: file)
        }
        NotificationCenter.default.post(name: PlayStats.changed, object: nil)
    }

    // "0hrs 0mins"
    static func format(seconds: Int) -> String {
        let mins = seconds / 60
        return "\(mins / 60)hrs \(mins % 60)mins"
    }
}
