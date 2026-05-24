import AppKit
import SwiftUI

/// Handles low-level app lifecycle events and manages the FloatingLyricsPanel.
/// Acts as the bridge between SwiftUI's App lifecycle and AppKit's window management.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    // MARK: - Properties

    var floatingPanel: FloatingLyricsPanel?
    var playerViewModel: PlayerViewModel?
    var settingsViewModel: SettingsViewModel?

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide from Dock (we're a menu bar only app)
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Don't quit when settings window is closed
        return false
    }

    // MARK: - Panel Management

    func setupFloatingPanel(playerVM: PlayerViewModel, settingsVM: SettingsViewModel) {
        self.playerViewModel = playerVM
        self.settingsViewModel = settingsVM

        floatingPanel = FloatingLyricsPanel()

        let content = LyricsWindowView()
            .environmentObject(playerVM)
            .environmentObject(settingsVM)

        floatingPanel?.setContent(content)
        floatingPanel?.alphaValue = settingsVM.settings.windowOpacity

        // Show if display mode includes floating window
        if settingsVM.settings.displayMode != .statusBarOnly {
            floatingPanel?.show()
        }
    }

    func showFloatingPanel() {
        floatingPanel?.show()
    }

    func hideFloatingPanel() {
        floatingPanel?.hide()
    }

    func toggleFloatingPanel() {
        if floatingPanel?.isVisible == true {
            floatingPanel?.hide()
        } else {
            floatingPanel?.show()
        }
    }

    func updatePanelOpacity(_ opacity: Double) {
        floatingPanel?.alphaValue = opacity
    }

    func updatePanelLevel(_ level: LyricsWindowLevel) {
        floatingPanel?.applyWindowLevel(level)
    }
}
