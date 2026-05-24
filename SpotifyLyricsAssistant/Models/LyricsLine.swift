import Foundation

/// A single line of lyrics with its timestamp
struct LyricsLine: Identifiable, Equatable, Codable {
    let id: UUID
    let timestamp: TimeInterval  // Seconds from track start
    let text: String

    init(timestamp: TimeInterval, text: String) {
        self.id = UUID()
        self.timestamp = timestamp
        self.text = text
    }

    init(id: UUID = UUID(), timestamp: TimeInterval, text: String) {
        self.id = id
        self.timestamp = timestamp
        self.text = text
    }
}

/// The source that provided lyrics
enum LyricsSource: String, Codable {
    case lrclib = "LRCLib"
    case netease = "网易云音乐"
    case qqMusic = "QQ音乐"
    case cache = "缓存"
    case unknown = "未知"
}

/// The result of a lyrics fetch operation
struct LyricsResult: Codable {
    let lines: [LyricsLine]
    let source: LyricsSource
    let isSynced: Bool           // true = has timestamps, false = plain text only
    let trackURI: String         // Spotify track URI used as cache key

    var isEmpty: Bool { lines.isEmpty }

    /// Plain text representation of all lyrics
    var plainText: String {
        lines.map(\.text).joined(separator: "\n")
    }
}
