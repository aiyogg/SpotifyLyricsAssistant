import SwiftUI
import AppKit
import CoreText

/// The root SwiftUI view displayed inside the FloatingLyricsPanel.
/// Features a glassmorphism background, animated lyrics lines, and a drag handle.
struct LyricsWindowView: View {
    @EnvironmentObject var player: PlayerViewModel
    @EnvironmentObject var settings: SettingsViewModel
    @State private var isHovering = false
    @State private var showControls = false

    var body: some View {
        ZStack {
            // Glassmorphism background
            GlassBackground()

            if player.playerState == .stopped || !player.isSpotifyRunning {
                SpotifyNotRunningView()
            } else if player.isLoadingLyrics {
                LoadingView()
            } else if player.hasLyrics {
                LyricsScrollView()
                    .environmentObject(player)
                    .environmentObject(settings)
            } else {
                NoLyricsView(
                    trackName: player.currentTrack?.name,
                    error: player.lyricsError
                )
            }

            // Hover overlay: controls appear on hover
            if isHovering {
                WindowControlsOverlay()
                    .environmentObject(player)
                    .environmentObject(settings)
                    .transition(.opacity)
            }
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovering = hovering
            }
        }
        // Window-level opacity (applied via SwiftUI so glass effect still works)
        .opacity(settings.settings.windowOpacity)
        .frame(minWidth: 250, minHeight: 60)
    }
}

// MARK: - Glass Background

struct GlassBackground: View {
    var body: some View {
        if #available(macOS 26.0, *) {
            Color.clear
                .glassEffect(.clear.interactive(), in: .rect(cornerRadius: 16))
                // 1. Top-edge inner glow: Simulates light hitting the top edge of the glass block
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(
                            LinearGradient(
                                stops: [
                                    .init(color: .white.opacity(0.35), location: 0),
                                    .init(color: .white.opacity(0.0), location: 0.2)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 1
                        )
                        .blendMode(.overlay)
                )
                // 2. Outer refraction rim: Simulates the bevel/edge of physical glass
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(
                            LinearGradient(
                                stops: [
                                    .init(color: .white.opacity(0.25), location: 0),
                                    .init(color: .white.opacity(0.02), location: 0.5),
                                    .init(color: .white.opacity(0.15), location: 1)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.5
                        )
                )
        } else {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
                )
        }
    }
}



// MARK: - No Lyrics / Error View

struct NoLyricsView: View {
    let trackName: String?
    let error: String?

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: "music.note.list")
                .font(.system(size: 20))
                .foregroundStyle(.secondary)
            Text(error ?? "暂无歌词")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
            if let name = trackName {
                Text(name)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .padding()
    }
}

// MARK: - Loading View

struct LoadingView: View {
    @State private var dotCount = 0
    let timer = Timer.publish(every: 0.4, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 8) {
            ProgressView()
                .scaleEffect(0.7)
                .tint(.white.opacity(0.7))
            Text("正在获取歌词\(String(repeating: ".", count: dotCount))")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .onReceive(timer) { _ in
            dotCount = (dotCount + 1) % 4
        }
    }
}

// MARK: - Spotify Not Running

struct SpotifyNotRunningView: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "music.note")
                .font(.system(size: 16))
                .foregroundStyle(.green.opacity(0.8))
            Text("等待 Spotify 播放...")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Font Family Info

/// Wraps a font family name with its localized display name.
/// We store the internal `familyName` (used with Font.custom) but show
/// the system-localized `displayName` to the user.
private struct FontFamilyItem: Identifiable {
    let id: String       // PostScript/internal family name — used for Font.custom()
    let displayName: String  // Localized name shown in the picker

    /// Builds a list of all installed font families with their localized names,
    /// sorted by display name using the current locale.
    static func allInstalled() -> [FontFamilyItem] {
        NSFontManager.shared.availableFontFamilies.compactMap { family in
            let descriptor = CTFontDescriptorCreateWithNameAndSize(family as CFString, 12)
            let font = CTFontCreateWithFontDescriptor(descriptor, 12, nil)
            // CTFontCopyLocalizedName returns the name in the user's locale
            let localized = CTFontCopyLocalizedName(font, kCTFontFamilyNameKey, nil)
                .map { $0 as String } ?? family
            return FontFamilyItem(id: family, displayName: localized)
        }
        .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    }
}

// MARK: - Window Controls Overlay

