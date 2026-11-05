import Foundation

/// A script as sections of paragraphs. A section heading is shown on the
/// prompter as a label and is never matched against speech.
public struct ScriptDocument: Equatable {
    public struct Section: Equatable {
        public var heading: String?
        public var paragraphs: [String]

        public init(heading: String? = nil, paragraphs: [String]) {
            self.heading = heading
            self.paragraphs = paragraphs
        }
    }

    public enum Format {
        case plainText, markdown, html
    }

    public var title: String
    public var sections: [Section]

    public init(title: String, sections: [Section]) {
        self.title = title
        self.sections = sections
    }

    /// True when there is nothing to read.
    public var isEmpty: Bool {
        sections.allSatisfy { section in
            section.paragraphs.allSatisfy { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        }
    }

    public static func format(forExtension ext: String) -> Format {
        switch ext.lowercased() {
        case "md", "markdown", "mdown", "mkd": return .markdown
        case "html", "htm": return .html
        default: return .plainText
        }
    }

    public static func parse(_ text: String, format: Format, title: String) -> ScriptDocument {
        switch format {
        case .plainText: return plainText(text, title: title)
        case .markdown: return markdown(text, title: title)
        case .html: return deckHTML(text, title: title) ?? plainText(HTMLText.strip(text), title: title)
        }
    }

    /// Blank lines separate paragraphs; the lines inside a paragraph are joined.
    public static func plainText(_ text: String, title: String) -> ScriptDocument {
        ScriptDocument(title: title, sections: [Section(paragraphs: paragraphs(in: text))])
    }

    /// Every non-empty line is its own paragraph. Used for Word and RTF files,
    /// where paragraphs come through as single line breaks.
    public static func linePerParagraph(_ text: String, title: String) -> ScriptDocument {
        let lines = splitLines(text)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return ScriptDocument(title: title, sections: [Section(paragraphs: lines)])
    }

    /// Headings (#) start sections; list items become their own paragraphs;
    /// emphasis, code marks, links and images are reduced to their text.
    public static func markdown(_ text: String, title: String) -> ScriptDocument {
        var sections: [Section] = []
        var heading: String?
        var paragraphs: [String] = []
        var current: [String] = []
        var inComment = false

        func flushParagraph() {
            if !current.isEmpty {
                paragraphs.append(current.joined(separator: " "))
                current = []
            }
        }
        func flushSection() {
            flushParagraph()
            if heading != nil || !paragraphs.isEmpty {
                sections.append(Section(heading: heading, paragraphs: paragraphs))
            }
            paragraphs = []
        }

        for raw in splitLines(text) {
            var line = raw.trimmingCharacters(in: .whitespaces)

            // HTML comments are notes to self, not lines to read.
            if inComment {
                guard let end = line.range(of: "-->") else { continue }
                line = String(line[end.upperBound...]).trimmingCharacters(in: .whitespaces)
                inComment = false
            }
            line = Patterns.inlineComment.replace(in: line, with: "")
            if let start = line.range(of: "<!--") {
                line = String(line[..<start.lowerBound]).trimmingCharacters(in: .whitespaces)
                inComment = true
            }

            if line.isEmpty || Patterns.rule.matches(line) {
                flushParagraph()
                continue
            }
            if line.hasPrefix("#") {
                flushSection()
                let text = String(line.drop(while: { $0 == "#" })).trimmingCharacters(in: .whitespaces)
                heading = cleanInline(text)
                continue
            }
            if let item = Patterns.listItem.firstGroup(in: line) {
                flushParagraph()
                current.append(cleanInline(item))
                flushParagraph()
                continue
            }
            current.append(cleanInline(line))
        }
        flushSection()
        return ScriptDocument(title: title, sections: sections)
    }

    /// Reads speaker notes from a slide deck: every `<section>` with a `data-notes`
    /// attribute becomes a section, headed by its `data-head` when present.
    /// Returns nil when the file has no notes, so callers can fall back to plain text.
    public static func deckHTML(_ html: String, title: String) -> ScriptDocument? {
        var sections: [Section] = []
        var slideNumber = 0
        for tag in Patterns.sectionTag.allMatches(in: html) {
            let isSlide = (Patterns.attribute("class", in: tag) ?? "").contains("slide")
            let notes = Patterns.attribute("data-notes", in: tag)
            guard isSlide || notes != nil else { continue }
            slideNumber += 1
            guard let notes else { continue }
            let head = HTMLText.decodeEntities(Patterns.attribute("data-head", in: tag) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let label = head.isEmpty ? "Slide \(slideNumber)" : "Slide \(slideNumber): \(head)"
            sections.append(Section(heading: label, paragraphs: paragraphs(in: HTMLText.decodeEntities(notes))))
        }
        return sections.isEmpty ? nil : ScriptDocument(title: title, sections: sections)
    }

    // MARK: Helpers

    static func splitLines(_ text: String) -> [String] {
        text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
    }

    static func paragraphs(in text: String) -> [String] {
        var out: [String] = []
        var current: [String] = []
        for raw in splitLines(text) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty {
                if !current.isEmpty { out.append(current.joined(separator: " ")); current = [] }
            } else {
                current.append(line)
            }
        }
        if !current.isEmpty { out.append(current.joined(separator: " ")) }
        return out
    }

    static func cleanInline(_ text: String) -> String {
        var s = text
        if s.hasPrefix(">") { s = String(s.drop(while: { $0 == ">" || $0 == " " })) }
        s = Patterns.image.replace(in: s, with: "")
        s = Patterns.link.replace(in: s, with: "$1")
        for mark in ["**", "__", "`"] { s = s.replacingOccurrences(of: mark, with: "") }
        s = Patterns.singleStar.replace(in: s, with: "$1")
        return s.trimmingCharacters(in: .whitespaces)
    }
}

/// Small wrapper so the parsers read clearly and compile without regex literals.
struct Pattern {
    let regex: NSRegularExpression

