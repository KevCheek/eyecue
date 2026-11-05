import AppKit
import EyeCueCore
import SwiftUI

enum Palette {
    static let ground = Color(red: 0.043, green: 0.047, blue: 0.055)   // near black, blends with the notch
    static let paper = Color(red: 0.969, green: 0.973, blue: 0.976)    // words still to say
    static let spoken = Color(red: 0.635, green: 0.663, blue: 0.682).opacity(0.5)
    static let next = Color(red: 0.863, green: 0.761, blue: 0.698)     // sand: the next word
    static let heading = Color(red: 0.690, green: 0.553, blue: 0.533)  // mauve section labels
    static let quiet = Color(red: 0.635, green: 0.663, blue: 0.682)
    static let live = Color(red: 0.42, green: 0.80, blue: 0.55)
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
        }
        .padding(.horizontal, 18)
    }

    private var dotColor: Color {
        switch model.mode {
        case .listening: return Palette.live
        case .startingMic, .scrolling: return Palette.next
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
