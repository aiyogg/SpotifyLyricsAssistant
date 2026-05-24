import Foundation

/// Fetches synchronized lyrics from QQ Music (QQ音乐)
/// Uses QQ Music's public JSON API endpoints.
final class QQMusicProvider: LyricsProvider {
    let name = "QQ音乐"
    let source = LyricsSource.qqMusic

    private let session: URLSession

    init(session: URLSession = .shared) {
        let config = URLSessionConfiguration.default
        // QQ Music requires Referer and specific headers
        config.httpAdditionalHeaders = [
            "Referer": "https://y.qq.com",
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36"
        ]
        self.session = URLSession(configuration: config)
    }

    func fetchLyrics(for track: Track) async throws -> LyricsResult {
        // Step 1: Search for song to get songmid
        let songMid = try await searchSong(track: track)

        // Step 2: Fetch lyrics
        return try await fetchLyricsForMid(songMid, track: track)
    }

    // MARK: - Search

    private func searchSong(track: Track) async throws -> String {
        let keyword = "\(track.artist) \(track.name)"
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? track.name

        // QQ Music search API
        let urlStr = "https://c.y.qq.com/soso/fcgi-bin/client_search_cp?w=\(keyword)&format=json&n=5&t=0&cr=1&g_tk=5381&p=1"
        guard let url = URL(string: urlStr) else {
            throw LyricsProviderError.parseError("Invalid search URL")
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 10

        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw LyricsProviderError.networkError(URLError(.badServerResponse))
        }

        let searchResult = try JSONDecoder().decode(QQSearchResult.self, from: data)
        guard let songs = searchResult.data?.song?.list, !songs.isEmpty else {
            throw LyricsProviderError.notFound
        }

        // Find best match
        let trackArtistLower = track.artist.lowercased()
        let trackNameLower = track.name.lowercased()

        let best = songs.first { song in
            let singerMatch = song.singer?.first?.name.lowercased().contains(trackArtistLower) ?? false
            let nameMatch = song.songname.lowercased().contains(trackNameLower)
            return singerMatch || nameMatch
        } ?? songs.first

        guard let match = best else {
            throw LyricsProviderError.notFound
        }
        return match.songmid
    }

    // MARK: - Lyrics Fetch

    private func fetchLyricsForMid(_ songmid: String, track: Track) async throws -> LyricsResult {
        let urlStr = "https://c.y.qq.com/lyric/fcgi-bin/fcg_query_lyric_new.fcg?songmid=\(songmid)&g_tk=5381&format=json&nobase64=1"
        guard let url = URL(string: urlStr) else {
            throw LyricsProviderError.parseError("Invalid lyrics URL")
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 10

        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw LyricsProviderError.networkError(URLError(.badServerResponse))
        }

        // QQ Music sometimes returns a JSONP-wrapped response; handle both
        var jsonData = data
        if let text = String(data: data, encoding: .utf8), text.hasPrefix("MusicJsonCallback") {
            // Strip JSONP wrapper: MusicJsonCallback({...})
            let stripped = text.dropFirst("MusicJsonCallback(".count).dropLast()
            jsonData = Data(stripped.utf8)
        }

        let lyricResult = try JSONDecoder().decode(QQLyricResult.self, from: jsonData)

        guard let lrcContent = lyricResult.lyric, !lrcContent.isEmpty else {
            throw LyricsProviderError.notFound
        }

        // QQ Music sometimes Base64-encodes lyrics; decode if needed
        let decodedLyric: String
        if let decodedData = Data(base64Encoded: lrcContent),
           let decodedStr = String(data: decodedData, encoding: .utf8) {
            decodedLyric = decodedStr
        } else {
            decodedLyric = lrcContent
        }

        let lines = LRCParser.parse(decodedLyric)
        guard !lines.isEmpty else {
            throw LyricsProviderError.parseError("Empty QQ lyrics after parsing")
        }

        return LyricsResult(lines: lines, source: .qqMusic, isSynced: true, trackURI: track.spotifyURI)
    }
}

// MARK: - API Response Models

private struct QQSearchResult: Decodable {
    let data: QQSearchData?
}

private struct QQSearchData: Decodable {
    let song: QQSongList?
}

private struct QQSongList: Decodable {
    let list: [QQSong]?
}

private struct QQSong: Decodable {
    let songmid: String
    let songname: String
    let singer: [QQSinger]?
}

private struct QQSinger: Decodable {
    let name: String
}

private struct QQLyricResult: Decodable {
    let lyric: String?
    let trans: String?  // Translation
    let retcode: Int?
}
