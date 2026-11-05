import Foundation
import Testing
@testable import EyeCueCore

@Test func normalizesCasePunctuationAndNumbers() {
    #expect(Normalizer.key("Ten,") == "10")
    #expect(Normalizer.key("10") == "10")
    #expect(Normalizer.key("Don't") == "dont")
    #expect(Normalizer.key("MP3.") == "mp3")
    #expect(Normalizer.key("&") == "")
}

@Test func similarAllowsSmallRecognizerSlips() {
    #expect(Normalizer.similar("plans", "plan"))
    #expect(Normalizer.similar("training", "trainings"))
    #expect(Normalizer.similar("password", "passwords"))
    #expect(Normalizer.similar("tuesday", "tuesdy"))
    #expect(!Normalizer.similar("the", "she"))   // three letters or fewer must match exactly
}

@Test func plainTextJoinsLinesIntoParagraphs() {
    let doc = ScriptDocument.plainText("First line\ncontinues here.\n\nSecond paragraph.", title: "t")
    #expect(doc.sections.count == 1)
    #expect(doc.sections[0].paragraphs == ["First line continues here.", "Second paragraph."])
}

@Test func markdownBecomesSectionsAndCleanText() {
    let md = """
    # Opening
    Hello **everyone**, see [the page](https://example.com).
    <!-- note to self: smile -->

    - First point
    - Second point

    ## Close
    That's it from *me*.
    """
    let doc = ScriptDocument.markdown(md, title: "t")
    #expect(doc.sections.map(\.heading) == ["Opening", "Close"])
    #expect(doc.sections[0].paragraphs == ["Hello everyone, see the page.", "First point", "Second point"])
    #expect(doc.sections[1].paragraphs == ["That's it from me."])
}

@Test func deckHTMLReadsSpeakerNotesInOrder() {
    let html = """
    <section class="slide" data-sec="Intro" data-head="Where we are" data-notes="So, quick heads up &amp; welcome. It&#39;s &quot;go&quot; time.">
      <h1>Ignored slide text</h1>
    </section>
    <section class="slide" data-head="No notes here"></section>
    <section class="slide full" data-head="Last thing" data-notes='That&rsquo;s it from me.'></section>
    """
    let doc = ScriptDocument.deckHTML(html, title: "deck")
    #expect(doc?.sections.count == 2)
    #expect(doc?.sections[0].heading == "Slide 1: Where we are")
    #expect(doc?.sections[0].paragraphs == ["So, quick heads up & welcome. It's \"go\" time."])
    #expect(doc?.sections[1].heading == "Slide 3: Last thing")
    #expect(doc?.sections[1].paragraphs == ["That\u{2019}s it from me."])
}

@Test func htmlWithoutNotesFallsBackToText() {
    let doc = ScriptDocument.parse("<html><body><p>Hello there.</p><p>Second.</p><script>x()</script></body></html>",
                                   format: .html, title: "t")
    #expect(doc.sections.first?.paragraphs == ["Hello there.", "Second."])
}

@Test func layoutWrapsAtTheWidthAndBreaksParagraphs() {
    let doc = ScriptDocument(title: "t", sections: [
        .init(heading: "Intro", paragraphs: ["aaaa bbbb cccc dddd", "eeee"]),
    ])
    let prepared = PreparedScript(doc)
    // Each letter is 10 points wide, a space is 10: "aaaa bbbb" is 90.
    let lines = prepared.layout(maxWidth: 100, spaceWidth: 10) { text, _ in Double(text.count) * 10 }
    #expect(lines.count == 4)
    #expect(lines[0].isHeading)
    #expect(lines[1].firstSpoken == 0 && lines[1].lastSpoken == 1)
    #expect(lines[2].firstSpoken == 2 && lines[2].lastSpoken == 3)
    #expect(lines[3].firstSpoken == 4)
    #expect(PreparedScript.lineIndex(forSpoken: 3, in: lines) == 2)
    #expect(PreparedScript.lineIndex(forSpoken: 99, in: lines) == 3)
}

@Test func symbolsAreShownButNotListenedFor() {
    let prepared = PreparedScript(ScriptDocument.plainText("Sales & Ops", title: "t"))
    #expect(prepared.tokens.count == 3)
    #expect(prepared.spokenKeys == ["sales", "ops"])
    #expect(prepared.tokens[1].spokenIndex == nil)
}

// MARK: Hostile input stays fast

@Test func unmatchedMarkdownOpenersParseQuickly() {
    let line = String(repeating: "[", count: 40_000) + " " + String(repeating: "*a", count: 20_000) + " " + String(repeating: "<!--", count: 10_000)
    let start = Date()
    let doc = ScriptDocument.parse(line, format: .markdown, title: "hostile")
    #expect(Date().timeIntervalSince(start) < 2)
    #expect(!doc.isEmpty)
}

@Test func unclosedHTMLParsesQuickly() {
    let html = String(repeating: "<section \"", count: 20_000) + String(repeating: "<script", count: 20_000) + String(repeating: "<", count: 40_000)
    let start = Date()
    _ = ScriptDocument.parse(html, format: .html, title: "hostile")
    #expect(Date().timeIntervalSince(start) < 2)
}

@Test func scriptAndStyleBlocksAreDropped() {
    let html = "<p>Keep this</p><SCRIPT>var x = 1;</script><style>p{}</style><span>and this</span><script>never closed"
    let text = HTMLText.strip(html)
    #expect(text.contains("Keep this"))
    #expect(text.contains("and this"))
    #expect(!text.contains("var x"))
    #expect(!text.contains("p{}"))
    #expect(!text.contains("never closed"))
}
