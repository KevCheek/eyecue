import AppKit

/// The menu bar icon: a small notch with three lines of text under it, matching the app icon.
/// Drawn as a template image so macOS tints it for light and dark menu bars.
enum MenuBarIcon {
    static func make() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            NSColor.black.setFill()
            // The notch: square top edge, rounded bottom corners.
            NSBezierPath(rect: NSRect(x: 5, y: 0, width: 8, height: 2)).fill()
            NSBezierPath(roundedRect: NSRect(x: 5, y: 0, width: 8, height: 4.5), xRadius: 1.8, yRadius: 1.8).fill()

            func bar(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, alpha: CGFloat = 1) {
                NSColor.black.withAlphaComponent(alpha).setFill()
                NSBezierPath(roundedRect: NSRect(x: x, y: y, width: width, height: 2), xRadius: 1, yRadius: 1).fill()
            }
            bar(4.5, 7.5, 9, alpha: 0.45)  // the line already read
            bar(2.5, 11, 3.5)              // the next word
            bar(7, 11, 8.5)                // the rest of the current line
            bar(3.5, 14.5, 11)             // the line after
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Snowpine Cue"
        return image
    }
}
