import Foundation

/// One word or heading as shown on the prompter.
public struct DisplayToken: Equatable {
    public enum Kind: Equatable {
        /// A word. `spoken` is its index among the words the tracker listens for,
        /// or nil for symbols with nothing to say ("&", "--").
        case word(spoken: Int?)
        case heading
    }

    public let text: String
    public let kind: Kind

    public init(text: String, kind: Kind) {
        self.text = text
        self.kind = kind
    }

    public var spokenIndex: Int? {
        if case .word(let spoken) = kind { return spoken }
        return nil
    }

    public var isHeading: Bool { kind == .heading }
}

/// A row on the prompter: a run of tokens that fits the strip's width.
public struct LaidOutLine: Equatable {
    public let tokens: Range<Int>
    public let isHeading: Bool
    public let firstSpoken: Int?
    public let lastSpoken: Int?
}

/// A script broken into display tokens and the keys the tracker matches against.
public struct PreparedScript {
    public let tokens: [DisplayToken]
    public let spokenKeys: [String]
    /// Token indices that start a paragraph, so the layout breaks the line there.
    let paragraphStarts: Set<Int>

    public init(_ document: ScriptDocument) {
        var tokens: [DisplayToken] = []
        var keys: [String] = []
        var starts = Set<Int>()
        for section in document.sections {
            if let heading = section.heading?.trimmingCharacters(in: .whitespacesAndNewlines), !heading.isEmpty {
                tokens.append(DisplayToken(text: heading, kind: .heading))
            }
            for paragraph in section.paragraphs {
                let words = paragraph.split(whereSeparator: { $0.isWhitespace })
                guard !words.isEmpty else { continue }
                starts.insert(tokens.count)
                for word in words {
                    let key = Normalizer.key(String(word))
                    if key.isEmpty {
                        tokens.append(DisplayToken(text: String(word), kind: .word(spoken: nil)))
                    } else {
                        tokens.append(DisplayToken(text: String(word), kind: .word(spoken: keys.count)))
                        keys.append(key)
                    }
                }
            }
        }
        self.tokens = tokens
        self.spokenKeys = keys
        self.paragraphStarts = starts
    }

    public var spokenCount: Int { spokenKeys.count }

    /// Names, acronyms and words with digits, passed to the recognizer as hints.
    public var contextualStrings: [String] {
        var seen = Set<String>()
        var out: [String] = []
        for token in tokens where token.spokenIndex != nil {
            let word = token.text.trimmingCharacters(in: .punctuationCharacters)
            guard word.count >= 3, !seen.contains(word) else { continue }
            let hasDigit = word.rangeOfCharacter(from: .decimalDigits) != nil
            let capitalized = word.first?.isUppercase ?? false
            if hasDigit || capitalized {
                seen.insert(word)
                out.append(word)
                if out.count >= 100 { break }
            }
        }
        return out
    }

    /// Greedy word wrap. `measure` returns the width of a token's text;
    /// its Bool argument is true for headings. Headings get a line of their own.
    public func layout(maxWidth: Double, spaceWidth: Double, measure: (String, Bool) -> Double) -> [LaidOutLine] {
        var lines: [LaidOutLine] = []
        var start = 0
        var width = 0.0

        func close(upTo end: Int) {
            guard end > start else { return }
            let spoken = tokens[start..<end].compactMap { $0.spokenIndex }
            lines.append(LaidOutLine(tokens: start..<end, isHeading: false,
                                     firstSpoken: spoken.first, lastSpoken: spoken.last))
        }

        for (i, token) in tokens.enumerated() {
            if token.isHeading {
                close(upTo: i)
                lines.append(LaidOutLine(tokens: i..<(i + 1), isHeading: true, firstSpoken: nil, lastSpoken: nil))
                start = i + 1
                width = 0
                continue
            }
            let w = measure(token.text, false)
            if i == start {
                width = w
            } else if paragraphStarts.contains(i) || width + spaceWidth + w > maxWidth {
                close(upTo: i)
                start = i
                width = w
            } else {
                width += spaceWidth + w
            }
        }
        close(upTo: tokens.count)
        return lines
    }

    /// The line that holds spoken word `index` (or the last line once the script is done).
    public static func lineIndex(forSpoken index: Int, in lines: [LaidOutLine]) -> Int {
        guard !lines.isEmpty else { return 0 }
        for (i, line) in lines.enumerated() {
            if let last = line.lastSpoken, index <= last { return i }
        }
        return lines.count - 1
    }
}
