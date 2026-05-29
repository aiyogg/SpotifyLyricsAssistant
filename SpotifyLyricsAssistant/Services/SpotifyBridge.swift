import Foundation
import AppKit

/// Bridges communication with the Spotify macOS app via AppleScript.
/// All AppleScript execution is done on a background thread to avoid blocking the UI.
actor SpotifyBridge {

    // MARK: - Public API

    /// Fetches the current track info and player position in a single AppleScript call.
    /// Returns nil if Spotify is not running or nothing is playing.
    func getCurrentPlaybackInfo() async -> PlaybackInfo? {
        // Fast pre-check using NSRunningApplication — no AppleScript needed, no permission required
        guard isSpotifyProcessRunning() else { return nil }

        // AppleScript: use "application X is running" form to avoid launching Spotify
        let script = """
        if application "Spotify" is running then
            tell application "Spotify"
                set pState to player state as string
                if pState is "playing" or pState is "paused" then
                    set tID to id of current track
                    set tName to name of current track
                    set tArtist to artist of current track
                    set tAlbum to album of current track
                    set tDuration to duration of current track as string
                    set tArtwork to artwork url of current track
                    set tPos to player position as string
                    return pState & "||" & tID & "||" & tName & "||" & tArtist & "||" & tAlbum & "||" & tDuration & "||" & tArtwork & "||" & tPos
                else
                    return "stopped"
                end if
            end tell
        else
            return "notrunning"
        end if
        """

        guard let result = await runAppleScript(script) else { return nil }
        let trimmed = result.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == "stopped" || trimmed == "notrunning" || trimmed.isEmpty { return nil }

        let parts = trimmed.components(separatedBy: "||")
        guard parts.count == 8 else { return nil }

        let stateStr = parts[0].trimmingCharacters(in: .whitespaces)
        let playerState: PlayerState = stateStr == "playing" ? .playing : .paused

        guard let durationMs = Int(parts[5].trimmingCharacters(in: .whitespaces)) else { return nil }
        let position = Double(parts[7].trimmingCharacters(in: .whitespaces)) ?? 0

        let track = Track(
            spotifyURI: parts[1].trimmingCharacters(in: .whitespaces),
            name: parts[2].trimmingCharacters(in: .whitespaces),
            artist: parts[3].trimmingCharacters(in: .whitespaces),
            album: parts[4].trimmingCharacters(in: .whitespaces),
            durationMs: durationMs,
            artworkURL: parts[6].trimmingCharacters(in: .whitespaces)
        )

        return PlaybackInfo(track: track, playerState: playerState, position: position)
    }

    /// Fetches only the player position (lightweight, called frequently for lyric sync).
    func getPlayerPosition() async -> Double? {
        guard isSpotifyProcessRunning() else { return nil }

        let script = """
        if application "Spotify" is running then
            tell application "Spotify"
                if player state is playing then
                    return player position as string
                else
                    return ""
                end if
            end tell
        else
            return ""
        end if
        """
        guard let result = await runAppleScript(script) else { return nil }
        let trimmed = result.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return Double(trimmed)
    }

    /// Seeks the Spotify player to a specific timestamp in seconds.
    func seek(to seconds: Double) async {
        guard isSpotifyProcessRunning() else { return }
        let script = """
        if application "Spotify" is running then
            tell application "Spotify" to set player position to \(seconds)
        end if
        """
        _ = await runAppleScript(script)
    }

    /// Toggles play/pause state.
    func togglePlayPause() async {
        guard isSpotifyProcessRunning() else { return }
        let script = "if application \"Spotify\" is running then tell application \"Spotify\" to playpause"
        _ = await runAppleScript(script)
    }

    /// Skips to the next track.
    func nextTrack() async {
        guard isSpotifyProcessRunning() else { return }
        let script = "if application \"Spotify\" is running then tell application \"Spotify\" to next track"
        _ = await runAppleScript(script)
    }

    /// Skips to the previous track.
    func previousTrack() async {
        guard isSpotifyProcessRunning() else { return }
        let script = "if application \"Spotify\" is running then tell application \"Spotify\" to previous track"
        _ = await runAppleScript(script)
    }

    /// Checks if Spotify is currently running using NSRunningApplication (no AppleScript, no permissions needed).
    func isSpotifyRunning() async -> Bool {
        return isSpotifyProcessRunning()
    }

    // MARK: - Private: Process Check

    /// Fast synchronous check using NSRunningApplication — requires no permissions.
    private func isSpotifyProcessRunning() -> Bool {
        return !NSRunningApplication
            .runningApplications(withBundleIdentifier: "com.spotify.client")
            .isEmpty
    }

    // MARK: - Private: AppleScript Runner

    /// Executes an AppleScript string and returns the string result.
    private func runAppleScript(_ source: String) async -> String? {
        return await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                guard let script = NSAppleScript(source: source) else {
                    continuation.resume(returning: nil)
                    return
                }
                var errorDict: NSDictionary?
                let result = script.executeAndReturnError(&errorDict)
                if let err = errorDict {
                    print("[SpotifyBridge] AppleScript error: \(err)")
                    continuation.resume(returning: nil)
                } else {
                    continuation.resume(returning: result.stringValue)
                }
            }
        }
    }
}

// MARK: - Data Types

struct PlaybackInfo {
    let track: Track
    let playerState: PlayerState
    let position: Double  // Seconds
}
