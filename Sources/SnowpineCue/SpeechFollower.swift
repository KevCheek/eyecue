import AVFoundation
import SnowpineCueCore
import Foundation
import Speech

/// Streams the microphone into Apple's speech recognizer and reports the running transcript.
///
/// Recognition is on-device only (`requiresOnDeviceRecognition = true`). If this Mac
/// can't recognize speech locally, voice follow stays off rather than sending audio
/// to a server. Audio is never written to disk.
final class SpeechFollower {
    enum State {
        case idle
        case listening
        case failed(String)
    }

    /// Called on the main thread with the whole utterance heard so far.
    var onTranscript: ((String) -> Void)?
    /// Called on the main thread.
    var onStateChange: ((State) -> Void)?
    /// Unusual words from the script, as hints for the recognizer.
    var contextualStrings: [String] = []

    private lazy var engine = AVAudioEngine()
    private var recognizer: SFSpeechRecognizer?
    private var task: SFSpeechRecognitionTask?
    /// True while the audio engine and its tap are live.
    private var running = false
    /// What the user asked for. Callbacks that arrive after a pause carry an old token and do nothing.
    private var lifecycle = ListenLifecycle()
    private var failures = QuickFailureGuard()
    /// Bumped whenever a task is replaced, so late callbacks from an old task are ignored.
    private var generation = 0

    // The audio tap runs on a real-time thread; it reads the current request under a lock.
    private let lock = NSLock()
    private var request: SFSpeechAudioBufferRecognitionRequest?

    func start() {
        guard let token = lifecycle.start() else { return }
        failures.reset()
        requestPermissions { [weak self] granted, message in
            // The user may have paused while the permission prompt was up.
            guard let self, self.lifecycle.isCurrent(token) else { return }
            guard granted else {
                self.fail(message)
                return
            }
            self.begin(token: token)
        }
    }

    func stop() {
        guard lifecycle.stop() else { return }
        shutDown()
        onStateChange?(.idle)
    }

    // MARK: Private

    private func requestPermissions(_ done: @escaping (Bool, String) -> Void) {
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async {
                guard status == .authorized else {
                    done(false, "Speech recognition is off for Snowpine Cue. Turn it on in System Settings > Privacy & Security > Speech Recognition, then press Start again.")
                    return
                }
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    DispatchQueue.main.async {
                        done(granted, "The microphone is off for Snowpine Cue. Turn it on in System Settings > Privacy & Security > Microphone, then press Start again.")
                    }
                }
            }
        }
    }

    /// Turns the microphone off and forgets the current request. Safe to call in any state.
    private func shutDown() {
        generation += 1
        endCurrentRequest()
        if running {
            running = false
            if engine.isRunning { engine.stop() }
            engine.inputNode.removeTap(onBus: 0)
        }
    }

    private func fail(_ message: String) {
        lifecycle.stop()
        shutDown()
        onStateChange?(.failed(message))
    }

    private func begin(token: Int) {
        let recognizer = SFSpeechRecognizer(locale: Locale.current) ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        guard let recognizer, recognizer.supportsOnDeviceRecognition else {
            fail("This Mac can't recognize speech on-device for your language yet, and Snowpine Cue never sends audio off the Mac. Turn on Dictation in System Settings > Keyboard so macOS downloads the speech model, or turn off Follow My Voice to scroll at a set speed.")
            return
        }
        self.recognizer = recognizer

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            fail("No microphone input is available.")
            return
        }
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 2048, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            self.lock.lock()
            let request = self.request
            self.lock.unlock()
            request?.append(buffer)
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            fail("The microphone couldn't start: \(error.localizedDescription)")
            return
        }
        running = true
        startTask(token: token)
        onStateChange?(.listening)
    }

    private func startTask(token: Int) {
        guard running, lifecycle.isCurrent(token), let recognizer else { return }
        endCurrentRequest()
        generation += 1
        let myGeneration = generation
        let startedAt = Date()
        var heardSomething = false

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        request.addsPunctuation = false
        request.contextualStrings = contextualStrings
        lock.lock()
        self.request = request
        lock.unlock()

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let failed = error != nil
            let finished = failed || (result?.isFinal ?? false)
            DispatchQueue.main.async {
                guard let self, self.running, self.lifecycle.isCurrent(token), myGeneration == self.generation else { return }
                if let text, !text.isEmpty {
                    heardSomething = true
                    self.onTranscript?(text)
                }
                guard finished else { return }
                // Recognition ends after a long pause or an error. Start a fresh task and keep listening,
                // unless it keeps failing straight away, which means it can't work right now.
                let giveUp = self.failures.taskEnded(after: Date().timeIntervalSince(startedAt),
                                                     failed: failed, heardSomething: heardSomething)
                if giveUp {
                    self.fail("Speech recognition keeps stopping, so Snowpine Cue turned the microphone off. Press Start to try again, or turn off Follow My Voice to scroll at a set speed.")
                } else {
                    self.restartTask(token: token)
                }
            }
        }
    }

    private func restartTask(token: Int) {
        generation += 1
        endCurrentRequest()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            self?.startTask(token: token)
        }
    }

    private func endCurrentRequest() {
        lock.lock()
        let old = request
        request = nil
        lock.unlock()
        old?.endAudio()
        task?.cancel()
        task = nil
    }
}
