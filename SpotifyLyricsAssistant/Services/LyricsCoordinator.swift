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

    // MARK: - Public API

    /// Fetches lyrics for the given track.
    /// Returns nil if no lyrics are found from any provider.
    func fetchLyrics(for track: Track) async -> LyricsResult? {
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

        // 2. Try each provider in priority order
        for provider in providers {
            let providerName = provider.name
            let providerSource = provider.source
            do {
                print("[LyricsCoordinator] Trying \(providerName) for: \(track.name) - \(track.artist)")
                let result = try await provider.fetchLyrics(for: track)
                print("[LyricsCoordinator] Success from \(providerName): \(result.lines.count) lines")

                // Store in cache for next time
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
                // Store empty result to avoid re-fetching instrumental tracks
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

    /// Clears the lyrics cache.
    func clearCache() async {
        await cache.clearAll()
    }

    /// Updates the provider order based on user settings.
    /// Returns a new coordinator with the updated provider list.
    func reordered(by priority: [LyricsSource]) -> LyricsCoordinator {
        let ordered = priority.compactMap { source in
            providers.first { $0.source == source }
        }
        let remaining = providers.filter { provider in
            !priority.contains(provider.source)
        }
        return LyricsCoordinator(providers: ordered + remaining, cache: cache)
    }
}
