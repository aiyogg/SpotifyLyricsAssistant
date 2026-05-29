import SwiftUI

/// Displays the full scrollable lyrics list with the current line highlighted and auto-scrolled into view.
struct LyricsScrollView: View {
    @EnvironmentObject var player: PlayerViewModel
    @EnvironmentObject var settings: SettingsViewModel

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 2) {
                    ForEach(Array((player.lyrics?.lines ?? []).enumerated()), id: \.element.id) { index, line in
                        LyricsLineView(
                            text: line.text,
                            isCurrent: index == player.currentLineIndex,
                            isPrevious: index == player.currentLineIndex - 1,
                            isNext: index == player.currentLineIndex + 1,
                            fontSize: settings.settings.windowFontSize,
                            fontName: settings.settings.windowFontName
                        )
                        .id(line.id)
                        .onTapGesture(count: 2) {
                            player.seek(to: line.timestamp)
                        }
                    }
                }
                .padding(.vertical, 16)
                .padding(.horizontal, 20)
            }
            .onChange(of: player.currentLineIndex) { _, newIndex in
                guard let lyrics = player.lyrics, newIndex < lyrics.lines.count else { return }
                let line = lyrics.lines[newIndex]
                withAnimation(.easeInOut(duration: 0.4)) {
                    proxy.scrollTo(line.id, anchor: .center)
                }
            }
        }
    }
}

// MARK: - Single Lyrics Line View

struct LyricsLineView: View {
    let text: String
    let isCurrent: Bool
    let isPrevious: Bool
    let isNext: Bool
    let fontSize: Double
    var fontName: String = ""

    private var displayText: String {
        text.isEmpty ? "♪" : text
    }

    private func makeFont(size: Double, weight: Font.Weight) -> Font {
        if fontName.isEmpty {
            return .system(size: size, weight: weight, design: .default)
        } else {
            // Use custom font name, fallback to system if unavailable
            return Font.custom(fontName, size: size).weight(weight)
        }
    }

    var body: some View {
        Text(displayText)
            .font(makeFont(size: effectiveFontSize, weight: fontWeight))
            .foregroundStyle(textForegroundStyle)
            // Shadow ensures readability against any background color showing
            // through the transparent glass (white page, dark editor, etc.)
            .shadow(color: .black.opacity(isCurrent ? 0.55 : 0.35), radius: 3, x: 0, y: 1)
            .multilineTextAlignment(.center)
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, isCurrent ? 6 : 3)
            .frame(maxWidth: .infinity)
            .scaleEffect(isCurrent ? 1.0 : 0.92)
            .animation(.spring(duration: 0.35, bounce: 0.1), value: isCurrent)
    }

    private var effectiveFontSize: Double {
        if isCurrent { return fontSize }
        if isPrevious || isNext { return fontSize * 0.78 }
        return fontSize * 0.68
    }

    private var fontWeight: Font.Weight {
        isCurrent ? .semibold : .regular
    }

    private var textForegroundStyle: AnyShapeStyle {
        if isCurrent {
            return AnyShapeStyle(.primary)
        } else if isPrevious || isNext {
            return AnyShapeStyle(.secondary)
        } else {
            return AnyShapeStyle(.tertiary)
        }
    }
}
