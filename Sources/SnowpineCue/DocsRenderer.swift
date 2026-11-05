import AppKit
import SnowpineCueCore
import SwiftUI

/// `SnowpineCue --render-docs <folder>` draws the README pictures from the real app: the real strip view,
/// the real menu items and the real menu bar icon. The live strip hides itself from screenshots,
/// so the pictures are drawn rather than captured. Nothing is shown and the microphone is not used.
enum DocsRenderer {
    @MainActor
    static func run(outputDirectory: String) -> Int32 {
        let suite = "snowpine-cue.render-docs"
        UserDefaults().removePersistentDomain(forName: suite)
        guard let defaults = UserDefaults(suiteName: suite) else { return fail("no defaults") }
        let settings = Settings(defaults: defaults)
        let app = AppDelegate(settings: settings)
        let model = app.model

        // Move along as if the first sentence had been read aloud.
        let words = model.tokens.filter { $0.spokenIndex != nil }.prefix(19).map(\.text)
        var heard: [String] = []
        for word in words {
            heard.append(word)
            model.applyTranscript(heard.joined(separator: " "))
        }
        let rows = MenuRow.rows(from: app.makeMenu())

        let folder = URL(fileURLWithPath: outputDirectory)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try write(OverviewPicture(model: model, settings: settings, rows: rows),
                      to: folder.appendingPathComponent("overview.png"))
            try write(MenuBarPicture(), to: folder.appendingPathComponent("menu-bar.png"))
        } catch {
            return fail(error.localizedDescription)
        }
        print("DOCS OK menu rows=\(rows.count) folder=\(folder.path)")
        return 0
    }

    /// A made-up talk for the website and video pictures.
    static let demoScript = ScriptDocument(title: "Demo", sections: [
        .init(heading: "Monthly update", paragraphs: [
            "Thanks for joining today. I'll walk you through where the project stands, what changed this month, and what I need from you.",
            "First, the new booking page went live on Monday, and sign ups are already coming in.",
        ]),
    ])

    /// `SnowpineCue --render-frames <folder>` draws the real strip once per word of the demo talk,
    /// as if it were being read aloud, for the website and the video.
    @MainActor
    static func runFrames(outputDirectory: String) -> Int32 {
        let suite = "snowpine-cue.render-frames"
        UserDefaults().removePersistentDomain(forName: suite)
        guard let defaults = UserDefaults(suiteName: suite) else { return fail("no defaults") }
        let settings = Settings(defaults: defaults)
        let model = PrompterModel(settings: settings, document: demoScript)
        model.showListeningForPictures()
        let words = model.tokens.filter { $0.spokenIndex != nil }.map(\.text)
        let band: CGFloat = 38
        let height = band + CGFloat(settings.visibleLines) * settings.lineHeight + 14
        let folder = URL(fileURLWithPath: outputDirectory)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            var heard: [String] = []
            for index in 0...words.count {
                if index > 0 {
                    heard.append(words[index - 1])
                    model.applyTranscript(heard.joined(separator: " "))
                }
                let view = PrompterView(model: model, settings: settings, topBand: band)
                    .frame(width: CGFloat(settings.panelWidth), height: height)
                try write(view, to: folder.appendingPathComponent(String(format: "strip-%03d.png", index)), scale: 3)
            }
        } catch {
            return fail(error.localizedDescription)
        }
        print("FRAMES OK words=\(words.count) folder=\(folder.path)")
        return 0
    }

    @MainActor
    private static func write<V: View>(_ view: V, to url: URL, scale: CGFloat = 2) throws {
        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else {
            throw RenderError(errorDescription: "could not render \(url.lastPathComponent)")
        }
        try png.write(to: url)
    }

    private struct RenderError: LocalizedError {
        let errorDescription: String?
    }

    private static func fail(_ message: String) -> Int32 {
        FileHandle.standardError.write(Data("DOCS FAIL: \(message)\n".utf8))
        return 1
    }
}

/// One line of the real menu, flattened for drawing.
struct MenuRow: Identifiable {
    let id: Int
    let title: String
    let shortcut: String
    let isSeparator: Bool
    let isEnabled: Bool
    let isChecked: Bool
    let hasSubmenu: Bool