    init(_ pattern: String, options: NSRegularExpression.Options = []) {
        // Patterns are constants in this file; a bad one is a programming error.
        regex = try! NSRegularExpression(pattern: pattern, options: options)
    }

    private func range(_ s: String) -> NSRange { NSRange(s.startIndex..<s.endIndex, in: s) }

    func matches(_ s: String) -> Bool { regex.firstMatch(in: s, range: range(s)) != nil }

    func replace(in s: String, with template: String) -> String {
        regex.stringByReplacingMatches(in: s, range: range(s), withTemplate: template)
    }

    func firstGroup(in s: String) -> String? {
        guard let m = regex.firstMatch(in: s, range: range(s)) else { return nil }
        for i in 1..<max(m.numberOfRanges, 1) {
            if let r = Range(m.range(at: i), in: s) { return String(s[r]) }
        }
        return nil
    }

    func allMatches(in s: String) -> [String] {
        regex.matches(in: s, range: range(s)).compactMap { Range($0.range, in: s).map { String(s[$0]) } }
    }
}

enum Patterns {
    static let listItem = Pattern(#"^(?:[-*+]|\d+[.)])\s+(.*)$"#)
    static let rule = Pattern(#"^(?:-{3,}|\*{3,}|_{3,})$"#)
    // Patterns that scan forward stop at the next opening character (or a length cap), so a long
    // run of unmatched openers in a hostile file costs linear time, not a rescan from every one.
    static let inlineComment = Pattern(#"<!--(?:[^<]{0,2000}?)-->"#)
    static let image = Pattern(#"!\[[^\[\]\n]*\]\([^()\n]*\)"#)
    static let link = Pattern(#"\[([^\[\]\n]+)\]\([^()\n]*\)"#)
    static let singleStar = Pattern(#"\*([^*\s][^*\n]*)\*"#)
    // A <section ...> opening tag, allowing ">" inside quoted attribute values.
    static let sectionTag = Pattern(#"<section\b(?:[^<>"']|"[^"<]*"|'[^'<]*')*>"#, options: [.caseInsensitive])

    static func attribute(_ name: String, in tag: String) -> String? {
        let escaped = NSRegularExpression.escapedPattern(for: name)
        return Pattern(#"\s"# + escaped + #"\s*=\s*(?:"([^"]*)"|'([^']*)')"#, options: [.caseInsensitive])
            .firstGroup(in: tag)
    }
}

enum HTMLText {
    static let named: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": " ",
        "rsquo": "\u{2019}", "lsquo": "\u{2018}", "rdquo": "\u{201D}", "ldquo": "\u{201C}",
        "ndash": "\u{2013}", "mdash": "\u{2014}", "hellip": "\u{2026}", "middot": "\u{00B7}",
        "rarr": "\u{2192}", "larr": "\u{2190}", "times": "\u{00D7}", "copy": "\u{00A9}",
        "reg": "\u{00AE}", "trade": "\u{2122}", "deg": "\u{00B0}", "bull": "\u{2022}",
    ]
    static let entity = Pattern(#"&(#[xX][0-9a-fA-F]+|#[0-9]+|[a-zA-Z]+);"#)

    static func decodeEntities(_ s: String) -> String {
        guard s.contains("&") else { return s }
        let ns = s as NSString
        var out = ""
        var last = 0
        for m in entity.regex.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
            out += ns.substring(with: NSRange(location: last, length: m.range.location - last))
            let body = ns.substring(with: m.range(at: 1))
            out += decode(body) ?? ns.substring(with: m.range)
            last = m.range.location + m.range.length
        }
        out += ns.substring(from: last)
        return out
    }

    private static func decode(_ body: String) -> String? {
        if body.hasPrefix("#x") || body.hasPrefix("#X") {
            return UInt32(body.dropFirst(2), radix: 16).flatMap(Unicode.Scalar.init).map { String(Character($0)) }
        }
        if body.hasPrefix("#") {
            return UInt32(body.dropFirst(1)).flatMap(Unicode.Scalar.init).map { String(Character($0)) }
        }
        return named[body.lowercased()]
    }

    static let breaks = Pattern(#"<br\s*/?>|</(?:p|div|li|h[1-6]|section|tr|blockquote)>"#, options: [.caseInsensitive])
    static let tags = Pattern(#"<[^<>]+>"#)

    /// Plain text from arbitrary HTML, keeping paragraph breaks.
    static func strip(_ html: String) -> String {
        var s = dropBlocks(html)
        s = breaks.replace(in: s, with: "\n\n")
        s = tags.replace(in: s, with: "")
        return decodeEntities(s)
    }

    /// Removes `<script>` and `<style>` blocks in one forward pass. An unclosed block drops the rest.
    static func dropBlocks(_ html: String) -> String {
        var out = ""
        var rest = html[...]
        while let open = rest.range(of: "<s", options: .caseInsensitive) {
            let after = rest[open.upperBound...]
            let head = after.prefix(5).lowercased()
            let name = ["cript", "tyle"].first { head.hasPrefix($0) }
            guard let name, let end = after.range(of: "</s" + name, options: .caseInsensitive) else {
                if name != nil { return out + rest[..<open.lowerBound] }
                out += rest[..<open.upperBound]
                rest = after
                continue
            }
            out += rest[..<open.lowerBound]
            rest = after[end.upperBound...]
            if let close = rest.firstIndex(of: ">") { rest = rest[rest.index(after: close)...] }
        }
        return out + rest
    }
}
