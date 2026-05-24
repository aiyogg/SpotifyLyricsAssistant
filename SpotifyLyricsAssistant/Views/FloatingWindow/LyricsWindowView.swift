import SwiftUI

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
        .frame(minWidth: 250, minHeight: 60)
    }
}

// MARK: - Glass Background

struct GlassBackground: View {
    var body: some View {
        ZStack {
            // NSVisualEffectView via AppKit bridge
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            // Subtle border
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        }
    }
}

// MARK: - Visual Effect (AppKit bridge)

struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        view.wantsLayer = true
        view.layer?.cornerRadius = 16
        view.layer?.masksToBounds = true
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.blendingMode = blendingMode
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

// MARK: - Window Controls Overlay

struct WindowControlsOverlay: View {
    @EnvironmentObject var player: PlayerViewModel
    @EnvironmentObject var settings: SettingsViewModel

    var body: some View {
        VStack {
            HStack {
                Spacer()
                HStack(spacing: 8) {
                    // Reload lyrics
                    ControlButton(icon: "arrow.clockwise", tooltip: "重新加载歌词") {
                        Task { await player.reloadLyrics() }
                    }

                    // Font size controls
                    ControlButton(icon: "textformat.size.smaller", tooltip: "缩小字体") {
                        settings.settings.windowFontSize = max(12, settings.settings.windowFontSize - 2)
                    }
                    ControlButton(icon: "textformat.size.larger", tooltip: "放大字体") {
                        settings.settings.windowFontSize = min(48, settings.settings.windowFontSize + 2)
                    }

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
