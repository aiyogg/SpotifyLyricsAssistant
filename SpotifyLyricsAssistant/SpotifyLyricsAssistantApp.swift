import SwiftUI
import Combine

@main
struct SpotifyLyricsAssistantApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    @StateObject private var player = PlayerViewModel()
    @StateObject private var settings = SettingsViewModel()

    var body: some Scene {
        // MARK: - Menu Bar Extra
        MenuBarExtra {
            MenuBarMenuView()
                .environmentObject(player)
                .environmentObject(settings)
                .onAppear {
                    // Wire up the AppDelegate with our ViewModels on first appearance
                    if appDelegate.playerViewModel == nil {
                        appDelegate.setupFloatingPanel(playerVM: player, settingsVM: settings)
                        setupSettingsObserver()
                    }
                }
        } label: {
            MenuBarLabelView(text: menuBarText)
        }
        .menuBarExtraStyle(.window)
    }

    // MARK: - Menu Bar Text

    /// Text to display in the menu bar alongside the music note icon.
    private var menuBarText: String {
        // Don't show text if mode is floating-window-only (avoid clutter)
        if settings.settings.displayMode == .floatingWindow {
            return ""
        }
        if !player.isSpotifyRunning || player.playerState == .stopped {
            return ""
        }
        if player.isLoadingLyrics {
            return "···"
        }
        let line = player.currentLyricsLine
        if !line.isEmpty { return line }
        return player.currentTrack?.name ?? ""
    }

    // MARK: - Settings Observer

    private func setupSettingsObserver() {
        // Observe settings changes to update panel in real time.
        // Centralised here so ANY source that writes to settings
        // (Settings view, MenuBar, etc.) automatically drives the panel.
        NotificationCenter.default.addObserver(
            forName: .settingsDidChange,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                let s = settings.settings
                appDelegate.updatePanelLevel(s.windowLevel)

                // Drive floating panel visibility from displayMode
                switch s.displayMode {
                case .floatingWindow, .both:
                    appDelegate.showFloatingPanel()
                case .statusBarOnly:
                    appDelegate.hideFloatingPanel()
                }
            }
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let settingsDidChange = Notification.Name("SpotifyLyricsAssistant.settingsDidChange")
}
