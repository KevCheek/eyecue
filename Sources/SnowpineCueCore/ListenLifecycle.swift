import Foundation

/// Tracks whether the user wants the microphone on, so that slow callbacks
/// (permission prompts, delayed restarts) can't turn it on after the user paused.
///
/// Every start and every stop issues a new token. A callback may act only if it
/// still holds the current token and the user still wants to listen.
public struct ListenLifecycle {
    public private(set) var wantsRunning = false
    public private(set) var token = 0

    public init() {}

    /// Returns the token for this start, or nil if listening was already requested.
    public mutating func start() -> Int? {
        guard !wantsRunning else { return nil }
        wantsRunning = true
        token += 1
        return token
    }

    /// Returns true if there was anything to stop.
    @discardableResult
    public mutating func stop() -> Bool {
        guard wantsRunning else { return false }
        wantsRunning = false
        token += 1
        return true
    }

    public func isCurrent(_ candidate: Int) -> Bool {
        wantsRunning && candidate == token
    }
}

/// Stops endless restarts when speech recognition fails straight away again and again
/// (no recognizer, no microphone), while still allowing the normal end of a task after a long pause.
public struct QuickFailureGuard {
    public let limit: Int
    public let quickSeconds: TimeInterval
    public private(set) var consecutive = 0

    public init(limit: Int = 5, quickSeconds: TimeInterval = 1.5) {
        self.limit = limit
        self.quickSeconds = quickSeconds
    }

    /// Records how a recognition task ended. Returns true when it is time to give up.
    public mutating func taskEnded(after seconds: TimeInterval, failed: Bool, heardSomething: Bool) -> Bool {
        if heardSomething || !failed || seconds >= quickSeconds {
            consecutive = 0
            return false
        }
        consecutive += 1
        return consecutive >= limit
    }

    public mutating func reset() { consecutive = 0 }
}
