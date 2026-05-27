import Foundation

/// Orchestrates lyrics fetching across multiple providers with a priority fallback chain.
/// Checks local cache before making any network requests.
actor LyricsCoordinator {

    // Store providers as type-erased Sendable wrappers
    private let providers: [any LyricsProvider]
    private let cache: LyricsCache

    init(providers: [any LyricsProvider] = [LRCLibProvider(), NeteaseProvider(), QQMusicProvider()],
         cache: LyricsCache = LyricsCache()) {
        self.providers = providers
        self.cache = cache
    }

    // MARK: - Private Helpers

    /// Returns providers reordered by `priority`, with any unlisted providers appended at the end.
    private func orderedProviders(by priority: [LyricsSource]) -> [any LyricsProvider] {
        let ordered = priority.compactMap { source in providers.first { $0.source == source } }
        let remaining = providers.filter { p in !priority.contains(p.source) }
        return ordered + remaining
    }

    // MARK: - Public API

    /// Fetches lyrics for the given track, respecting the given source priority order.
    /// Checks the local cache before making any network requests.
    func fetchLyrics(for track: Track, priority: [LyricsSource] = []) async -> LyricsResult? {
        // 1. Check cache first
        if let cached = await cache.get(for: track.spotifyURI) {
            print("[LyricsCoordinator] Cache hit for: \(track.name)")
            return LyricsResult(
                lines: cached.lines,
                source: .cache,
                isSynced: cached.isSynced,
                trackURI: track.spotifyURI
            )
        }

        // 2. Try each provider in the requested priority order
        let ordered = priority.isEmpty ? providers : orderedProviders(by: priority)
        for provider in ordered {
            let providerName = provider.name
            let providerSource = provider.source
            do {
                print("[LyricsCoordinator] Trying \(providerName) for: \(track.name) - \(track.artist)")
                let result = try await provider.fetchLyrics(for: track)
                print("[LyricsCoordinator] Success from \(providerName): \(result.lines.count) lines")

                await cache.store(result, for: track.spotifyURI)
                return result

            } catch LyricsProviderError.notFound {
                print("[LyricsCoordinator] Not found in \(providerName), trying next...")
                continue
            } catch LyricsProviderError.rateLimited {
                print("[LyricsCoordinator] Rate limited by \(providerName), skipping...")
                continue
            } catch LyricsProviderError.unsupportedTrack {
                print("[LyricsCoordinator] Instrumental track detected by \(providerName)")
                let emptyResult = LyricsResult(lines: [], source: providerSource, isSynced: false, trackURI: track.spotifyURI)
                await cache.store(emptyResult, for: track.spotifyURI)
                return emptyResult
            } catch {
                print("[LyricsCoordinator] Error from \(providerName): \(error.localizedDescription)")
                continue
            }
        }

        print("[LyricsCoordinator] No lyrics found from any provider for: \(track.name)")
        return nil
    }

    /// Fetches lyrics skipping a specific provider, then wrapping around in priority order.
    /// `priority` must match the same ordering used by `nextReloadSource` in the view model
    /// so that the displayed "next source" matches what actually gets tried.
    /// Does not read from cache; writes on success.
    func fetchLyrics(for track: Track, skippingSource: LyricsSource, priority: [LyricsSource]) async -> LyricsResult? {
        guard !providers.isEmpty else { return nil }

        // Reorder providers according to the caller-supplied priority, then rotate
        // past the skipped source so the next one is tried first.
        let allOrdered = orderedProviders(by: priority)
        let skipIndex = allOrdered.firstIndex(where: { $0.source == skippingSource }) ?? -1
        let startIndex = (skipIndex + 1) % allOrdered.count
        let indices = Array(startIndex..<allOrdered.count) + Array(0..<startIndex)
        let orderedProviders = indices.map { allOrdered[$0] }

        for provider in orderedProviders {
            let providerName = provider.name
            let providerSource = provider.source
            do {
                print("[LyricsCoordinator] (skip-rotate) Trying \(providerName) for: \(track.name)")
                let result = try await provider.fetchLyrics(for: track)
                print("[LyricsCoordinator] (skip-rotate) Success from \(providerName): \(result.lines.count) lines")
                await cache.store(result, for: track.spotifyURI)
                return result
            } catch LyricsProviderError.notFound {
                print("[LyricsCoordinator] (skip-rotate) Not found in \(providerName), trying next...")
                continue
            } catch LyricsProviderError.rateLimited {
                print("[LyricsCoordinator] (skip-rotate) Rate limited by \(providerName), skipping...")
                continue
            } catch LyricsProviderError.unsupportedTrack {
                print("[LyricsCoordinator] (skip-rotate) Instrumental detected by \(providerName)")
                let emptyResult = LyricsResult(lines: [], source: providerSource, isSynced: false, trackURI: track.spotifyURI)
                await cache.store(emptyResult, for: track.spotifyURI)
                return emptyResult
            } catch {
                print("[LyricsCoordinator] (skip-rotate) Error from \(providerName): \(error.localizedDescription)")
                continue
            }
        }

        print("[LyricsCoordinator] (skip-rotate) No lyrics found from any provider for: \(track.name)")
        return nil
    }

    /// Clears the lyrics cache.
    func clearCache() async {
        await cache.clearAll()
    }
}
