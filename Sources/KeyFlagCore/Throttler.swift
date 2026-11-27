import Foundation

/// Runs the most recent block at most once per `minimumDelay`, always running the last
/// call of a burst. Used to keep Accessibility queries cheap while the mouse moves.
@MainActor
public final class Throttler {
    private let minimumDelay: TimeInterval
    private let now: () -> TimeInterval
    private var lastRun: TimeInterval = -.infinity
    private var pending: Task<Void, Never>?

    public init(minimumDelay: TimeInterval, now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.minimumDelay = minimumDelay
        self.now = now
    }

    public func throttle(_ block: @escaping @MainActor () -> Void) {
        pending?.cancel()
        let delay = max(0, minimumDelay - (now() - lastRun))
        pending = Task { @MainActor [weak self] in
            if delay > 0 {
                try? await Task.sleep(for: .seconds(delay))
            }
            // Checked even without a delay: a newer call may have replaced this one
            // before the task got to run.
            guard !Task.isCancelled, let self else { return }
            self.lastRun = self.now()
            block()
        }
    }

    public func cancel() {
        pending?.cancel()
        pending = nil
    }
}
