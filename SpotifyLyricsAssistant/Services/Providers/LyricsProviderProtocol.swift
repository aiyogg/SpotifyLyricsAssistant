import Foundation

/// Protocol that all lyrics providers must conform to.
/// Providers should throw if they cannot find lyrics (not return empty).
protocol LyricsProvider: Sendable {
    /// Human-readable name for display in UI
    var name: String { get }

    /// The LyricsSource enum value for this provider
    var source: LyricsSource { get }

    /// Fetch lyrics for a given track.
    /// - Returns: A LyricsResult with synchronized lines if available.
    /// - Throws: LyricsProviderError if lyrics cannot be found.
    func fetchLyrics(for track: Track) async throws -> LyricsResult
}

// MARK: - Errors

enum LyricsProviderError: Error, LocalizedError {
    case notFound
    case networkError(Error)
    case parseError(String)
    case rateLimited
    case unsupportedTrack

    var errorDescription: String? {
        switch self {
        case .notFound:           return "该曲目暂无歌词"
        case .networkError(let e): return "网络错误: \(e.localizedDescription)"
        case .parseError(let msg): return "解析失败: \(msg)"
        case .rateLimited:        return "请求过于频繁，请稍后再试"
        case .unsupportedTrack:   return "不支持的曲目类型"
        }
    }
}