    static func rows(from menu: NSMenu) -> [MenuRow] {
        menu.items.enumerated().map { index, item in
            MenuRow(id: index, title: item.title, shortcut: shortcut(for: item), isSeparator: item.isSeparatorItem,
                    isEnabled: item.isEnabled, isChecked: item.state == .on, hasSubmenu: item.submenu != nil)
        }
    }

    private static func shortcut(for item: NSMenuItem) -> String {
        guard let scalar = item.keyEquivalent.unicodeScalars.first else { return "" }
        let mods = item.keyEquivalentModifierMask
        var text = ""
        if mods.contains(.control) { text += "\u{2303}" }
        if mods.contains(.option) { text += "\u{2325}" }
        if mods.contains(.shift) { text += "\u{21E7}" }
        if mods.contains(.command) { text += "\u{2318}" }
        switch Int(scalar.value) {
        case NSDownArrowFunctionKey: text += "\u{2193}"
        case NSUpArrowFunctionKey: text += "\u{2191}"
        default: text += item.keyEquivalent.uppercased()
        }
        return text
    }
}

private enum DocColors {
    static let accent = Palette.next
    static let paper = Color.white
    static let desktopTop = Color(white: 0.2)     // #333333
    static let desktopBottom = Color(white: 0.08) // #141414
    static let menuBar = Color.black.opacity(0.32)
    static let menu = Color(white: 0.17)
}

/// A numbered marker that the legend refers to.
private struct Badge: View {
    let number: Int
    var body: some View {
        Text("\(number)")
            .font(.custom(BrandFonts.headingName, size: 13))
            .foregroundColor(.black)
            .frame(width: 22, height: 22)
            .background(Circle().fill(DocColors.accent))
            .shadow(color: .black.opacity(0.4), radius: 3, y: 1)
    }
}

/// The right side of the menu bar, with the Snowpine Cue icon first.
private struct StatusIcons: View {
    var highlight = true
    var body: some View {
        HStack(spacing: 14) {
            Image(nsImage: MenuBarIcon.make())
                .renderingMode(.template)
                .foregroundColor(.white)
                .frame(width: 22, height: 22)
                .background(RoundedRectangle(cornerRadius: 5).fill(Color.white.opacity(highlight ? 0.22 : 0)))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(DocColors.accent, lineWidth: highlight ? 2 : 0).padding(-3))
            Image(systemName: "wifi").frame(width: 22)
            Image(systemName: "battery.75percent").frame(width: 30)
            Image(systemName: "magnifyingglass").frame(width: 22)
            Image(systemName: "switch.2").frame(width: 22)
            Text("Thu 9:41 AM").frame(width: 92, alignment: .trailing)
        }
        .font(.system(size: 13.5, weight: .medium))
        .foregroundColor(.white)
    }
}

/// The whole picture: menu bar, notch, the strip under it, and the open menu.
struct OverviewPicture: View {
    @ObservedObject var model: PrompterModel
    @ObservedObject var settings: Settings
    let rows: [MenuRow]

    private let width: CGFloat = 1300
    private let height: CGFloat = 545
    private let barHeight: CGFloat = 32
    private let menuWidth: CGFloat = 330
    // The right-hand icons are laid out at fixed widths (see StatusIcons), so the Snowpine Cue icon sits here:
    private var iconX: CGFloat { width - 16 - 280 }
    private var menuX: CGFloat { min(iconX - 8, width - 12 - menuWidth) }
    private var stripHeight: CGFloat { barHeight + CGFloat(settings.visibleLines) * settings.lineHeight + 14 }

    var body: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(colors: [DocColors.desktopTop, DocColors.desktopBottom], startPoint: .top, endPoint: .bottom)

            // Menu bar
            HStack(spacing: 18) {
                Image(systemName: "apple.logo")
                Text("Finder").fontWeight(.bold)
                Text("File"); Text("Edit"); Text("View"); Text("Window"); Text("Help")
                Spacer()
            }
            .font(.system(size: 13.5))
            .foregroundColor(.white)
            .padding(.leading, 18)
            .frame(width: width, height: barHeight)
            .background(DocColors.menuBar)

