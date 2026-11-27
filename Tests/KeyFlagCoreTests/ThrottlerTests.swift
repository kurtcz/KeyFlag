import Testing
@testable import KeyFlagCore

@MainActor
struct ThrottlerTests {
    @Test func burstRunsOnlyTheLastBlock() async throws {
        let throttler = Throttler(minimumDelay: 0.05)
        let calls = Recorder()
        throttler.throttle {} // starts the throttle window
        try await Task.sleep(for: .milliseconds(10))
        for i in 0..<10 {
            throttler.throttle { calls.values.append(i) }
        }
        try await Task.sleep(for: .milliseconds(200))
        #expect(calls.values == [9])
    }

    @Test func idleThrottlerRunsImmediately() async throws {
        let throttler = Throttler(minimumDelay: 10)
        let calls = Recorder()
        throttler.throttle { calls.values.append(1) }
        try await Task.sleep(for: .milliseconds(50))
        #expect(calls.values == [1])
    }

    @Test func cancelDropsPendingBlock() async throws {
        let throttler = Throttler(minimumDelay: 0.05)
        let calls = Recorder()
        throttler.throttle {}
        try await Task.sleep(for: .milliseconds(10))
        throttler.throttle { calls.values.append(1) }
        throttler.cancel()
        try await Task.sleep(for: .milliseconds(150))
        #expect(calls.values.isEmpty)
    }
}

@MainActor
final class Recorder {
    var values: [Int] = []
}
