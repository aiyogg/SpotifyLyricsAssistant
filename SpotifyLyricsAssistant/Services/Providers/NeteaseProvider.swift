import Foundation

/// Fetches synchronized lyrics from Netease Cloud Music (网易云音乐)
/// Uses the official music.163.com API directly — no third-party proxy required.
final class NeteaseProvider: LyricsProvider {
    let name = "网易云音乐"
    let source = LyricsSource.netease

    private let session: URLSession

    // Official Netease API base URL
    private let baseURL = "https://music.163.com"

    // Headers required by the official API to accept requests
    private let headers: [String: String] = [
        "Referer": "music.163.com",
        "User-Agent": "Mozilla/5.0 (Linux; Android 11; M2007J3SC Build/RKQ1.200826.002; wv) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/77.0.3865.120 Mobile Safari/537.36 NeteaseMusic/8.7.01",
        "Accept": "*/*",
        "Accept-Language": "zh-CN,zh;q=0.9,en-US;q=0.8,en;q=0.7"
    ]

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchLyrics(for track: Track) async throws -> LyricsResult {
        let songID = try await searchSong(track: track)
        return try await fetchLyricsForID(songID, track: track)
    }

    // MARK: - Search

    private func searchSong(track: Track) async throws -> Int {
        guard let url = URL(string: "\(baseURL)/api/cloudsearch/pc") else {
            throw LyricsProviderError.parseError("Invalid search URL")
        }

        let keyword = "\(track.artist) \(track.name)"

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 10
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let bodyParams = [
            "s": keyword,
            "type": "1",
            "limit": "5",
            "total": "true",
            "offset": "0"
        ]
        request.httpBody = bodyParams
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)

        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw LyricsProviderError.networkError(URLError(.badServerResponse))
        }

        let searchResult = try JSONDecoder().decode(NeteaseSearchResult.self, from: data)
        guard let songs = searchResult.result?.songs, !songs.isEmpty else {
            throw LyricsProviderError.notFound
        }

        // Best match: prefer songs where both artist and name match
        let trackArtistLower = track.artist.lowercased()
        let trackNameLower = track.name.lowercased()

        let best = songs.first { song in
            let artistMatch = song.ar?.first?.name.lowercased().contains(trackArtistLower) ?? false
            let nameMatch = song.name.lowercased().contains(trackNameLower)
            return artistMatch && nameMatch
        } ?? songs.first { song in
            song.name.lowercased().contains(trackNameLower)
        } ?? songs.first

        guard let match = best else {
            throw LyricsProviderError.notFound
        }
        return match.id
    }

    // MARK: - Lyric Fetch

    private func fetchLyricsForID(_ id: Int, track: Track) async throws -> LyricsResult {
        // lv=1: use the best available version; kv=1: karaoke; tv=-1: no translation required
        guard let url = URL(string: "\(baseURL)/api/song/lyric?id=\(id)&lv=1&kv=1&tv=-1") else {
            throw LyricsProviderError.parseError("Invalid lyrics URL")
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }

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

/// cloudsearch/pc returns artists as "ar", not "artists"
private struct NeteaseSong: Decodable {
    let id: Int
    let name: String
    let ar: [NeteaseArtist]?
    let dt: Int?  // duration in ms
}

private struct NeteaseArtist: Decodable {
    let name: String
}

private struct NeteaseLyricResult: Decodable {
    let lrc: NeteaseLRC?
    let tlyric: NeteaseLRC?  // Translation (if available)
}

private struct NeteaseLRC: Decodable {
    let lyric: String?
}
