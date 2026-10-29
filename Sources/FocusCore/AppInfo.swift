/// A process ID. Kept as a plain integer so this target doesn't need AppKit.
public typealias ProcessID = Int32

/// An app as it was when it came to the front.
public struct AppInfo: Codable, Hashable, Sendable {
    public var name: String
    public var bundleID: String?
    /// The app bundle, or the executable for apps that don't have one.
    public var path: String?

    public init(name: String, bundleID: String? = nil, path: String? = nil) {
        self.name = name
        self.bundleID = bundleID
        self.path = path
    }

    /// Groups events from the same app, even after an update moves or renames it.
    public var key: String { bundleID ?? path ?? name }

    /// The app this one ships inside, like "Logi Options+" for a helper in
    /// "Logi Options+.app/Contents/Frameworks/". Helpers often have names nobody recognizes.
    public var containingAppName: String? {
        guard let path else { return nil }
        var components = path.split(separator: "/")
        if components.last.map(Self.isAppBundle) == true {
            components.removeLast()
        }
        guard let outer = components.first(where: Self.isAppBundle) else { return nil }
        let name = String(outer.dropLast(4))
        return name.isEmpty || name == self.name ? nil : name
    }

    private static func isAppBundle(_ component: Substring) -> Bool {
        component.count > 4 && component.lowercased().hasSuffix(".app")
    }
}
