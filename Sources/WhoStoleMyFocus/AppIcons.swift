import AppKit
import FocusCore

/// App icons for the menu and the log, looked up once per app.
@MainActor
final class AppIcons {
    private var cache: [String: NSImage] = [:]
    /// Icons to use instead of looking them up, by `AppInfo.key`. Used for the README screenshots,
    /// whose made-up apps have no icons of their own.
    var custom: [String: NSImage] = [:]

    func icon(for app: AppInfo, size: CGFloat) -> NSImage {
        let key = "\(app.key)@\(size)"
        if let cached = cache[key] { return cached }
        let icon = ((custom[app.key] ?? source(for: app)).copy() as? NSImage) ?? NSImage()
        icon.size = NSSize(width: size, height: size)
        cache[key] = icon
        return icon
    }

    private func source(for app: AppInfo) -> NSImage {
        if let path = app.path, FileManager.default.fileExists(atPath: path) {
            return NSWorkspace.shared.icon(forFile: path)
        }
        if let id = app.bundleID, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        return NSWorkspace.shared.icon(for: .applicationBundle)
    }
}
