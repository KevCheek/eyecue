import AppKit
import Combine
import SnowpineCueCore

/// User preferences, saved to UserDefaults as they change.
///
/// The strip under the camera and the floating window each keep their own text size,
/// width and number of lines. `fontSize`, `panelWidth` and `visibleLines` read and
/// change whichever one is showing.
final class Settings: ObservableObject {
    private enum Keys {
        // The strip keeps the original keys, so earlier settings carry over.
        static let fontSize = "fontSize"
        static let panelWidth = "panelWidth"
        static let visibleLines = "visibleLines"
        static let floating = "floating"
        static let floatFontSize = "floatFontSize"
        static let floatWidth = "floatWidth"
        static let floatLines = "floatLines"
        static let floatLeft = "floatLeft"
        static let floatTop = "floatTop"
        static let followVoice = "followVoice"
        static let hideFromSharing = "hideFromSharing"
        static let wordsPerMinute = "wordsPerMinute"
        static let showPrompter = "showPrompter"
    }

    static let fontRange: ClosedRange<Double> = 14...64
    static let widthRange: ClosedRange<Double> = 320...2400
    static let stripLines: ClosedRange<Int> = 2...10
    static let floatLines: ClosedRange<Int> = 2...24
    static let speedRange: ClosedRange<Double> = 60...300

    private let defaults: UserDefaults

    @Published var stripFontSize: Double { didSet { defaults.set(stripFontSize, forKey: Keys.fontSize) } }
    @Published var stripWidth: Double { didSet { defaults.set(stripWidth, forKey: Keys.panelWidth) } }
    @Published var stripLines: Int { didSet { defaults.set(stripLines, forKey: Keys.visibleLines) } }
    /// Shows the prompter as a larger window that can be moved anywhere, instead of the strip under the camera.
    @Published var floating: Bool { didSet { defaults.set(floating, forKey: Keys.floating) } }
    @Published var floatFontSize: Double { didSet { defaults.set(floatFontSize, forKey: Keys.floatFontSize) } }
    @Published var floatWidth: Double { didSet { defaults.set(floatWidth, forKey: Keys.floatWidth) } }
    @Published var floatLines: Int { didSet { defaults.set(floatLines, forKey: Keys.floatLines) } }
    @Published var followVoice: Bool { didSet { defaults.set(followVoice, forKey: Keys.followVoice) } }
    @Published var hideFromSharing: Bool { didSet { defaults.set(hideFromSharing, forKey: Keys.hideFromSharing) } }
    /// Scroll speed when not following the voice.
    @Published var wordsPerMinute: Double { didSet { defaults.set(wordsPerMinute, forKey: Keys.wordsPerMinute) } }
    @Published var showPrompter: Bool { didSet { defaults.set(showPrompter, forKey: Keys.showPrompter) } }

