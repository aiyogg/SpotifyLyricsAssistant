import Foundation
import SwiftUI

/// Manages user settings with UserDefaults persistence.
@MainActor
final class SettingsViewModel: ObservableObject {

    private let defaults = UserDefaults.standard
    private let settingsKey = "AppSettings"

    @Published var settings: AppSettings {
        didSet { saveSettings() }
    }

    init() {
        if let data = UserDefaults.standard.data(forKey: "AppSettings"),
           let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) {
            self.settings = decoded
        } else {
            self.settings = AppSettings()
        }
    }

    private func saveSettings() {
        if let data = try? JSONEncoder().encode(settings) {
            defaults.set(data, forKey: settingsKey)
        }
    }

    // MARK: - Convenience Accessors

    var displayMode: DisplayMode {
        get { settings.displayMode }
        set { settings.displayMode = newValue }
    }

    var windowOpacity: Double {
        get { settings.windowOpacity }
        set { settings.windowOpacity = newValue }
    }

    var windowFontSize: Double {
        get { settings.windowFontSize }
        set { settings.windowFontSize = newValue }
    }

    var windowLevel: LyricsWindowLevel {
        get { settings.windowLevel }
        set { settings.windowLevel = newValue }
    }

    var lyricsOffsetSeconds: Double {
        get { settings.lyricsOffsetSeconds }
        set { settings.lyricsOffsetSeconds = newValue }
    }

    var windowFontName: String {
        get { settings.windowFontName }
        set { settings.windowFontName = newValue }
    }
}
