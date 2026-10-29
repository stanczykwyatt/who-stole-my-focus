/// Parts of macOS that come to the front by themselves, described in words people recognize.
public enum SystemApps {
    /// Bundle IDs checked against macOS 15. Most of these are agents with names like "coreautha"
    /// that never appear in the Dock.
    public static let descriptions: [String: String] = [
        "com.apple.SecurityAgent": "macOS asking for your password to approve a change",
        "com.apple.LocalAuthentication.UIAgent": "macOS asking for Touch ID or your password",
        "com.apple.UserNotificationCenter": "a system alert",
        "com.apple.loginwindow": "the lock screen or login window",
        "com.apple.ScreenSaver.Engine": "the screen saver",
        "com.apple.coreservices.uiagent": "a warning about something downloaded from the internet",
        "com.apple.accessibility.universalAccessAuthWarn": "an app asking for Accessibility access",
        "com.apple.CoreLocationAgent": "an app asking to use your location",
        "com.apple.security.Keychain-Circle-Notification": "an iCloud Keychain prompt",
        "com.apple.IOUIAgent": "macOS asking whether to allow a USB accessory",
        "com.apple.UnmountAssistantAgent": "a disk that couldn't be ejected",
        "com.apple.NetAuthAgent": "a network server asking you to sign in",
        "com.apple.BluetoothUIServer": "a Bluetooth pairing prompt",
        "com.apple.BluetoothUIService": "a Bluetooth pairing prompt",
        "com.apple.wifi.WiFiAgent": "a Wi-Fi password or sign-in prompt",
        "com.apple.SoftwareUpdate": "Software Update",
        "com.apple.PackageUIKit.Install-in-Progress": "an installer finishing up",
        "com.apple.DiagnosticsReporter": "a crash report",
        "com.apple.ProblemReporter": "a crash report",
        "com.apple.KeyboardSetupAssistant": "the keyboard setup assistant",
        "com.apple.dock": "the Dock, Mission Control or Launchpad",
        "com.apple.Spotlight": "Spotlight",
        "com.apple.notificationcenterui": "Notification Center",
        "com.apple.controlcenter": "Control Center",
        "com.apple.systemuiserver": "a menu bar item",
        "com.apple.WindowManager": "Stage Manager",
        "com.apple.screencaptureui": "the screenshot toolbar",
        "com.apple.Siri": "Siri",
        "com.apple.PIPAgent": "a picture-in-picture video",
    ]

    public static func description(for app: AppInfo) -> String? {
        app.bundleID.flatMap { descriptions[$0] }
    }

    /// Parts of macOS that come forward because you asked for them, from a hot corner, gesture,
    /// special key or menu bar click, so they're never counted as stealing focus.
    public static let onRequest: Set<String> = [
        "com.apple.dock",
        "com.apple.Spotlight",
        "com.apple.notificationcenterui",
        "com.apple.controlcenter",
        "com.apple.systemuiserver",
        "com.apple.WindowManager",
        "com.apple.screencaptureui",
        "com.apple.Siri",
        "com.apple.PIPAgent",
    ]

    public static func opensOnRequest(_ app: AppInfo) -> Bool {
        app.bundleID.map(onRequest.contains) ?? false
    }

    /// System screens that interrupt whatever you're doing and then hand focus back to it.
    public static func isInterruption(_ app: AppInfo) -> Bool {
        description(for: app) != nil
    }

    /// Locking the screen isn't an app misbehaving, so these aren't counted unless you choose to.
    public static let ignoredByDefault: Set<String> = Set(ignoredDefaultNames.keys)

    /// Names for the apps ignored by default, for menus shown before either has come to the front.
    public static let ignoredDefaultNames: [String: String] = [
        "com.apple.loginwindow": "Lock screen (loginwindow)",
        "com.apple.ScreenSaver.Engine": "Screen saver (ScreenSaverEngine)",
    ]
}
