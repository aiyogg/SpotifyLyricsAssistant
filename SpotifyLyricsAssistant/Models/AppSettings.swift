import Foundation
import SwiftUI

/// User-configurable settings for the app
/// Stored in UserDefaults via @AppStorage
struct AppSettings: Codable {

    // MARK: - Display Mode
    var displayMode: DisplayMode = .floatingWindow

    // MARK: - Floating Window Appearance
    var windowOpacity: Double = 0.92
    var windowFontSize: Double = 22
    var windowFrame: CGRect = CGRect(x: 100, y: 100, width: 520, height: 140)
    var colorScheme: LyricsColorScheme = .dark
    var windowLevel: LyricsWindowLevel = .floating

    // MARK: - Status Bar
    var statusBarScrollSpeed: Double = 50  // pixels per second
    var showAlbumArtInMenuBar: Bool = false

    // MARK: - Lyrics Sources
    var lyricsSourcePriority: [LyricsSource] = [.lrclib, .netease, .qqMusic]
    var cacheEnabled: Bool = true

    // MARK: - Sync
    var lyricsOffsetSeconds: Double = 0.0  // Manual timing adjustment

    // MARK: - Launch
    var launchAtLogin: Bool = false
}

enum DisplayMode: String, Codable, CaseIterable {
    case floatingWindow = "悬浮窗"
    case statusBarOnly = "仅状态栏"
    case both = "两者都显示"
}

enum LyricsColorScheme: String, Codable, CaseIterable {
    case dark = "深色"
    case light = "浅色"
    case system = "跟随系统"
    case custom = "自定义"
}

enum LyricsWindowLevel: String, Codable, CaseIterable {
    case floating = "悬浮（普通置顶）"
    case alwaysOnTop = "始终最顶层"

    var nsWindowLevel: NSWindow.Level {
        switch self {
        case .floating: return .floating
        case .alwaysOnTop: return .screenSaver
        }
    }
}
