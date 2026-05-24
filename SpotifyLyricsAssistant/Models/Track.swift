import Foundation

/// Represents the currently playing track in Spotify
struct Track: Equatable, Codable {
    let spotifyURI: String       // e.g. "spotify:track:4iV5W9uYEdYuvU7niJsc7G"
    let name: String
    let artist: String
    let album: String
    let durationMs: Int          // Track duration in milliseconds
    let artworkURL: String

    /// Unique track ID extracted from Spotify URI
    var trackID: String {
        spotifyURI.components(separatedBy: ":").last ?? spotifyURI
    }

    /// Duration in seconds (Double for precise comparison)
    var durationSeconds: Double {
        Double(durationMs) / 1000.0
    }

    static func == (lhs: Track, rhs: Track) -> Bool {
        lhs.spotifyURI == rhs.spotifyURI
    }
}

/// Current playback state from Spotify
enum PlayerState: String, Equatable {
    case playing
    case paused
    case stopped
}
