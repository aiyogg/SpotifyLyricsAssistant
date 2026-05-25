import AppKit
import SwiftUI
import UserNotifications

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

        // Request notification permission and show a one-time welcome tip so the
        // user can find the status bar icon even on a crowded menu bar.
        requestNotificationPermissionIfNeeded()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Don't quit when settings window is closed
        return false
    }

    /// Called when the user clicks the app icon in the Dock (or re-opens via Finder/Spotlight).
    /// This provides a reliable fallback entry point when the status bar item is hidden
    /// because the menu bar is full.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        // Show the floating lyrics panel so the user can interact with the app.
        showFloatingPanel()
        NSApp.activate(ignoringOtherApps: true)
        return true
    }

    // MARK: - Panel Management

    func setupFloatingPanel(playerVM: PlayerViewModel, settingsVM: SettingsViewModel) {
        self.playerViewModel = playerVM
        self.settingsViewModel = settingsVM
        self.playerViewModel?.settingsVM = settingsVM

        floatingPanel = FloatingLyricsPanel()

        let content = LyricsWindowView()
            .environmentObject(playerVM)
            .environmentObject(settingsVM)

        floatingPanel?.setContent(content)

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

    // Transparency is now handled natively by SwiftUI .ultraThinMaterial

    func updatePanelLevel(_ level: LyricsWindowLevel) {
        floatingPanel?.applyWindowLevel(level)
    }

    // MARK: - Notifications

    private func requestNotificationPermissionIfNeeded() {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .notDetermined:
                center.requestAuthorization(options: [.alert]) { granted, _ in
                    if granted { self.scheduleWelcomeNotification() }
                }
            case .authorized, .provisional, .ephemeral:
                self.scheduleWelcomeNotification()
            default:
                break
            }
        }
    }

    /// Fires a one-time notification (after a short delay) pointing the user to
    /// the status bar music-note icon.  Uses a flag in UserDefaults so it only
    /// appears on the very first launch.
    private func scheduleWelcomeNotification() {
        let key = "hasShownWelcomeNotification"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)

        let content = UNMutableNotificationContent()
        content.title = "Spotify 歌词助手已启动"
        content.body = "在屏幕右上角状态栏中找到 ♪ 图标，点击即可查看歌词。若图标被遮挡，可从 Launchpad 再次点击应用图标来打开歌词窗口。"

        // Deliver 3 seconds after launch so the app is fully ready
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 3, repeats: false)
        let request = UNNotificationRequest(
            identifier: "welcome",
            content: content,
            trigger: trigger
        )
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }
}
