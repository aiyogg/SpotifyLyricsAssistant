import AppKit
import SwiftUI

/// A frameless, always-on-top, transparent floating panel for displaying lyrics.
/// Subclasses NSPanel to gain non-activating, floating behavior while hosting SwiftUI content.
final class FloatingLyricsPanel: NSPanel {

    private var hostingView: NSHostingView<AnyView>?

    // UserDefaults key for frame persistence (avoids FSFindFolder Carbon API)
    private static let frameKey = "FloatingLyricsPanel.frame"

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 140),
            styleMask: [
                .nonactivatingPanel,    // Don't steal focus from other apps
                .fullSizeContentView,   // Content extends under title bar
                .borderless,            // No title bar chrome
                .resizable              // Allow resize
            ],
            backing: .buffered,
            defer: false
        )

        configure()
    }

    private func configure() {
        // Visual
        isOpaque = false
        backgroundColor = .clear
        // On macOS 26+, glassEffect renders its own shadow/glow.
        // Keeping hasShadow=true causes a rectangular NSPanel shadow that
        // conflicts with the glass's rounded corners, creating a double-border.
        hasShadow = false

        // Always on top
        level = .floating

        // Show on all Spaces and over full-screen apps
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        // Draggable by clicking anywhere in the background
        isMovableByWindowBackground = true

        // Don't hide when app deactivates
        hidesOnDeactivate = false

        // Minimum size
        minSize = NSSize(width: 250, height: 60)

        // Restore saved position, or place at bottom-center on first launch
        restoreFrame()
    }

    // MARK: - Content

    func setContent<Content: View>(_ content: Content) {
        let hosting = NSHostingView(rootView: AnyView(content))
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = .clear
        hosting.layer?.isOpaque = false
        // Clip the hosting view layer to the same rounded rect as glassEffect.
        // This physically prevents any background bleed from rendering outside
        // the rounded corners — the root cause of the faint gray rectangle.
        hosting.layer?.cornerRadius = 16
        hosting.layer?.cornerCurve = .continuous  // matches SwiftUI's .continuous style
        hosting.layer?.masksToBounds = true
        contentView = hosting
        hostingView = hosting
    }

    // MARK: - Frame Persistence (via UserDefaults — no Carbon FSFindFolder)

    private func restoreFrame() {
        if let frameStr = UserDefaults.standard.string(forKey: Self.frameKey),
           let frameValue = parseFrameString(frameStr),
           frameValue != .zero {
            // Validate that the saved frame is still on a visible screen
            let isOnScreen = NSScreen.screens.contains { screen in
                screen.visibleFrame.intersects(frameValue)
            }
            if isOnScreen {
                setFrame(frameValue, display: false)
                return
            }
        }

        // First launch: center horizontally, near bottom of screen
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let w: CGFloat = 520
            let h: CGFloat = 140
            let x = screenFrame.midX - w / 2
            let y = screenFrame.minY + 100
            setFrame(NSRect(x: x, y: y, width: w, height: h), display: false)
        } else {
            center()
        }
    }

    /// Call this when the window moves/resizes to persist the frame.
    func saveFrame() {
        UserDefaults.standard.set(NSStringFromRect(frame), forKey: Self.frameKey)
    }

    // MARK: - Overrides

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    // Save frame on every move/resize
    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        super.setFrame(frameRect, display: flag)
        // Only save if window is actually visible (avoid saving zero frame at init)
        if isVisible {
            saveFrame()
        }
    }

    // MARK: - Level Management

    func applyWindowLevel(_ level: LyricsWindowLevel) {
        self.level = level.nsWindowLevel
    }

    // MARK: - Show / Hide

    func show() {
        makeKeyAndOrderFront(nil)
        orderFrontRegardless()
    }

    func hide() {
        orderOut(nil)
    }
}

// MARK: - Helper

/// Parses a frame string saved by NSStringFromRect back into an NSRect.
/// Returns nil if the string is invalid or represents a zero rect.
private func parseFrameString(_ string: String) -> NSRect? {
    // NSRectFromString is a free AppKit function (C-level)
    // We'll use Scanner to parse "{{x, y}, {w, h}}"
    let s = string.trimmingCharacters(in: .whitespaces)
    guard s.hasPrefix("{") else { return nil }
    // Remove outer braces: {{x, y}, {w, h}} -> {x, y}, {w, h}
    var scanner = Scanner(string: s)
    var x = 0.0, y = 0.0, w = 0.0, h = 0.0
    scanner.charactersToBeSkipped = CharacterSet(charactersIn: "{}., ")
    guard scanner.scanDouble(&x),
          scanner.scanDouble(&y),
          scanner.scanDouble(&w),
          scanner.scanDouble(&h) else { return nil }
    let rect = NSRect(x: x, y: y, width: w, height: h)
    return rect == .zero ? nil : rect
}
