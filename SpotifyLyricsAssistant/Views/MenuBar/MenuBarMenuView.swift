import SwiftUI

/// The dropdown menu content displayed when user clicks the menu bar item.
struct MenuBarMenuView: View {
    @EnvironmentObject var player: PlayerViewModel
    @EnvironmentObject var settings: SettingsViewModel

    @State private var showingSettings = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // Now Playing header
            NowPlayingHeader()
                .environmentObject(player)
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 12)

            Divider()
                .padding(.horizontal, 8)

            // Display mode toggle
            VStack(alignment: .leading, spacing: 2) {
                SectionHeader("显示模式")
                    .padding(.horizontal, 16)
                    .padding(.top, 10)

                ForEach(DisplayMode.allCases, id: \.self) { mode in
                    MenuRow(
                        title: mode.rawValue,
                        isSelected: settings.displayMode == mode,
                        systemImage: displayModeIcon(mode)
                    ) {
                        settings.displayMode = mode
                    }
                }
            }
            .padding(.bottom, 8)

            Divider()
                .padding(.horizontal, 8)

            // Actions
            VStack(alignment: .leading, spacing: 2) {
                MenuRow(title: player.reloadTooltip, systemImage: "arrow.clockwise") {
                    Task { await player.reloadLyrics() }
                }
                MenuRow(title: "设置...", systemImage: "gearshape") {
                    openSettings()
                }
            }
            .padding(.vertical, 8)

            Divider()
                .padding(.horizontal, 8)

            // Source info
            if let lyrics = player.lyrics {
                VStack(alignment: .leading, spacing: 2) {
                    Text("歌词来源：\(lyrics.source.rawValue)")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                    if let next = player.nextReloadSource {
                        Text("重获时将切换至：\(next.rawValue)")
                            .font(.caption)
                            .foregroundStyle(.quaternary)
                            .padding(.horizontal, 16)
                    }
                }
                .padding(.bottom, 4)
            }

            MenuRow(title: "退出", systemImage: "power") {
                NSApplication.shared.terminate(nil)
            }
            .padding(.bottom, 8)
        }
        .frame(width: 260)
    }

    // MARK: - Helpers

    private func displayModeIcon(_ mode: DisplayMode) -> String {
        switch mode {
        case .floatingWindow: return "macwindow"
        case .statusBarOnly: return "menubar.rectangle"
        case .both: return "rectangle.split.2x1"
        }
    }


    private func openSettings() {
        // In .accessory policy apps, we must explicitly activate to show windows
        NSApp.activate(ignoringOtherApps: true)

        // Reuse existing settings window if already open — force it to front
        if let settingsWindow = NSApp.windows.first(where: { $0.title == "设置" }) {
            // Temporarily raise the level to guarantee it appears above all other windows,
            // then restore to normal so it doesn't permanently float above everything.
            settingsWindow.level = .floating
            settingsWindow.orderFrontRegardless()
            settingsWindow.makeKeyAndOrderFront(nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                settingsWindow.level = .normal
            }
            return
        }

        // Create a new settings window
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 430),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "设置"
        window.isReleasedWhenClosed = false  // Prevent ARC dealloc on close
        window.contentView = NSHostingView(rootView:
            SettingsView()
                .environmentObject(settings)
                .environmentObject(player)
        )
        window.center()
        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)
    }
}

// MARK: - Subviews

struct NowPlayingHeader: View {
    @EnvironmentObject var player: PlayerViewModel

    var body: some View {
        HStack(spacing: 10) {
            // Album art placeholder / icon
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.green.opacity(0.15))
                    .frame(width: 40, height: 40)
                Image(systemName: "music.note")
                    .font(.system(size: 16))
                    .foregroundStyle(.green)
            }

            VStack(alignment: .leading, spacing: 2) {
                if let track = player.currentTrack {
                    Text(track.name)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    Text(track.artist)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    Text("未在播放")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()

            // State indicator
            Circle()
                .fill(player.playerState == .playing ? Color.green : Color.secondary.opacity(0.4))
                .frame(width: 7, height: 7)
        }
    }
}

struct SectionHeader: View {
    let title: String
    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
    }
}

struct MenuRow: View {
    let title: String
    var isSelected: Bool = false
    var systemImage: String? = nil
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let icon = systemImage {
                    Image(systemName: icon)
                        .font(.system(size: 12))
                        .frame(width: 16)
                        .foregroundStyle(.secondary)
                }
                Text(title)
                    .font(.system(size: 13))
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 5)
            .background(isHovered ? Color.accentColor.opacity(0.12) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}
