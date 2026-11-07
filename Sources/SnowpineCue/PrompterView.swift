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
            shape.fill(Palette.ground)
            shape.strokeBorder(Color.white.opacity(settings.floating ? 0.14 : 0), lineWidth: 1)
            grip
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

    /// The strip hangs from the top of the screen, so only its bottom corners are round.
    private var shape: UnevenRoundedRectangle {
        let top: CGFloat = settings.floating ? 16 : 0
        let bottom: CGFloat = settings.floating ? 16 : 20
        return UnevenRoundedRectangle(topLeadingRadius: top, bottomLeadingRadius: bottom,
                                      bottomTrailingRadius: bottom, topTrailingRadius: top, style: .continuous)
    }

    /// A hint that the edges can be dragged: a short bar under the strip, or ridges in the
    /// floating window's bottom right corner.
    private var grip: some View {
        Canvas { context, size in
            let color = GraphicsContext.Shading.color(Palette.quiet.opacity(0.4))
            if settings.floating {
                for step in 0..<3 {
                    let inset = CGFloat(step) * 4.5
                    var path = Path()
                    path.move(to: CGPoint(x: size.width - 7 - inset, y: size.height - 4))
                    path.addLine(to: CGPoint(x: size.width - 4, y: size.height - 7 - inset))
                    context.stroke(path, with: color, style: StrokeStyle(lineWidth: 1.3, lineCap: .round))
                }
            } else {
                let bar = CGRect(x: size.width / 2 - 16, y: size.height - 7, width: 32, height: 3.5)
                context.fill(Path(roundedRect: bar, cornerRadius: 1.75), with: color)
            }
        }
        .allowsHitTesting(false)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Circle().fill(dotColor).frame(width: 7, height: 7)
            Text(model.statusText)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(Palette.quiet)
                .lineLimit(1)
            Spacer()
            if !settings.followVoice {
                // The manual scroll speed, so it can be set without opening the menu.
                Text("\(Int(settings.wordsPerMinute)) wpm")
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundColor(Palette.quiet)
                    .padding(.trailing, 4)
            }
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
