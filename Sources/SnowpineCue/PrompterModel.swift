import AppKit
import SnowpineCueCore

/// The script, where the speaker is in it, and whether the prompter is moving.
final class PrompterModel: ObservableObject {
    enum Mode {
        case paused, startingMic, listening, scrolling, finished
    }

    @Published private(set) var tokens: [DisplayToken] = []
    @Published private(set) var lines: [LaidOutLine] = []
    /// Index of the next word to say.
    @Published private(set) var position = 0
    @Published private(set) var currentLine = 0
    @Published private(set) var mode: Mode = .paused
    @Published private(set) var title = ""

    let settings: Settings
    let speech = SpeechFollower()
    private(set) var sourceURL: URL?
    private var script: PreparedScript
    private var tracker: VoiceTracker
    private var timer: Timer?

    /// Shown to the user when something needs their attention (permissions, no on-device speech).
    var onProblem: ((String) -> Void)?

    init(settings: Settings, document: ScriptDocument) {
        self.settings = settings
        script = PreparedScript(document)
        tracker = VoiceTracker(keys: script.spokenKeys)
        tokens = script.tokens
        title = document.title
        speech.onTranscript = { [weak self] text in self?.heard(text) }
        speech.onStateChange = { [weak self] state in self?.speechChanged(state) }
        relayout()
    }

    var spokenCount: Int { script.spokenCount }
    var isRunning: Bool { mode == .startingMic || mode == .listening || mode == .scrolling }

    var statusText: String {
        switch mode {
        case .paused: return "Paused"
        case .startingMic: return "Starting mic"
        case .listening: return "Listening"
        case .scrolling: return "Scrolling"
        case .finished: return "End of script"
        }
    }

    var progressText: String {
        guard spokenCount > 0 else { return "" }
        return "\(Int((Double(position) / Double(spokenCount) * 100).rounded()))%"
    }

    // MARK: Script

    func load(_ document: ScriptDocument, from url: URL?) {
        pause()
        script = PreparedScript(document)
        tracker = VoiceTracker(keys: script.spokenKeys)
        tokens = script.tokens
        title = document.title
        sourceURL = url
        mode = .paused
        relayout()
        setPosition(0)
    }

    func relayout() {
        let body = settings.bodyFont
        let heading = settings.headingFont
        lines = script.layout(maxWidth: Double(settings.textWidth) - 4,
                              spaceWidth: Self.width(" ", font: body)) { text, isHeading in
            Self.width(text, font: isHeading ? heading : body)
        }
        currentLine = PreparedScript.lineIndex(forSpoken: position, in: lines)
    }

    static func width(_ text: String, font: NSFont) -> Double {
        Double((text as NSString).size(withAttributes: [.font: font]).width)
    }

    // MARK: Position

    func setPosition(_ newPosition: Int) {
        position = min(max(0, newPosition), spokenCount)
        tracker.reset(to: position)
        currentLine = PreparedScript.lineIndex(forSpoken: position, in: lines)
    }

    func restart() {
        setPosition(0)
        if mode == .finished { mode = .paused }
    }

    /// Moves to the start of the next (or previous) line that has words on it.
    func moveLines(_ delta: Int) {
        let wordLines = lines.indices.filter { lines[$0].firstSpoken != nil }
        guard !wordLines.isEmpty else { return }
        let here = wordLines.lastIndex(where: { $0 <= currentLine }) ?? 0
        let target = wordLines[min(max(0, here + delta), wordLines.count - 1)]
        if let first = lines[target].firstSpoken { setPosition(first) }
        if mode == .finished { mode = .paused }
    }

    /// Applies a transcript as if the recognizer had produced it. The app calls this
    /// through the speech callback; the smoke test calls it directly.
    func applyTranscript(_ text: String) {
        guard tracker.update(transcript: text) else { return }
        position = tracker.position
        currentLine = PreparedScript.lineIndex(forSpoken: position, in: lines)
        if position >= spokenCount {
            stopInputs()
            mode = .finished
        }
    }

    // MARK: Start and stop

    func toggle() { isRunning ? pause() : start() }

    func start() {
        guard spokenCount > 0 else { return }
        if position >= spokenCount { setPosition(0) }
        if settings.followVoice {
            mode = .startingMic
            speech.contextualStrings = script.contextualStrings
            speech.start()
        } else {
            mode = .scrolling
            startTimer()
        }
    }

    func pause() {
        stopInputs()
        if mode != .finished { mode = .paused }
    }

    /// Picks up a new scroll speed while scrolling.
    func settingsChanged() {
        if mode == .scrolling { startTimer() }
    }

    private func heard(_ text: String) {
        guard mode == .listening || mode == .startingMic else { return }
        applyTranscript(text)
    }

    private func speechChanged(_ state: SpeechFollower.State) {
        switch state {
        case .listening:
            if mode == .startingMic { mode = .listening }
        case .idle:
            break
        case .failed(let message):
            stopInputs()
            mode = .paused
            onProblem?(message)
        }
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 60.0 / max(40, settings.wordsPerMinute), repeats: true) { [weak self] _ in
            guard let self else { return }
            if self.position >= self.spokenCount {
                self.stopInputs()
                self.mode = .finished
            } else {
                self.setPosition(self.position + 1)
            }
        }
    }

    private func stopInputs() {
        speech.stop()
        timer?.invalidate()
        timer = nil
    }
}
