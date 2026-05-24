import Foundation

/// Fetches synchronized lyrics from Netease Cloud Music (网易云音乐)
/// Uses a public proxy API that handles Netease's request signing.
final class NeteaseProvider: LyricsProvider {
    let name = "网易云音乐"
    let source = LyricsSource.netease

    private let session: URLSession
    // Public proxy instances for the NeteaseCloudMusicApi project
    private let searchBase = "https://music.xianqiao.wang/neteaseapiv2"

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchLyrics(for track: Track) async throws -> LyricsResult {
        // Step 1: Search for the song
        let songID = try await searchSong(track: track)

        // Step 2: Fetch lyrics by song ID
        return try await fetchLyricsForID(songID, track: track)
    }

    // MARK: - Search

    private func searchSong(track: Track) async throws -> Int {
        let query = "\(track.artist) \(track.name)"
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? track.name

        guard let url = URL(string: "\(searchBase)/search?limit=5&type=1&keywords=\(query)") else {
            throw LyricsProviderError.parseError("Invalid search URL")
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 10

        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw LyricsProviderError.networkError(URLError(.badServerResponse))
        }

        let searchResult = try JSONDecoder().decode(NeteaseSearchResult.self, from: data)
        guard let songs = searchResult.result?.songs, !songs.isEmpty else {
            throw LyricsProviderError.notFound
        }

        // Find the best matching song by comparing artist name
        let trackArtistLower = track.artist.lowercased()
        let trackNameLower = track.name.lowercased()

        let best = songs.first { song in
            let artistMatch = song.artists?.first?.name.lowercased().contains(trackArtistLower) ?? false
            let nameMatch = song.name.lowercased().contains(trackNameLower)
            return artistMatch || nameMatch
        } ?? songs.first

        guard let match = best else {
            throw LyricsProviderError.notFound
        }
        return match.id
    }

    // MARK: - Lyric Fetch

    private func fetchLyricsForID(_ id: Int, track: Track) async throws -> LyricsResult {
        guard let url = URL(string: "\(searchBase)/lyric?id=\(id)") else {
            throw LyricsProviderError.parseError("Invalid lyrics URL")
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 10

        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw LyricsProviderError.networkError(URLError(.badServerResponse))
        }

        let lyricResult = try JSONDecoder().decode(NeteaseLyricResult.self, from: data)

        guard let lrcContent = lyricResult.lrc?.lyric, !lrcContent.isEmpty else {
            throw LyricsProviderError.notFound
        }

        let lines = LRCParser.parse(lrcContent)
        guard !lines.isEmpty else {
            throw LyricsProviderError.parseError("Empty lyrics after parsing")
        }

        return LyricsResult(lines: lines, source: .netease, isSynced: true, trackURI: track.spotifyURI)
    }
}

// MARK: - API Response Models

private struct NeteaseSearchResult: Decodable {
    let result: NeteaseSearchResultData?
}

private struct NeteaseSearchResultData: Decodable {
    let songs: [NeteaseSong]?
}

private struct NeteaseSong: Decodable {
    let id: Int
    let name: String
    let artists: [NeteaseArtist]?
    let duration: Int?
}

private struct NeteaseArtist: Decodable {
    let name: String
}

private struct NeteaseLyricResult: Decodable {
    let lrc: NeteaseLRC?
    let tlyric: NeteaseLRC?  // Translation lyrics (if available)
}

private struct NeteaseLRC: Decodable {
    let lyric: String?
}
