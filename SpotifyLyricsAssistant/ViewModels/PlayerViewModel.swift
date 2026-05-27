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
    /// The source that will be tried first on the next reload.
    /// Derived synchronously from the current lyrics source and the settings priority order.
    var nextReloadSource: LyricsSource? {
        guard let currentSource = lyrics?.source, currentSource != .cache else { return nil }
        let priority = settingsVM?.settings.lyricsSourcePriority ?? [.lrclib, .netease, .qqMusic]
        guard let idx = priority.firstIndex(of: currentSource) else { return priority.first }
        return priority[(idx + 1) % priority.count]
    }
    
    // Per-track manual offset (seconds). Applied on top of global settings offset.
    // Resets to 0 automatically when the track changes.
    @Published var trackOffsetSeconds: Double = 0

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
        trackOffsetSeconds = 0  // Reset local offset for the new track
        isLoadingLyrics = true

        fetchTask = Task {
            let priority = self.settingsVM?.settings.lyricsSourcePriority ?? [.lrclib, .netease, .qqMusic]
            let result = await lyricsCoordinator.fetchLyrics(for: track, priority: priority)

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

        // Apply time offsets:
        // Global offset (from settings) + Local track offset (from floating window)
        // E.g., if offset is +0.5, it means lyrics should appear 0.5s later.
        // So we subtract the offset from the position.
        let globalOffset = settingsVM?.settings.lyricsOffsetSeconds ?? 0.0
        let totalOffset = globalOffset + trackOffsetSeconds
        let adjustedPosition = position - totalOffset

        // Find the last line whose timestamp <= adjusted position
        let newIndex = lyrics.lines.lastIndex(where: { $0.timestamp <= adjustedPosition }) ?? 0

        guard newIndex != currentLineIndex else { return }

        withAnimation(.easeInOut(duration: 0.25)) {
            currentLineIndex = newIndex
        }
    }

    // MARK: - Manual Controls

    /// Dynamic tooltip for the "reload lyrics" button.
    /// Shows the current source and the next source that will be tried.
    var reloadTooltip: String {
        guard let currentSource = lyrics?.source,
              currentSource != .cache,
              nextReloadSource != nil else {
            return "重新获取歌词"
        }
        return "切换来源重新获取"
    }

    /// Reloads lyrics for the current track by skipping the last-used source
    /// and cycling to the next provider. If there was no prior source, clears
    /// cache and re-fetches from the top of the priority list.
    func reloadLyrics() async {
        guard let track = currentTrack else { return }

        let lastSource = lyrics?.source

        // Cancel any in-progress fetch
        fetchTask?.cancel()
        lyrics = nil
        lyricsError = nil
        currentLineIndex = 0
        isLoadingLyrics = true

        fetchTask = Task {
            let result: LyricsResult?

            if let lastSource = lastSource, lastSource != .cache {
                // Skip the source that just delivered (possibly wrong) lyrics.
                // Pass the same priority used by nextReloadSource so display and fetch stay in sync.
                let priority = self.settingsVM?.settings.lyricsSourcePriority ?? [.lrclib, .netease, .qqMusic]
                result = await lyricsCoordinator.fetchLyrics(for: track, skippingSource: lastSource, priority: priority)
            } else {
                // No prior source (e.g., failed state): clear cache and start fresh
                await lyricsCoordinator.clearCache()
                result = await lyricsCoordinator.fetchLyrics(for: track)
            }

            guard !Task.isCancelled else { return }

            if let result = result {
                self.lyrics = result
                self.lyricsError = nil
                self.updateCurrentLine(at: self.playerPosition)
            } else {
                self.lyricsError = "所有来源均无歌词"
            }
            self.isLoadingLyrics = false
        }
    }

    /// Clears all cached lyrics.
    func clearLyricsCache() async {
        await lyricsCoordinator.clearCache()
    }
}
