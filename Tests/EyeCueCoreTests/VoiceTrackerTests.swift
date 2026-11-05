import Testing
@testable import EyeCueCore

private func keys(_ script: String) -> [String] { Normalizer.keys(in: script) }

/// Feeds a transcript the way the recognizer does: the whole utterance so far, one word longer each time.
private func speak(_ words: [String], into tracker: inout VoiceTracker, heardSoFar: inout [String]) {
    for word in words {
        heardSoFar.append(word)
        tracker.update(transcript: heardSoFar.joined(separator: " "))
    }
}

private let update = """
So quick update on the new system. We go live on Tuesday and the team has been \
training all week. If you have not logged in yet please do that today so we can \
fix any password problems before then. That's it from me.
"""

@Test func followsAStraightRead() {
    var tracker = VoiceTracker(keys: keys(update))
    var heard: [String] = []
    speak(update.split(separator: " ").map(String.init), into: &tracker, heardSoFar: &heard)
    #expect(tracker.position == tracker.keys.count)
}

@Test func keepsGoingThroughAMisheardWord() {
    var tracker = VoiceTracker(keys: keys(update))
    var heard: [String] = []
    var words = update.split(separator: " ").map(String.init)
    words[6] = "sister"   // "system." misheard
    words[20] = "Ted"     // "not" misheard
    speak(words, into: &tracker, heardSoFar: &heard)
    #expect(tracker.position == tracker.keys.count)
}

@Test func ignoresUnrelatedTalk() {
    var tracker = VoiceTracker(keys: keys(update))
    tracker.update(transcript: "hang on a sec while I share my screen okay can everyone see it")
    #expect(tracker.position == 0)
}

@Test func catchesUpWhenTheSpeakerSkipsASentence() {
    var tracker = VoiceTracker(keys: keys(update))
    var heard: [String] = []
    speak(["So", "quick", "update", "on", "the", "new", "system."], into: &tracker, heardSoFar: &heard)
    #expect(tracker.position == 7)
    // Skips "We go live on Tuesday and the team has been training all week."
    speak(["If", "you", "have", "not", "logged", "in", "yet"], into: &tracker, heardSoFar: &heard)
    let expected = keys("So quick update on the new system We go live on Tuesday and the team has been training all week If you have not logged in yet").count
    #expect(tracker.position == expected)
}

@Test func doesNotJumpToARepeatedPhraseFarAhead() {
    let filler = Array(repeating: "and then we will review the numbers in detail", count: 6).joined(separator: " ")
    let script = "thank you all for joining " + filler + " thank you all for joining again"
    var tracker = VoiceTracker(keys: keys(script))
    var heard: [String] = []
    speak(["thank", "you", "all", "for", "joining"], into: &tracker, heardSoFar: &heard)
    #expect(tracker.position == 5)
}

@Test func matchesNumbersWrittenEitherWay() {
    var tracker = VoiceTracker(keys: keys("We have 14 aircraft switching over on day one"))
    tracker.update(transcript: "we have fourteen aircraft switching")
    #expect(tracker.position == 5)
}

@Test func resetMovesBackToStart() {
    var tracker = VoiceTracker(keys: keys(update))
    tracker.update(transcript: "so quick update on the new system")
    tracker.reset()
    #expect(tracker.position == 0)
}
