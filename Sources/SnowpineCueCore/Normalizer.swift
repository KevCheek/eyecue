import Foundation

/// Turns words into comparison keys, so the script and what the recognizer heard
/// can be matched despite case, punctuation and how numbers are written.
public enum Normalizer {
    static let numberWords: [String: String] = [
        "zero": "0", "one": "1", "two": "2", "three": "3", "four": "4",
        "five": "5", "six": "6", "seven": "7", "eight": "8", "nine": "9",
        "ten": "10", "eleven": "11", "twelve": "12", "thirteen": "13",
        "fourteen": "14", "fifteen": "15", "sixteen": "16", "seventeen": "17",
        "eighteen": "18", "nineteen": "19", "twenty": "20", "thirty": "30",
        "forty": "40", "fifty": "50", "sixty": "60", "seventy": "70",
        "eighty": "80", "ninety": "90", "hundred": "100",
        "first": "1st", "second": "2nd", "third": "3rd",
    ]

    /// Lowercase letters and digits only, with spelled-out numbers mapped to digits.
    /// Returns an empty string for tokens with nothing to say ("&", "--").
    public static func key(_ raw: String) -> String {
        let folded = raw.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                                 locale: Locale(identifier: "en_US_POSIX"))
        var scalars = String.UnicodeScalarView()
        for scalar in folded.unicodeScalars where CharacterSet.alphanumerics.contains(scalar) {
            scalars.append(scalar)
        }
        let key = String(scalars).lowercased()
        return numberWords[key] ?? key
    }

    /// Keys for every word in a transcript, empty ones dropped.
    public static func keys(in text: String) -> [String] {
        text.split(whereSeparator: { $0.isWhitespace })
            .map { key(String($0)) }
            .filter { !$0.isEmpty }
    }

    /// Loose equality for recognizer output: exact, a shared stem ("plan"/"plans"),
    /// or one or two letters off for longer words.
    public static func similar(_ a: String, _ b: String) -> Bool {
        if a == b { return true }
        let ca = Array(a), cb = Array(b)
        let longer = max(ca.count, cb.count), shorter = min(ca.count, cb.count)
        if shorter >= 4, longer - shorter <= 3, a.hasPrefix(b) || b.hasPrefix(a) { return true }
        let allowed = longer >= 8 ? 2 : (longer >= 4 ? 1 : 0)
        guard allowed > 0, longer - shorter <= allowed else { return false }
        return editDistance(ca, cb) <= allowed
    }

    static func editDistance(_ a: [Character], _ b: [Character]) -> Int {
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var previous = Array(0...b.count)
        var current = [Int](repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            current[0] = i
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost)
            }
            swap(&previous, &current)
        }
        return previous[b.count]
    }
}
