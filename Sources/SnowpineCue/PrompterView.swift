import AppKit
import SnowpineCueCore
import SwiftUI

/// Snowpine Code brand 2.0: pure black, white, neutral greys and Pine Blue.
enum Palette {
    static let ground = Color.black                                     // #000000, blends with the notch
    static let paper = Color.white                                      // words still to say
    static let silver = Color(red: 166 / 255, green: 166 / 255, blue: 166 / 255)  // #A6A6A6
    static let spoken = silver.opacity(0.5)
    static let next = Color(red: 0, green: 163 / 255, blue: 224 / 255)  // #00A3E0 Pine Blue: the next word
    static let heading = silver
    static let quiet = silver
    static let live = next
}

/// The strip under the camera. The top band sits behind the notch; the
/// script scrolls a line at a time below it, with the current line second
/// from the top so the line just read stays in view.
struct PrompterView: View {
    @ObservedObject var model: PrompterModel
    @ObservedObject var settings: Settings
    /// Height of the band that sits beside and behind the notch.
    var topBand: CGFloat

    var body: some View {
        let lineHeight = settings.lineHeight
        ZStack(alignment: .top) {
            UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 20,
                                   bottomTrailingRadius: 20, topTrailingRadius: 0, style: .continuous)
                .fill(Palette.ground)
            VStack(spacing: 0) {
                header.frame(height: topBand)
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(model.lines.enumerated()), id: \.offset) { index, line in
                        row(line, index: index)
                            .frame(width: settings.textWidth, height: lineHeight, alignment: .leading)
                    }
                }
                .offset(y: -CGFloat(max(0, model.currentLine - 1)) * lineHeight)
                .animation(.easeOut(duration: 0.22), value: model.currentLine)
                .frame(width: settings.textWidth, height: CGFloat(settings.visibleLines) * lineHeight, alignment: .topLeading)
                .clipped()
                Spacer(minLength: 0)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Circle().fill(dotColor).frame(width: 7, height: 7)
            Text(model.statusText)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(Palette.quiet)
            Spacer()
            Text(model.progressText)
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundColor(Palette.quiet)
            // Opens the menu. PrompterHostingView handles the click.
            Image(systemName: "ellipsis.circle.fill")
                .font(.system(size: 15))
                .foregroundColor(Palette.paper)
                .accessibilityLabel("Menu")
        }
        .padding(.horizontal, 18)
    }

    private var dotColor: Color {
        switch model.mode {
        case .listening: return Palette.live
        case .startingMic, .scrolling: return Palette.paper
        case .paused, .finished: return Palette.quiet.opacity(0.5)
        }
    }

    @ViewBuilder
    private func row(_ line: LaidOutLine, index: Int) -> some View {
        if line.isHeading {
            Text(model.tokens[line.tokens.lowerBound].text.uppercased())
                .font(Font(settings.headingFont as CTFont))
                .tracking(1.1)
                .foregroundColor(Palette.heading)
                .lineLimit(1)
        } else {
            Text(attributed(line))
                .font(Font(settings.bodyFont as CTFont))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .opacity(index < model.currentLine ? 0.6 : 1)
        }
    }

    private func attributed(_ line: LaidOutLine) -> AttributedString {
        var out = AttributedString()
        for i in line.tokens {
            let token = model.tokens[i]
            if i > line.tokens.lowerBound { out.append(AttributedString(" ")) }
            var piece = AttributedString(token.text)
            piece[AttributeScopes.SwiftUIAttributes.ForegroundColorAttribute.self] = color(for: token)
            out.append(piece)
        }
        return out
    }

    private func color(for token: DisplayToken) -> Color {
        guard let spoken = token.spokenIndex else { return Palette.quiet }
        if spoken < model.position { return Palette.spoken }
        if spoken == model.position { return Palette.next }
        return Palette.paper
    }
}