struct WindowControlsOverlay: View {
    @EnvironmentObject var player: PlayerViewModel
    @EnvironmentObject var settings: SettingsViewModel

    // Computed once per hover — CoreText lookup is fast but we avoid calling it per render
    private let fontFamilies: [FontFamilyItem] = FontFamilyItem.allInstalled()

    private var currentFontDisplayName: String {
        if settings.settings.windowFontName.isEmpty { return "系统默认" }
        return fontFamilies.first { $0.id == settings.settings.windowFontName }?.displayName
            ?? settings.settings.windowFontName
    }

    var body: some View {
        VStack {
            HStack {
                Spacer()
                HStack(spacing: 6) {
                    // Reload lyrics
                    ControlButton(icon: "arrow.clockwise", tooltip: "重新加载歌词") {
                        Task { await player.reloadLyrics() }
                    }

                    Divider().frame(height: 14)

                    // Time offset controls (local to current track)
                    if player.trackOffsetSeconds != 0 {
                        Text(String(format: "%+.1fs", player.trackOffsetSeconds))
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    ControlTextButton(text: "快", tooltip: "当前歌词提前0.5秒") {
                        player.trackOffsetSeconds -= 0.5
                        player.updateCurrentLine(at: player.playerPosition)
                    }
                    ControlTextButton(text: "慢", tooltip: "当前歌词延后0.5秒") {
                        player.trackOffsetSeconds += 0.5
                        player.updateCurrentLine(at: player.playerPosition)
                    }

                    Divider().frame(height: 14)

                    // Opacity controls
                    ControlButton(icon: "sun.min", tooltip: "降低透明度") {
                        settings.settings.windowOpacity = max(0.2, settings.settings.windowOpacity - 0.1)
                    }
                    ControlButton(icon: "sun.max", tooltip: "提高透明度") {
                        settings.settings.windowOpacity = min(1.0, settings.settings.windowOpacity + 0.1)
                    }

                    Divider().frame(height: 14)

                    // Font size controls
                    ControlButton(icon: "textformat.size.smaller", tooltip: "缩小字体") {
                        settings.settings.windowFontSize = max(12, settings.settings.windowFontSize - 2)
                    }
                    ControlButton(icon: "textformat.size.larger", tooltip: "放大字体") {
                        settings.settings.windowFontSize = min(48, settings.settings.windowFontSize + 2)
                    }

                    // Font picker
                    Menu {
                        // "系统默认" always at the top
                        Button {
                            settings.settings.windowFontName = ""
                        } label: {
                            HStack {
                                Text("系统默认")
                                if settings.settings.windowFontName.isEmpty {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                        Divider()
                        // All installed font families with localized display names
                        ForEach(fontFamilies) { item in
                            Button {
                                // Store internal family name (used by Font.custom)
                                settings.settings.windowFontName = item.id
                            } label: {
                                HStack {
                                    // Show user-friendly localized name
                                    Text(item.displayName)
                                    if settings.settings.windowFontName == item.id {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 2) {
                            Image(systemName: "textformat")
                                .font(.system(size: 11, weight: .medium))
                            Image(systemName: "chevron.down")
                                .font(.system(size: 8, weight: .medium))
                        }
                        .foregroundStyle(.secondary)
                        .frame(height: 22)
                        .padding(.horizontal, 4)
                        .background(Color.white.opacity(0.0), in: RoundedRectangle(cornerRadius: 6))
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .help("选择字体（\(currentFontDisplayName)）")


                    Divider().frame(height: 14)

                    // Close
                    ControlButton(icon: "xmark", tooltip: "隐藏悬浮窗") {
                        NSApp.windows.first { $0 is FloatingLyricsPanel }?.orderOut(nil)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
                .padding(8)
            }
            Spacer()
        }
    }
}

struct ControlButton: View {
    let icon: String
    let tooltip: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(isHovered ? .primary : .secondary)
                .frame(width: 22, height: 22)
                .background(isHovered ? Color.white.opacity(0.15) : Color.clear,
                             in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .help(tooltip)
        .onHover { isHovered = $0 }
    }
}

struct ControlTextButton: View {
    let text: String
    let tooltip: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text(text)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(isHovered ? .primary : .secondary)
                .frame(width: 22, height: 22)
                .background(isHovered ? Color.white.opacity(0.15) : Color.clear,
                             in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .help(tooltip)
        .onHover { isHovered = $0 }
    }
}
