import Foundation

/// Keeps your place in the script from live speech recognition.
///
/// The recognizer reports the whole utterance so far, again and again, as it
/// refines it. The tracker only looks at the last few words heard and lines
/// them up with the script near the current position. A match needs several
/// words in order, so one misheard, extra or dropped word does not stop it and
/// stray talk ("hang on, let me share my screen") does not move it.
public struct VoiceTracker {
    public let keys: [String]
    /// Index of the next word the speaker is expected to say.
    public private(set) var position: Int

    /// How far back and ahead of the position a match may land.
    public var lookBack = 8
    public var lookAhead = 40
    /// Jumps longer than this need every heard word to match.
    public var bigJump = 12

    public init(keys: [String], position: Int = 0) {
        self.keys = keys
        self.position = min(max(0, position), keys.count)
    }

    public mutating func reset(to newPosition: Int = 0) {
        position = min(max(0, newPosition), keys.count)
    }

    /// Feed the recognizer's current transcript. Returns true when the position moved.
    @discardableResult
    public mutating func update(transcript: String) -> Bool {
        update(heard: Normalizer.keys(in: transcript))
    }

    @discardableResult
    public mutating func update(heard: [String]) -> Bool {
        guard !heard.isEmpty, !keys.isEmpty else { return false }
        let tail = Array(heard.suffix(5))
        let k = tail.count
        let low = max(0, position - lookBack)
        let high = min(keys.count - 1, position + lookAhead)
        guard low <= high else { return false }

        var best: (end: Int, score: Int, cost: Int)?
        for end in low...high {
            var straight = 0
            for j in 0..<k {
                let index = end - (k - 1 - j)
                if index >= 0, Normalizer.similar(tail[j], keys[index]) { straight += 1 }
            }
            let lastMatches = Normalizer.similar(tail[k - 1], keys[end])
            // When the newest word lands here, allow for a word the recognizer added or dropped.
            let score = lastMatches ? max(straight, inOrderMatches(tail, endingAt: end)) : straight
            let jump = end - position  // 0 means the next expected word
            guard accept(score: score, straight: straight, count: k, lastMatches: lastMatches, jump: jump) else { continue }
            let cost = jump >= 0 ? jump : -jump * 2  // prefer moving forward
            if let current = best, score < current.score || (score == current.score && cost >= current.cost) {
                continue
            }
            best = (end, score, cost)
        }

        guard let match = best else { return false }
        let newPosition = match.end + 1
        guard newPosition != position else { return false }
        position = newPosition
        return true
    }

    /// How many heard words appear in order in the script words ending at `end`, gaps allowed.
    private func inOrderMatches(_ tail: [String], endingAt end: Int) -> Int {
        let window = Array(keys[max(0, end - tail.count - 1)...end])
        var previous = [Int](repeating: 0, count: window.count + 1)
        for word in tail {
            var current = [Int](repeating: 0, count: window.count + 1)
            for j in window.indices {
                current[j + 1] = Normalizer.similar(word, window[j])
                    ? previous[j] + 1
                    : max(previous[j + 1], current[j])
            }
            previous = current
        }
        return previous[window.count]
    }

    private func accept(score: Int, straight: Int, count k: Int, lastMatches: Bool, jump: Int) -> Bool {
        switch k {
        case 1:
            // A lone word only nudges the position forward by a word or two.
            return lastMatches && (0...1).contains(jump)
        case 2:
            return lastMatches && score == 2 && (-1...5).contains(jump)
        default:
            let needed = k == 3 ? 2 : k - 1
            guard score >= needed else { return false }
            // The newest word may still be misheard; allow it only when the rest agree.
            guard lastMatches || (k >= 4 && score == k - 1) else { return false }
            // A long jump must be word for word, gaps not allowed.
            if jump > bigJump || jump < -3 { return k >= 4 && straight == k }
            return true
        }
    }
}
