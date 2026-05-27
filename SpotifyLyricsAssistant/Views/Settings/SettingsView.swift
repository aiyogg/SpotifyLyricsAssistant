import SwiftUI

/// Preferences / Settings window view.
struct SettingsView: View {
    @EnvironmentObject var settings: SettingsViewModel
    @EnvironmentObject var player: PlayerViewModel
    @State private var selectedTab = SettingsTab.appearance

    enum SettingsTab: String, CaseIterable {
        case appearance = "外观"
        case lyrics = "歌词来源"
        case advanced = "高级"

        var icon: String {
            switch self {
            case .appearance: return "paintbrush"
            case .lyrics: return "music.note.list"
            case .advanced: return "gearshape.2"
            }
        }
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            ForEach(SettingsTab.allCases, id: \.self) { tab in
                tabContent(tab)
                    .tabItem {
                        Label(tab.rawValue, systemImage: tab.icon)
                    }
                    .tag(tab)
            }
        }
        .frame(width: 480, height: 400)
        .padding()
    }

    @ViewBuilder
    private func tabContent(_ tab: SettingsTab) -> some View {
        switch tab {
        case .appearance:
            AppearanceSettingsView()
                .environmentObject(settings)
        case .lyrics:
            LyricsSourceSettingsView()
                .environmentObject(settings)
                .environmentObject(player)
        case .advanced:
            AdvancedSettingsView()
                .environmentObject(settings)
                .environmentObject(player)
        }
    }
}

// MARK: - Appearance Settings

struct AppearanceSettingsView: View {
    @EnvironmentObject var settings: SettingsViewModel

    // Local state buffers the Picker value so that writing back to the
    // @Published settings happens outside the current view-update cycle,
    // avoiding "Publishing changes from within view updates" runtime warnings.
    @State private var displayMode: DisplayMode = .floatingWindow

    var body: some View {
        Form {
            Section("显示模式") {
                Picker("模式", selection: $displayMode) {
                    ForEach(DisplayMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: displayMode) { newMode in
                    DispatchQueue.main.async {
                        settings.settings.displayMode = newMode
                    }
                }
            }

            Section("悬浮窗") {
                HStack {
                    Text("字体大小")
                    Slider(
                        value: $settings.settings.windowFontSize,
                        in: 12...48,
                        step: 1
                    )
                    Text("\(Int(settings.settings.windowFontSize))pt")
                        .monospacedDigit()
                        .frame(width: 40)
                }

                HStack {
                    Text("透明度")
                    Slider(
                        value: $settings.settings.windowOpacity,
                        in: 0.3...1.0,
                        step: 0.05
                    )
                    Text("\(Int(settings.settings.windowOpacity * 100))%")
                        .monospacedDigit()
                        .frame(width: 40)
                }

                Picker("窗口层级", selection: $settings.settings.windowLevel) {
                    ForEach(LyricsWindowLevel.allCases, id: \.self) { level in
                        Text(level.rawValue).tag(level)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            // Sync local state from settings when the view appears
            displayMode = settings.settings.displayMode
        }
    }
}

// MARK: - Lyrics Source Settings

struct LyricsSourceSettingsView: View {
    @EnvironmentObject var settings: SettingsViewModel
    @EnvironmentObject var player: PlayerViewModel

    var body: some View {
        Form {
            Section("歌词来源优先级") {
                Text("按优先级排列，从上到下依次尝试")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                List {
                    ForEach(settings.settings.lyricsSourcePriority, id: \.self) { source in
                        HStack {
                            Image(systemName: "line.3.horizontal")
                                .foregroundStyle(.secondary)
                            Text(source.rawValue)
                            Spacer()
                        }
                    }
                    .onMove { indices, newOffset in
                        settings.settings.lyricsSourcePriority.move(fromOffsets: indices, toOffset: newOffset)
                    }
                }
                .frame(height: 120)
            }

            Section("缓存") {
                Toggle("启用歌词缓存", isOn: $settings.settings.cacheEnabled)

                Button("清除歌词缓存") {
                    Task { await player.clearLyricsCache() }
                }
                .foregroundStyle(.red)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Advanced Settings

struct AdvancedSettingsView: View {
    @EnvironmentObject var settings: SettingsViewModel
    @EnvironmentObject var player: PlayerViewModel

    var body: some View {
        Form {
            Section("同步调整") {
                HStack {
                    Text("歌词时间偏移")
                    Slider(
                        value: $settings.settings.lyricsOffsetSeconds,
                        in: -5.0...5.0,
                        step: 0.1
                    )
                    Text(String(format: "%+.1fs", settings.settings.lyricsOffsetSeconds))
                        .monospacedDigit()
                        .frame(width: 50)
                }
                Text("如果歌词比音乐快或慢，可调整此偏移量")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("状态栏") {
                HStack {
                    Text("滚动速度")
                    Slider(
                        value: $settings.settings.statusBarScrollSpeed,
                        in: 20...100,
                        step: 5
                    )
                    Text("\(Int(settings.settings.statusBarScrollSpeed))pt/s")
                        .monospacedDigit()
                        .frame(width: 60)
                }
            }

            Section("关于") {
                let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "未知"
                LabeledContent("版本", value: appVersion)
                LabeledContent("歌词来源", value: "LRCLib · 网易云 · QQ音乐")
            }
        }
        .formStyle(.grouped)
    }
}
