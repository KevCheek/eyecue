import AppKit
import EyeCueCore

/// Reads a script file into a ScriptDocument.
enum ScriptLoader {
    enum LoadError: LocalizedError {
        case empty
        case tooLarge
        case tooLong
        var errorDescription: String? {
            switch self {
            case .empty: return "That file has no text EyeCue can read."
            case .tooLarge: return "That file is over 20 MB, which is far more than a script needs."
            case .tooLong: return "That script is over \(ScriptLoader.maxCharacters / 1000),000 characters, far more than a talk needs. Split it into shorter files."
            }
        }
    }

    /// Generous limits: an hour-long talk is about 60,000 characters.
    static let maxFileBytes = 20_000_000
    static let maxCharacters = 300_000

    /// The system importer for each rich format, set explicitly so a file can't pick a different
    /// importer (for example HTML renamed to .doc) by what it contains.
    private static let richTypes: [String: NSAttributedString.DocumentType] = [
        "docx": .officeOpenXML, "doc": .docFormat, "rtf": .rtf, "rtfd": .rtfd, "odt": .openDocument,
    ]

    /// Text, Markdown and deck HTML are parsed directly; Word, RTF and OpenDocument
    /// go through the system text importer.
    static func load(_ url: URL) throws -> ScriptDocument {
        let ext = url.pathExtension.lowercased()
        let title = url.deletingPathExtension().lastPathComponent
        let size = try url.resourceValues(forKeys: [.totalFileSizeKey, .fileSizeKey])
        if (size.totalFileSize ?? size.fileSize ?? 0) > maxFileBytes { throw LoadError.tooLarge }

        let document: ScriptDocument
        if let type = richTypes[ext] {
            let text = try NSAttributedString(url: url, options: [.documentType: type], documentAttributes: nil).string
            try checkLength(text)
            document = ScriptDocument.linePerParagraph(text, title: title)
        } else {
            let text = try readText(url)
            let format = ScriptDocument.format(forExtension: ext)
            // Deck HTML carries markup and styles around the notes, so only plain text is length-checked up front.
            if format != .html { try checkLength(text) }
            document = ScriptDocument.parse(text, format: format, title: title)
        }
        guard !document.isEmpty else { throw LoadError.empty }
        try checkLength(document.sections.flatMap(\.paragraphs).joined(separator: " "))
        return document
    }

    static func checkLength(_ text: String) throws {
        if text.utf16.count > maxCharacters { throw LoadError.tooLong }
    }

    private static func readText(_ url: URL) throws -> String {
        if let text = try? String(contentsOf: url, encoding: .utf8) { return text }
        var encoding = String.Encoding.utf8
        return try String(contentsOf: url, usedEncoding: &encoding)
    }
}

enum WelcomeScript {
    static let document = ScriptDocument(title: "Welcome", sections: [
        .init(heading: "Welcome to EyeCue", paragraphs: [
            "This strip sits right under your camera, so you can read your script and still look at the people you are talking to.",
            "Press Control Option P to start, or click the strip. With Follow My Voice on, EyeCue listens on this Mac and moves along as you speak. Nothing you say leaves your Mac.",
            "To open a script, change settings or quit, click the EyeCue icon in the menu bar, a small notch with three lines under it. You can also right-click this strip for the same menu.",
            "Control Option Down and Up move a line, Control Option R goes back to the start, and Control Option H hides the strip.",
            "The strip is hidden from screen sharing. Do one quick test share before a big call.",
        ]),
    ])
}
