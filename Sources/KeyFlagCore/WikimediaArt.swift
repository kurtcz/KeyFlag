import AppKit

/// Flags and coats of arms taken from Wikimedia Commons, rendered to PNG at 150 px high
/// and bundled in `Resources/Flags` and `Resources/CoatsOfArms` (one `<CODE>.png` each;
/// sources, authors and licenses in `Resources/Wikimedia-Credits.md`).
/// `Scripts/fetch-wikimedia-art.py` downloads them again.
enum WikimediaArt {
    enum Kind: String {
        case flag = "Flags"
        case coatOfArms = "CoatsOfArms"
    }

    static func image(_ kind: Kind, code: String) -> NSImage? {
        cache.image(kind, code: code.uppercased())
    }

    /// The app's Resources folder, or the repository's when running tests or `swift run`.
    static let resourceRoot: URL? = {
        let fileManager = FileManager.default
        if let bundled = Bundle.main.resourceURL,
           fileManager.fileExists(atPath: bundled.appendingPathComponent(Kind.flag.rawValue).path) {
            return bundled
        }
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources")
        return fileManager.fileExists(atPath: repository.appendingPathComponent(Kind.flag.rawValue).path) ? repository : nil
    }()

    private static let cache = Cache()

    private final class Cache: @unchecked Sendable {
        private let lock = NSLock()
        private var images: [String: NSImage?] = [:]

        func image(_ kind: Kind, code: String) -> NSImage? {
            let key = kind.rawValue + "/" + code
            lock.lock()
            defer { lock.unlock() }
            if let cached = images[key] { return cached }
            let url = resourceRoot?.appendingPathComponent(kind.rawValue).appendingPathComponent(code + ".png")
            let image = url.flatMap { NSImage(contentsOf: $0) }
            images[key] = image
            return image
        }
    }
}
