import Foundation

/// Fetches synchronized lyrics from LRCLib.net
/// Free, open, no authentication required.
/// Documentation: https://lrclib.net/docs
final class LRCLibProvider: LyricsProvider {
    let name = "LRCLib"
    let source = LyricsSource.lrclib

    private let session: URLSession
    private let baseURL = "https://lrclib.net/api"
    private let userAgent = "SpotifyLyricsAssistant/1.0 (https://github.com/SpotifyLyricsAssistant)"

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchLyrics(for track: Track) async throws -> LyricsResult {
        // Try exact match first (requires duration for deduplication)
        let durationSeconds = Int(track.durationSeconds)

        var components = URLComponents(string: "\(baseURL)/get")!
        components.queryItems = [
            URLQueryItem(name: "track_name", value: track.name),
            URLQueryItem(name: "artist_name", value: track.artist),
            URLQueryItem(name: "album_name", value: track.album),
            URLQueryItem(name: "duration", value: String(durationSeconds))
        ]

        guard let url = components.url else {
            throw LyricsProviderError.parseError("Invalid URL construction")
        }

        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 10

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LyricsProviderError.networkError(URLError(.badServerResponse))
        }

        switch httpResponse.statusCode {
        case 200:
            break
        case 404:
            // Try search fallback
            return try await searchFallback(for: track)
        case 429:
            throw LyricsProviderError.rateLimited
        default:
            throw LyricsProviderError.networkError(URLError(.badServerResponse))
        }

        return try parseResponse(data: data, trackURI: track.spotifyURI)
    }

    // MARK: - Search Fallback

    private func searchFallback(for track: Track) async throws -> LyricsResult {
        var components = URLComponents(string: "\(baseURL)/search")!
        components.queryItems = [
            URLQueryItem(name: "track_name", value: track.name),
            URLQueryItem(name: "artist_name", value: track.artist)
        ]

        guard let url = components.url else {
            throw LyricsProviderError.notFound
        }

        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 10

        let (data, _) = try await session.data(for: request)
        let results = try JSONDecoder().decode([LRCLibResponse].self, from: data)

        // Pick the best match by checking if artist name matches
        let trackArtistLower = track.artist.lowercased()
        let best = results.first { result in
            result.artistName.lowercased().contains(trackArtistLower) ||
            trackArtistLower.contains(result.artistName.lowercased())
        } ?? results.first

        guard let match = best, !match.instrumental else {
            throw LyricsProviderError.notFound
        }

        return try parseLRCLibResponse(match, trackURI: track.spotifyURI)
    }

    // MARK: - Parsing

    private func parseResponse(data: Data, trackURI: String) throws -> LyricsResult {
        let response = try JSONDecoder().decode(LRCLibResponse.self, from: data)
        return try parseLRCLibResponse(response, trackURI: trackURI)
    }

    private func parseLRCLibResponse(_ response: LRCLibResponse, trackURI: String) throws -> LyricsResult {
        if response.instrumental {
            throw LyricsProviderError.unsupportedTrack
        }

        // Prefer synced lyrics
        if let syncedLyrics = response.syncedLyrics, !syncedLyrics.isEmpty {
            let lines = LRCParser.parse(syncedLyrics)
            guard !lines.isEmpty else {
                throw LyricsProviderError.parseError("Synced lyrics parsed to empty")
            }
            return LyricsResult(lines: lines, source: .lrclib, isSynced: true, trackURI: trackURI)
        }

        // Fall back to plain lyrics (unsynced)
        if let plainLyrics = response.plainLyrics, !plainLyrics.isEmpty {
            let lines = plainLyrics
                .components(separatedBy: "\n")
                .enumerated()
                .compactMap { (idx, text) -> LyricsLine? in
                    let trimmed = text.trimmingCharacters(in: .whitespaces)
                    guard !trimmed.isEmpty else { return nil }
                    return LyricsLine(timestamp: Double(idx) * 3.0, text: trimmed)
                }
            return LyricsResult(lines: lines, source: .lrclib, isSynced: false, trackURI: trackURI)
        }

        throw LyricsProviderError.notFound
    }
}

// MARK: - API Response Model

private struct LRCLibResponse: Decodable {
    let id: Int
    let trackName: String
    let artistName: String
    let albumName: String
    let duration: Double
    let instrumental: Bool
    let plainLyrics: String?
    let syncedLyrics: String?
}
