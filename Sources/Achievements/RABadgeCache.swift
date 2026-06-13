// T3d Boy — RetroAchievements badge / box-art image loader.
//
// Two-tier cache (in-memory NSCache + on-disk under Application Support) backed
// by URLSession. Badge art is normal raster art, so callers should display it
// with SMOOTH scaling (unlike the pixel-art ROM thumbnails).
//
// `image(for:completion:)` is safe to call repeatedly for the same URL (in-flight
// requests are coalesced) and the completion always fires on the main queue, so
// it's table-reuse friendly: a cell can fire a request and bail in its own check.

import Cocoa
import CryptoKit

final class RABadgeCache {
    static let shared = RABadgeCache()

    private let memory = NSCache<NSString, NSImage>()
    private let dir: URL
    private let ioQueue = DispatchQueue(label: "t3dboy.badges", qos: .userInitiated)
    private let session: URLSession

    // URL string → completions waiting on the same in-flight download.
    private var inFlight: [String: [(NSImage?) -> Void]] = [:]
    private let lock = NSLock()

    init() {
        dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("T3d Boy/Badges", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let config = URLSessionConfiguration.default
        config.requestCachePolicy = .returnCacheDataElseLoad
        config.timeoutIntervalForRequest = 20
        session = URLSession(configuration: config)

        memory.countLimit = 400
    }

    /// Returns a cached image immediately if it's in memory, else nil.
    func cachedImage(for url: String) -> NSImage? {
        memory.object(forKey: url as NSString)
    }

    /// Loads (and caches) the image at `url`. `completion` always fires on main.
    /// A nil or empty URL completes with nil. Coalesces duplicate in-flight loads.
    func image(for url: String?, completion: @escaping (NSImage?) -> Void) {
        guard let url, !url.isEmpty else {
            DispatchQueue.main.async { completion(nil) }
            return
        }
        if let cached = memory.object(forKey: url as NSString) {
            DispatchQueue.main.async { completion(cached) }
            return
        }

        // Coalesce: if a load for this URL is already running, just queue up.
        lock.lock()
        if inFlight[url] != nil {
            inFlight[url]?.append(completion)
            lock.unlock()
            return
        }
        inFlight[url] = [completion]
        lock.unlock()

        ioQueue.async { [weak self] in
            guard let self else { return }

            // 1) Disk cache.
            let file = self.cacheFile(for: url)
            if let data = try? Data(contentsOf: file), let img = NSImage(data: data) {
                self.finish(url: url, image: img)
                return
            }

            // 2) Network.
            guard let remote = URL(string: url) else {
                self.finish(url: url, image: nil)
                return
            }
            let task = self.session.dataTask(with: remote) { data, _, _ in
                var image: NSImage?
                if let data, let img = NSImage(data: data) {
                    image = img
                    try? data.write(to: file)
                }
                self.finish(url: url, image: image)
            }
            task.resume()
        }
    }

    private func finish(url: String, image: NSImage?) {
        if let image { memory.setObject(image, forKey: url as NSString) }
        lock.lock()
        let waiters = inFlight[url] ?? []
        inFlight[url] = nil
        lock.unlock()
        DispatchQueue.main.async {
            for w in waiters { w(image) }
        }
    }

    private func cacheFile(for url: String) -> URL {
        let hex = Insecure.MD5.hash(data: Data(url.utf8))
            .map { String(format: "%02x", $0) }.joined()
        // Preserve a sensible extension where the URL has one.
        let ext = URL(string: url)?.pathExtension
        let name = (ext?.isEmpty == false) ? "\(hex).\(ext!)" : "\(hex).img"
        return dir.appendingPathComponent(name)
    }
}
