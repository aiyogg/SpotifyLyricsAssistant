import Foundation
import Combine
import SwiftUI

/// The central view model that manages Spotify playback state and lyrics synchronization.
/// Runs all UI-critical state on the main actor.
@MainActor
final class PlayerViewModel: ObservableObject {

    // MARK: - Published State

    @Published var currentTrack: Track? = nil
    @Published var playerState: PlayerState = .stopped
    @Published var playerPosition: Double = 0    // Seconds
    @Published var lyrics: LyricsResult? = nil
    @Published var currentLineIndex: Int = 0
    @Published var isLoadingLyrics: Bool = false
    @Published var lyricsError: String? = nil
    @Published var isSpotifyRunning: Bool = false

    // MARK: - Computed

    var currentLyricsLine: String {
        guard let lyrics = lyrics, !lyrics.lines.isEmpty else { return "" }
        guard currentLineIndex < lyrics.lines.count else { return "" }
        return lyrics.lines[currentLineIndex].text
    }

    var nextLyricsLine: String? {
        guard let lyrics = lyrics, currentLineIndex + 1 < lyrics.lines.count else { return nil }
        return lyrics.lines[currentLineIndex + 1].text
    }

    var previousLyricsLine: String? {
        guard let lyrics = lyrics, currentLineIndex > 0 else { return nil }
        return lyrics.lines[currentLineIndex - 1].text
    }

    var hasLyrics: Bool { lyrics != nil && !(lyrics?.isEmpty ?? true) }

    // MARK: - Private

    weak var settingsVM: SettingsViewModel?
    private let spotifyBridge = SpotifyBridge()
    private let lyricsCoordinator = LyricsCoordinator()
    private var cancellables = Set<AnyCancellable>()
    private var fetchTask: Task<Void, Never>? = nil

    // Polling intervals
    private let trackPollInterval: TimeInterval = 2.0    // Check for track change
    private let positionPollInterval: TimeInterval = 0.5  // Check playback position

    // MARK: - Initialization

    init() {
        setupPolling()
    }

    deinit {
        fetchTask?.cancel()
    }

    // MARK: - Polling Setup

    private func setupPolling() {
        // Poll for track changes (less frequent, heavier AppleScript call)
        Timer.publish(every: trackPollInterval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                Task { [weak self] in await self?.pollTrackInfo() }
            }
            .store(in: &cancellables)

        // Poll for position updates (frequent, lightweight)
        Timer.publish(every: positionPollInterval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                Task { [weak self] in await self?.pollPosition() }
            }
            .store(in: &cancellables)

        // Initial fetch
        Task { await self.pollTrackInfo() }
    }

    // MARK: - Polling Actions

    private func pollTrackInfo() async {
        let info = await spotifyBridge.getCurrentPlaybackInfo()

        guard let info = info else {
            // Spotify not running or nothing playing
            let running = await spotifyBridge.isSpotifyRunning()
            isSpotifyRunning = running
            if !running || playerState != .stopped {
                playerState = .stopped
            }
            return
        }

        isSpotifyRunning = true
        playerState = info.playerState
        playerPosition = info.position

        // Detect track change
        if info.track != currentTrack {
            let oldTrack = currentTrack
            currentTrack = info.track
            currentLineIndex = 0

            if info.track != oldTrack {
                await handleTrackChange(to: info.track)
            }
        }
    }

    private func pollPosition() async {
        guard playerState == .playing else { return }

        if let position = await spotifyBridge.getPlayerPosition() {
            playerPosition = position
            updateCurrentLine(at: position)
        }
    }

    // MARK: - Track Change Handler

    private func handleTrackChange(to track: Track) async {
        // Cancel any in-progress lyrics fetch
        fetchTask?.cancel()

        lyrics = nil
        lyricsError = nil
        currentLineIndex = 0
        isLoadingLyrics = true

        fetchTask = Task {
            let result = await lyricsCoordinator.fetchLyrics(for: track)

            guard !Task.isCancelled else { return }

            if let result = result {
                self.lyrics = result
                self.lyricsError = nil
                // Sync to current position immediately
                self.updateCurrentLine(at: self.playerPosition)
            } else {
                self.lyricsError = "暂无歌词"
            }
            self.isLoadingLyrics = false
        }
    }

    // MARK: - Lyrics Line Sync

    func updateCurrentLine(at position: Double) {
        guard let lyrics = lyrics, !lyrics.lines.isEmpty else { return }

        // Apply manual time offset (e.g. +1.0 means lyrics are delayed by 1s, so we pretend position is 1s ahead)
        // Wait, if lyricsOffsetSeconds = +0.5, it means lyrics should appear 0.5s later.
        // So we subtract the offset from the position. If offset is +0.5, position 10.0 becomes 9.5.
        // Therefore, timestamp 10.0 won't be reached until position 10.5.
        let offset = settingsVM?.settings.lyricsOffsetSeconds ?? 0.0
        let adjustedPosition = position - offset

        // Find the last line whose timestamp <= adjusted position
        let newIndex = lyrics.lines.lastIndex(where: { $0.timestamp <= adjustedPosition }) ?? 0

        guard newIndex != currentLineIndex else { return }

        withAnimation(.easeInOut(duration: 0.25)) {
            currentLineIndex = newIndex
        }
    }

    // MARK: - Manual Controls

    /// Reloads lyrics for the current track (bypasses cache).
    func reloadLyrics() async {
        guard let track = currentTrack else { return }
        await lyricsCoordinator.clearCache()
        await handleTrackChange(to: track)
    }

    /// Clears all cached lyrics.
    func clearLyricsCache() async {
        await lyricsCoordinator.clearCache()
    }
}
