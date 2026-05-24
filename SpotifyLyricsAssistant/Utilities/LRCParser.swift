import Foundation
import RegexBuilder

/// Parses LRC (Lyric) format text into an array of LyricsLine objects.
/// Supports standard LRC [mm:ss.xx], [mm:ss.xxx], and extended LRCX formats.
///
/// LRC format example:
///   [00:17.87] We're no strangers to love
///   [00:22.23] You know the rules and so do I
enum LRCParser {

    // Metadata tags to skip (they contain colons but are not timestamps)
    private static let metadataTags = Set(["ar", "ti", "al", "au", "length", "by", "offset", "re", "ve", "tool"])

    /// Parses an LRC string into an array of LyricsLine, sorted by timestamp.
    static func parse(_ lrcString: String) -> [LyricsLine] {
        var lines: [LyricsLine] = []

        let rawLines = lrcString.components(separatedBy: "\n")

        for rawLine in rawLines {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }

            // Extract all timestamp tags from this line
            let timestamps = extractTimestamps(from: line)
            guard !timestamps.isEmpty else { continue }

            // The text follows all the timestamp tags
            let text = textAfterTimestamps(in: line)
            let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)

            // Allow empty lines (e.g., musical breaks) — they act as "pause" markers
            // But skip pure metadata tags
            for timestamp in timestamps {
                lines.append(LyricsLine(timestamp: timestamp, text: trimmedText))
            }
        }

        // Sort by timestamp (LRC lines can be out of order with multiple timestamps)
        return lines.sorted { $0.timestamp < $1.timestamp }
    }

    // MARK: - Private Helpers

    /// Extracts all numeric timestamps from LRC bracket tags in a line.
    private static func extractTimestamps(from line: String) -> [TimeInterval] {
        var timestamps: [TimeInterval] = []
        var searchRange = line.startIndex..<line.endIndex

        while let openBracket = line.range(of: "[", range: searchRange) {
            guard let closeBracket = line.range(of: "]", range: openBracket.upperBound..<line.endIndex) else {
                break
            }

            let tagContent = String(line[openBracket.upperBound..<closeBracket.lowerBound])

            // Skip metadata tags (e.g., [ar:Artist Name])
            let colonIdx = tagContent.firstIndex(of: ":")
            if let colon = colonIdx {
                let prefix = String(tagContent[..<colon]).lowercased()
                if metadataTags.contains(prefix) {
                    searchRange = closeBracket.upperBound..<line.endIndex
                    continue
                }
            }

            // Try to parse as timestamp
            if let timestamp = parseTimestamp(tagContent) {
                timestamps.append(timestamp)
            }

            searchRange = closeBracket.upperBound..<line.endIndex
        }

        return timestamps
    }

    /// Returns the text portion of an LRC line after all bracket tags.
    private static func textAfterTimestamps(in line: String) -> String {
        var idx = line.startIndex

        while idx < line.endIndex, line[idx] == "[" {
            guard let close = line.range(of: "]", range: idx..<line.endIndex) else { break }
            idx = close.upperBound
        }

        return String(line[idx...])
    }

    /// Parses a timestamp string like "mm:ss.xx", "mm:ss.xxx" into TimeInterval (seconds).
    private static func parseTimestamp(_ str: String) -> TimeInterval? {
        // Split on ":" first
        let colonParts = str.components(separatedBy: ":")
        guard colonParts.count == 2 else { return nil }

        guard let minutes = Double(colonParts[0].trimmingCharacters(in: .whitespaces)) else { return nil }

        // seconds part may contain "." for fractional seconds
        let secStr = colonParts[1].trimmingCharacters(in: .whitespaces)
        let dotParts = secStr.components(separatedBy: ".")

        guard let seconds = Double(dotParts[0]) else { return nil }

        var fractional: Double = 0
        if dotParts.count >= 2 {
            let fracStr = dotParts[1]
            if let fracVal = Double(fracStr) {
                fractional = fracVal / pow(10.0, Double(fracStr.count))
            }
        }

        let totalSeconds = minutes * 60 + seconds + fractional
        guard totalSeconds >= 0 else { return nil }
        return totalSeconds
    }

    /// Parses an [offset:NNN] tag value and returns the offset in seconds.
    static func parseOffsetTag(_ lrcString: String) -> TimeInterval {
        let lines = lrcString.components(separatedBy: "\n")
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.lowercased().hasPrefix("[offset:") {
                let inner = trimmed.dropFirst("[offset:".count).dropLast()
                if let ms = Double(inner.trimmingCharacters(in: .whitespaces)) {
                    return ms / 1000.0  // Convert ms to seconds
                }
            }
        }
        return 0
    }
}
