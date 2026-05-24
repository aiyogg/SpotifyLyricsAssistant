import Foundation

/// Manages local caching of lyrics to avoid redundant API calls.
/// Uses the Spotify track URI as the cache key.
/// Cache is stored as JSON files in the app's Application Support directory.
actor LyricsCache {

    private let cacheDirectory: URL
    private let maxCacheSize = 500  // Maximum number of cached tracks
    private let cacheExpiryDays: Double = 30

    // In-memory cache for the current session
    private var memoryCache: [String: LyricsResult] = [:]

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        self.cacheDirectory = appSupport
            .appendingPathComponent("SpotifyLyricsAssistant")
            .appendingPathComponent("LyricsCache")

        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    // MARK: - Public API

    /// Returns cached lyrics for a Spotify track URI, or nil if not cached.
    func get(for trackURI: String) -> LyricsResult? {
        // Check memory cache first (fastest)
        if let cached = memoryCache[trackURI] {
            return cached
        }

        // Check disk cache
        let fileURL = cacheFileURL(for: trackURI)
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }

        // Check expiry
        if let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
           let modDate = attrs[.modificationDate] as? Date {
            let ageInDays = Date().timeIntervalSince(modDate) / 86400
            if ageInDays > cacheExpiryDays {
                try? FileManager.default.removeItem(at: fileURL)
                return nil
            }
        }

        guard let data = try? Data(contentsOf: fileURL),
              let result = try? JSONDecoder().decode(LyricsResult.self, from: data) else {
            return nil
        }

        // Promote to memory cache
        memoryCache[trackURI] = result
        return result
    }

    /// Stores lyrics in both memory and disk cache.
    func store(_ result: LyricsResult, for trackURI: String) {
        memoryCache[trackURI] = result

        let fileURL = cacheFileURL(for: trackURI)
        if let data = try? JSONEncoder().encode(result) {
            try? data.write(to: fileURL)
        }

        // Asynchronously trim cache if over limit
        Task.detached(priority: .background) {
            await self.trimCacheIfNeeded()
        }
    }

    /// Clears all cached lyrics.
    func clearAll() {
        memoryCache.removeAll()
        try? FileManager.default.removeItem(at: cacheDirectory)
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    // MARK: - Private Helpers

    private func cacheFileURL(for trackURI: String) -> URL {
        // Sanitize the URI to be a valid filename
        let sanitized = trackURI
            .replacingOccurrences(of: ":", with: "_")
            .replacingOccurrences(of: "/", with: "_")
        return cacheDirectory.appendingPathComponent("\(sanitized).json")
    }

    private func trimCacheIfNeeded() {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: cacheDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: .skipsHiddenFiles
        ) else { return }

        guard files.count > maxCacheSize else { return }

        // Sort by modification date (oldest first) and remove excess
        let sorted = files.sorted { a, b in
            let aDate = (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let bDate = (try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return aDate < bDate
        }

        let toDelete = sorted.prefix(files.count - maxCacheSize)
        for fileURL in toDelete {
            try? FileManager.default.removeItem(at: fileURL)
        }
    }
}
