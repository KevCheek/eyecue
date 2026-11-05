import AppKit
import Combine

/// User preferences, saved to UserDefaults as they change.
final class Settings: ObservableObject {
    private enum Keys {
        static let fontSize = "fontSize"
        static let panelWidth = "panelWidth"
        static let visibleLines = "visibleLines"
        static let followVoice = "followVoice"
        static let hideFromSharing = "hideFromSharing"
        static let wordsPerMinute = "wordsPerMinute"
        static let showPrompter = "showPrompter"
    }

    private let defaults: UserDefaults

    @Published var fontSize: Double { didSet { defaults.set(fontSize, forKey: Keys.fontSize) } }
    @Published var panelWidth: Double { didSet { defaults.set(panelWidth, forKey: Keys.panelWidth) } }
    @Published var visibleLines: Int { didSet { defaults.set(visibleLines, forKey: Keys.visibleLines) } }
    @Published var followVoice: Bool { didSet { defaults.set(followVoice, forKey: Keys.followVoice) } }
    @Published var hideFromSharing: Bool { didSet { defaults.set(hideFromSharing, forKey: Keys.hideFromSharing) } }
    /// Scroll speed when not following the voice.
    @Published var wordsPerMinute: Double { didSet { defaults.set(wordsPerMinute, forKey: Keys.wordsPerMinute) } }
    @Published var showPrompter: Bool { didSet { defaults.set(showPrompter, forKey: Keys.showPrompter) } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        fontSize = defaults.object(forKey: Keys.fontSize) as? Double ?? 24
        panelWidth = defaults.object(forKey: Keys.panelWidth) as? Double ?? 560
        visibleLines = defaults.object(forKey: Keys.visibleLines) as? Int ?? 3
        followVoice = defaults.object(forKey: Keys.followVoice) as? Bool ?? true
        hideFromSharing = defaults.object(forKey: Keys.hideFromSharing) as? Bool ?? true
        wordsPerMinute = defaults.object(forKey: Keys.wordsPerMinute) as? Double ?? 150
        showPrompter = defaults.object(forKey: Keys.showPrompter) as? Bool ?? true
    }

    func adjustFontSize(by delta: Double) { fontSize = min(48, max(14, fontSize + delta)) }
    func adjustWidth(by delta: Double) { panelWidth = min(1200, max(360, panelWidth + delta)) }
    func adjustSpeed(by delta: Double) { wordsPerMinute = min(260, max(60, wordsPerMinute + delta)) }

    // MARK: Derived layout values

    static let horizontalPadding: CGFloat = 24

    var textWidth: CGFloat { CGFloat(panelWidth) - Self.horizontalPadding * 2 }
    var lineHeight: CGFloat { ceil(CGFloat(fontSize) * 1.38) }

    var bodyFont: NSFont {
        NSFont(name: BrandFonts.bodyName, size: CGFloat(fontSize)) ?? .systemFont(ofSize: CGFloat(fontSize), weight: .medium)
    }

    var headingFont: NSFont {
        let size = max(11, CGFloat(fontSize) * 0.6)
        return NSFont(name: BrandFonts.headingName, size: size) ?? .systemFont(ofSize: size, weight: .semibold)
    }
}
