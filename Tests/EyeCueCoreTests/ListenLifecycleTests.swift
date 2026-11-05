import Testing
@testable import EyeCueCore

@Test func pausingWhileThePermissionPromptIsUpKeepsTheMicOff() {
    var life = ListenLifecycle()
    let token = life.start()!
    life.stop()                       // the user pauses before answering the prompt
    #expect(!life.isCurrent(token))   // so the late "granted" callback must not start the mic
}

@Test func aRestartFromAnEarlierSessionIsIgnored() {
    var life = ListenLifecycle()
    let first = life.start()!
    life.stop()
    let second = life.start()!
    #expect(!life.isCurrent(first))
    #expect(life.isCurrent(second))
}

@Test func startingTwiceDoesNotIssueASecondToken() {
    var life = ListenLifecycle()
    let first = life.start()
    let second = life.start()
    #expect(first != nil)
    #expect(second == nil)
}

@Test func repeatedInstantFailuresGiveUp() {
    var guardrail = QuickFailureGuard(limit: 3, quickSeconds: 1.5)
    let results = (1...3).map { _ in guardrail.taskEnded(after: 0.1, failed: true, heardSomething: false) }
    #expect(results == [false, false, true])
}

@Test func aLongPauseEndingATaskIsNotAFailure() {
    var guardrail = QuickFailureGuard(limit: 2, quickSeconds: 1.5)
    let quick = guardrail.taskEnded(after: 0.1, failed: true, heardSomething: false)
    let silenceTimeout = guardrail.taskEnded(after: 45, failed: true, heardSomething: false)
    let quickAgain = guardrail.taskEnded(after: 0.1, failed: true, heardSomething: false)
    #expect([quick, silenceTimeout, quickAgain] == [false, false, false])
}