    /// Top left corner of the floating window in screen coordinates, once it has been placed.
    var floatTopLeft: CGPoint? {
        get {
            guard let x = defaults.object(forKey: Keys.floatLeft) as? Double,
                  let y = defaults.object(forKey: Keys.floatTop) as? Double else { return nil }
            return CGPoint(x: x, y: y)
        }
        set {
            if let point = newValue {
                defaults.set(Double(point.x), forKey: Keys.floatLeft)
                defaults.set(Double(point.y), forKey: Keys.floatTop)
            } else {
                defaults.removeObject(forKey: Keys.floatLeft)
                defaults.removeObject(forKey: Keys.floatTop)
            }
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        stripFontSize = Self.clamp(defaults.object(forKey: Keys.fontSize) as? Double ?? 24, Self.fontRange)
        stripWidth = Self.clamp(defaults.object(forKey: Keys.panelWidth) as? Double ?? 560, Self.widthRange)
        stripLines = Self.clamp(defaults.object(forKey: Keys.visibleLines) as? Int ?? 3, Self.stripLines)
        floating = defaults.object(forKey: Keys.floating) as? Bool ?? false
        floatFontSize = Self.clamp(defaults.object(forKey: Keys.floatFontSize) as? Double ?? 32, Self.fontRange)
        floatWidth = Self.clamp(defaults.object(forKey: Keys.floatWidth) as? Double ?? 820, Self.widthRange)
        floatLines = Self.clamp(defaults.object(forKey: Keys.floatLines) as? Int ?? 6, Self.floatLines)
        followVoice = defaults.object(forKey: Keys.followVoice) as? Bool ?? true
        hideFromSharing = defaults.object(forKey: Keys.hideFromSharing) as? Bool ?? true
        wordsPerMinute = Self.clamp(defaults.object(forKey: Keys.wordsPerMinute) as? Double ?? 150, Self.speedRange)
        showPrompter = defaults.object(forKey: Keys.showPrompter) as? Bool ?? true
    }

    // MARK: Whichever one is showing

    var fontSize: Double {
        get { floating ? floatFontSize : stripFontSize }
        set {
            let value = Self.clamp(newValue, Self.fontRange)
            if floating { floatFontSize = value } else { stripFontSize = value }
        }
    }

    var panelWidth: Double {
        get { floating ? floatWidth : stripWidth }
        set {
            let value = Self.clamp(newValue.rounded(), Self.widthRange)
            if floating { floatWidth = value } else { stripWidth = value }
        }
    }

    var visibleLines: Int {
        get { floating ? floatLines : stripLines }
        set {
            if floating { floatLines = Self.clamp(newValue, Self.floatLines) } else { stripLines = Self.clamp(newValue, Self.stripLines) }
        }
    }

    var lineRange: ClosedRange<Int> { floating ? Self.floatLines : Self.stripLines }

    func adjustFontSize(by delta: Double) { fontSize += delta }
    func adjustWidth(by delta: Double) { panelWidth += delta }
    func adjustSpeed(by delta: Double) { setSpeed(wordsPerMinute + delta) }
    func setSpeed(_ value: Double) { wordsPerMinute = Self.clamp(value.rounded(), Self.speedRange) }

    private static func clamp<T: Comparable>(_ value: T, _ range: ClosedRange<T>) -> T {
        min(range.upperBound, max(range.lowerBound, value))
    }

    // MARK: Derived layout values

    static let horizontalPadding: CGFloat = 24
    /// Space under the last line.
    static let bottomMargin: CGFloat = 14
    /// The floating window's top band, where its status shows and where it is dragged from.
    static let floatingBand: CGFloat = 30

    var textWidth: CGFloat { CGFloat(panelWidth) - Self.horizontalPadding * 2 }
    var lineHeight: CGFloat { ceil(CGFloat(fontSize) * 1.38) }

    /// Height of the whole prompter for a given top band.
    func panelHeight(band: CGFloat) -> CGFloat { band + CGFloat(visibleLines) * lineHeight + Self.bottomMargin }

    /// The limits a drag works within, for the one showing, given the room on its screen.
    func limits(band: CGFloat, maxWidth: CGFloat, maxHeight: CGFloat) -> PanelLimits {
        let upper = max(CGFloat(Self.widthRange.lowerBound), min(CGFloat(Self.widthRange.upperBound), maxWidth.rounded(.down)))
        let fitting = Int(((maxHeight - band - Self.bottomMargin) / lineHeight).rounded(.down))
        let mostLines = max(lineRange.lowerBound, min(lineRange.upperBound, fitting))
        return PanelLimits(width: CGFloat(Self.widthRange.lowerBound)...upper, lines: lineRange.lowerBound...mostLines,
                           lineHeight: lineHeight, chrome: band + Self.bottomMargin)
    }

    var bodyFont: NSFont {
        NSFont(name: BrandFonts.bodyName, size: CGFloat(fontSize)) ?? .systemFont(ofSize: CGFloat(fontSize), weight: .medium)
    }

    var headingFont: NSFont {
        let size = max(11, CGFloat(fontSize) * 0.6)
        return NSFont(name: BrandFonts.headingName, size: size) ?? .systemFont(ofSize: size, weight: .semibold)
    }
}