            StatusIcons()
                .frame(height: barHeight)
                .offset(x: iconX)

            // The strip, hanging from the notch
            PrompterView(model: model, settings: settings, topBand: barHeight)
                .frame(width: CGFloat(settings.panelWidth), height: stripHeight)
                .offset(x: (width - CGFloat(settings.panelWidth)) / 2)

            // The notch over the middle of the strip's top band
            UnevenRoundedRectangle(bottomLeadingRadius: 11, bottomTrailingRadius: 11)
                .fill(Color.black)
                .frame(width: 190, height: barHeight)
                .overlay(Circle().fill(Color(white: 0.12)).frame(width: 7, height: 7))
                .offset(x: (width - 190) / 2)

            // The open menu, under the icon
            MenuPicture(rows: rows)
                .frame(width: menuWidth)
                .offset(x: menuX, y: barHeight + 5)

            // Markers
            Badge(number: 1).offset(x: iconX - 34, y: 5)
            Badge(number: 2).offset(x: (width - CGFloat(settings.panelWidth)) / 2 - 32, y: barHeight + 18)
            Badge(number: 3).offset(x: menuX - 30, y: quitRowY)

            Legend()
                .frame(width: 540, alignment: .leading)
                .offset(x: 40, y: stripHeight + 70)
        }
        .frame(width: width, height: height)
        .clipped()
    }

    /// Where the Quit row sits inside the drawn menu.
    private var quitRowY: CGFloat {
        var y = barHeight + 5 + 6
        for row in rows {
            if row.title.hasPrefix("Quit") { return y }
            y += row.isSeparator ? MenuPicture.separatorHeight : MenuPicture.rowHeight
        }
        return y
    }
}

private struct Legend: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            item(1, "The Snowpine Cue icon in the menu bar.", "Click it for the menu: open or paste a script, settings, and Quit.")
            item(2, "The strip under your camera.", "Click it to start or pause, scroll over it to move a line, right-click it for the same menu.")
            item(3, "Quit Snowpine Cue is at the bottom of the menu.", "Command Q works while the menu is open.")
        }
        .padding(22)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.black.opacity(0.35)))
    }

    private func item(_ number: Int, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Badge(number: number)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.custom(BrandFonts.headingName, size: 16)).foregroundColor(DocColors.paper)
                Text(detail).font(.custom(BrandFonts.regularName, size: 14)).foregroundColor(DocColors.paper.opacity(0.75))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// The real menu items drawn in the style of a macOS menu.
struct MenuPicture: View {
    static let rowHeight: CGFloat = 22
    static let separatorHeight: CGFloat = 11
    let rows: [MenuRow]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(rows) { row in
                if row.isSeparator {
                    Rectangle().fill(Color.white.opacity(0.13)).frame(height: 1)
                        .padding(.horizontal, 10)
                        .frame(height: Self.separatorHeight)
                } else {
                    HStack(spacing: 6) {
                        Text(row.isChecked ? "\u{2713}" : "").frame(width: 14)
                        Text(row.title).lineLimit(1)
                        Spacer(minLength: 8)
                        if !row.shortcut.isEmpty { Text(row.shortcut).foregroundColor(.white.opacity(0.5)) }
                        if row.hasSubmenu { Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)) }
                    }
                    .font(.system(size: 13))
                    .foregroundColor(row.isEnabled ? .white : .white.opacity(0.42))
                    .padding(.horizontal, 8)
                    .frame(height: Self.rowHeight)
                }
            }
        }
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 10).fill(DocColors.menu.opacity(0.97)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.14), lineWidth: 1))
        .shadow(color: .black.opacity(0.45), radius: 14, y: 6)
    }
}

/// A close-up of the right side of the menu bar with the Snowpine Cue icon marked.
struct MenuBarPicture: View {
    var body: some View {
        StatusIcons()
            .padding(.horizontal, 18)
            .frame(height: 40)
            .background(LinearGradient(colors: [DocColors.desktopTop, DocColors.desktopBottom], startPoint: .top, endPoint: .bottom))
    }
}
