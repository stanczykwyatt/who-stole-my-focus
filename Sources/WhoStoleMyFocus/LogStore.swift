import FocusCore
import Foundation

/// Saves the log as JSON in the app's sandbox container. Nothing is ever sent anywhere.
struct LogStore {
    let url: URL

    init(url: URL = LogStore.defaultURL) {
        self.url = url
    }

    static var defaultURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Who Stole My Focus", isDirectory: true)
            .appendingPathComponent("log.json")
    }

    /// The saved log, or an empty one. A file that can't be read, whether damaged or written by a
    /// newer version, is moved aside rather than overwritten, so nothing is lost.
    func load() -> FocusLog {
        guard let data = try? Data(contentsOf: url) else { return FocusLog() }
        do {
            return try LogFile.decode(data)
        } catch {
            setAside()
            return FocusLog()
        }
    }

    func save(_ log: FocusLog) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try LogFile.encode(log).write(to: url, options: .atomic)
    }

    private func setAside() {
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let aside = url.deletingLastPathComponent().appendingPathComponent("log-unreadable-\(stamp).json")
        try? FileManager.default.moveItem(at: url, to: aside)
    }
}
