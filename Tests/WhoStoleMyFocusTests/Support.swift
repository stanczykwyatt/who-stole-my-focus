import AppKit
import FocusCore
@testable import WhoStoleMyFocus

/// An input clock the test sets by hand.
final class FakeClock: InputClock {
    var input = InputSnapshot(click: 60, keyPress: 60, modifierChange: 60, gesture: 60)
    func snapshot() -> InputSnapshot { input }
}

/// Settings in a throwaway defaults domain, so tests never touch the real app's settings.
func scratchPreferences() -> Preferences {
    let name = "WhoStoleMyFocusTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    return Preferences(defaults: defaults)
}

/// A folder that's deleted when the test process ends.
func scratchFolder() -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("WhoStoleMyFocusTests-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

enum Sample {
    static let start = Date(timeIntervalSince1970: 1_800_000_000)
    static let xcode = AppInfo(name: "Xcode", bundleID: "com.apple.dt.Xcode", path: "/Applications/Xcode.app")
    static let notes = AppInfo(name: "Notes", bundleID: "com.apple.Notes", path: "/System/Applications/Notes.app")
    static let syncHelper = AppInfo(
        name: "SyncHelper", bundleID: "com.example.sync.helper",
        path: "/Applications/CloudSync.app/Contents/Library/LoginItems/SyncHelper.app"
    )
    static let meetings = AppInfo(name: "Meetings", bundleID: "com.example.meetings", path: "/Applications/Meetings.app")

    static func steal(_ app: AppInfo, from previous: AppInfo, at date: Date, idle: Double = 41, heldFor: Double? = 2) -> FocusEvent {
        FocusEvent(
            date: date, app: app, pid: 500, previous: previous,
            input: InputSnapshot(click: idle, keyPress: idle, modifierChange: idle, gesture: idle),
            cause: .none, verdict: .stole, heldFor: heldFor, next: previous, nextVerdict: .switched
        )
    }

    static func switched(_ app: AppInfo, from previous: AppInfo, at date: Date) -> FocusEvent {
        FocusEvent(
            date: date, app: app, pid: 501, previous: previous,
            input: InputSnapshot(click: 0.1, keyPress: 30, modifierChange: 30, gesture: 30),
            cause: .click, verdict: .switched, heldFor: 30
        )
    }

    /// Always running, so tests have real `NSRunningApplication`s to put in notifications.
    static var finder: NSRunningApplication {
        NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first!
    }

    static var desktopIsRunning: Bool {
        ["com.apple.finder", "com.apple.dock"].allSatisfy { !NSRunningApplication.runningApplications(withBundleIdentifier: $0).isEmpty }
    }

    /// The test process itself: a real running app that isn't part of macOS, to play the thief.
    static var me: NSRunningApplication { .current }

    static var dock: NSRunningApplication {
        NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first!
    }
}

/// A model whose log holds these events, without a file behind it.
@MainActor
func model(with events: [FocusEvent], preferences: Preferences = scratchPreferences()) -> FocusModel {
    let folder = scratchFolder()
    let store = LogStore(url: folder.appendingPathComponent("log.json"))
    try? store.save(FocusLog(events: events))
    return FocusModel(store: store, preferences: preferences, ownPID: nil)
}
