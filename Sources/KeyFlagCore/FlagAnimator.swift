import AppKit

/// Shows a list of frames in turn, looping, by handing each one to `apply`.
/// A single frame is shown once with no timer running.
@MainActor
final class FlagAnimator {
    private let apply: (NSImage) -> Void
    private let interval: TimeInterval
    private var frames: [NSImage] = []
    private var index = 0
    private var timer: Timer?

    init(framesPerSecond: Double = 12, apply: @escaping (NSImage) -> Void) {
        self.interval = 1 / framesPerSecond
        self.apply = apply
    }

    /// Shows `frames`, restarting only if they changed (so redundant updates don't jump).
    func show(_ frames: [NSImage]) {
        guard !frames.isEmpty else { return }
        if frames.count == self.frames.count, zip(frames, self.frames).allSatisfy({ $0 === $1 }) {
            if timer == nil { start() }
            return
        }
        self.frames = frames
        index = 0
        apply(frames[0])
        start()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func start() {
        stop()
        guard frames.count > 1 else { return }
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.advance() }
        }
        RunLoop.main.add(timer, forMode: .common) // keep waving while a menu is open
        self.timer = timer
    }

    private func advance() {
        index = (index + 1) % frames.count
        apply(frames[index])
    }
}
