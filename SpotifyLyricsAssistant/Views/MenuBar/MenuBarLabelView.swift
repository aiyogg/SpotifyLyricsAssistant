import SwiftUI
import AppKit

/// The scrolling text label shown in the menu bar status item.
/// Displays the current lyrics line with a Marquee animation when text overflows.
struct MenuBarLabelView: View {
    let text: String
    let maxWidth: CGFloat = 280

    @State private var textWidth: CGFloat = 0
    @State private var offset: CGFloat = 0
    @State private var animating = false

    var body: some View {
        HStack(spacing: 4) {
            // Music note icon
            Image(systemName: "music.note")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.primary)

            // Scrolling lyrics text
            if text.isEmpty {
                Text("Spotify 歌词助手")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(.primary)
            } else {
                MarqueeText(text: text, maxWidth: maxWidth - 24)
            }
        }
        .frame(maxWidth: maxWidth)
    }
}

// MARK: - Marquee Text

struct MarqueeText: View {
    let text: String
    let maxWidth: CGFloat
    let speed: CGFloat = 40  // Points per second

    @State private var textSize: CGSize = .zero
    @State private var offset: CGFloat = 0
    @State private var isAnimating = false

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                if textSize.width > maxWidth {
                    // Scrolling text (two copies for seamless loop)
                    HStack(spacing: 40) {
                        textContent
                        textContent
                    }
                    .offset(x: offset)
                    .frame(height: geo.size.height)
                } else {
                    // Static text (fits without scrolling)
                    textContent
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(width: maxWidth, alignment: .leading)
            .clipped()
        }
        .frame(width: maxWidth, height: 16)
        .onAppear { startAnimation() }
        .onChange(of: text) { _, _ in
            offset = 0
            isAnimating = false
            // Reset size measurement
            textSize = measureText(text)
            startAnimation()
        }
    }

    private var textContent: some View {
        Text(text)
            .font(.system(size: 12, weight: .regular))
            .foregroundStyle(.primary)
            .lineLimit(1)
            .fixedSize()
            .background(
                GeometryReader { geo in
                    Color.clear.onAppear {
                        textSize = geo.size
                    }
                }
            )
    }

    private func startAnimation() {
        textSize = measureText(text)
        guard textSize.width > maxWidth else { return }
        guard !isAnimating else { return }

        isAnimating = true
        offset = 0

        // Duration based on text width and speed
        let scrollDistance = textSize.width + 40
        let duration = Double(scrollDistance) / Double(speed)

        // Pause 1s, then scroll, then repeat
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            withAnimation(.linear(duration: duration)) {
                offset = -scrollDistance
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
                offset = 0
                isAnimating = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    startAnimation()
                }
            }
        }
    }

    private func measureText(_ text: String) -> CGSize {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12)
        ]
        return (text as NSString).size(withAttributes: attributes)
    }
}
