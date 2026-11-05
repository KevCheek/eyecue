import AppKit
import SnowpineCueCore
import SwiftUI

/// `SnowpineCue --smoke-test <folder>`: builds the model and view without showing
/// anything or touching the microphone, checks that simulated speech moves the
/// prompter, and renders the strip to prompter.png for a visual check.
enum SmokeTest {
    @MainActor
    static func run(outputDirectory: String) -> Int32 {
        guard BrandFonts.allLoaded else { return fail("the brand fonts did not load") }
        let suite = "snowpine-cue.smoke-test"
        UserDefaults().removePersistentDomain(forName: suite)
        guard let defaults = UserDefaults(suiteName: suite) else { return fail("no defaults") }
        let settings = Settings(defaults: defaults)
        let model = PrompterModel(settings: settings, document: WelcomeScript.document)

        let words = model.tokens.filter { $0.spokenIndex != nil }.prefix(22).map(\.text)
        var heard: [String] = []
        for word in words {
            heard.append(word)
            model.applyTranscript(heard.joined(separator: " "))
        }
        guard model.position == words.count else {
            return fail("position \(model.position), expected \(words.count)")
        }

        let band: CGFloat = 38
        let height = band + CGFloat(settings.visibleLines) * settings.lineHeight + 14
        let view = PrompterView(model: model, settings: settings, topBand: band)
            .frame(width: CGFloat(settings.panelWidth), height: height)
            .padding(.horizontal, 40)
            .padding(.bottom, 30)
            .background(Color(white: 0.2))
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else {
            return fail("could not render the prompter")
        }
        let folder = URL(fileURLWithPath: outputDirectory)
        let file = folder.appendingPathComponent("prompter.png")
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try png.write(to: file)
        } catch {
            return fail("could not write \(file.path): \(error.localizedDescription)")
        }
        print("SMOKE OK position=\(model.position)/\(model.spokenCount) line=\(model.currentLine)/\(model.lines.count) image=\(file.path)")
        return 0
    }

    private static func fail(_ message: String) -> Int32 {
        FileHandle.standardError.write(Data("SMOKE FAIL: \(message)\n".utf8))
        return 1
    }
}
