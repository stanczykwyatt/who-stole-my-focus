import Foundation
@testable import FocusCore

/// Apps and input times used across the tests.
enum Fixture {
    static let start = Date(timeIntervalSince1970: 1_800_000_000)

    static let xcode = AppInfo(name: "Xcode", bundleID: "com.apple.dt.Xcode", path: "/Applications/Xcode.app")
    static let notes = AppInfo(name: "Notes", bundleID: "com.apple.Notes", path: "/System/Applications/Notes.app")
    static let updater = AppInfo(
        name: "SyncHelper", bundleID: "com.example.sync.helper",
        path: "/Applications/CloudSync.app/Contents/Library/LoginItems/SyncHelper.app"
    )
    static let meetings = AppInfo(name: "Meetings", bundleID: "com.example.meetings", path: "/Applications/Meetings.app")
    static let launcher = AppInfo(name: "Launcher", bundleID: "com.example.launcher", path: "/Applications/Launcher.app")
    static let securityAgent = AppInfo(
        name: "SecurityAgent", bundleID: "com.apple.SecurityAgent",
        path: "/System/Library/Frameworks/Security.framework/Versions/A/MachServices/SecurityAgent.bundle"
    )
    static let loginWindow = AppInfo(name: "loginwindow", bundleID: "com.apple.loginwindow", path: "/System/Library/CoreServices/loginwindow.app")
    static let own = AppInfo(name: "Who Stole My Focus", bundleID: "com.stanczykwyatt.WhoStoleMyFocus")

    static let pids: [String: ProcessID] = [
        "Xcode": 101, "Notes": 102, "SyncHelper": 103, "Meetings": 104, "Launcher": 105,
        "SecurityAgent": 106, "loginwindow": 107, "Who Stole My Focus": 999,
    ]

    /// A fixed ID per app name. Apps not listed get one made from their name, stable for the run.
    static func pid(_ app: AppInfo) -> ProcessID {
        pids[app.name] ?? 2_000 + ProcessID(app.name.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) % 10_000 })
    }

    /// Nothing for a minute.
    static let idle = InputSnapshot(click: 60, keyPress: 60, modifierChange: 60, gesture: 60)

    static func clicked(_ seconds: Double) -> InputSnapshot {
        var input = idle
        input.click = seconds
        return input
    }

    static func typed(_ seconds: Double) -> InputSnapshot {
        var input = idle
        input.keyPress = seconds
        return input
    }

    /// Touched the trackpad a moment ago, which macOS reports for a swipe and for moving the pointer alike.
    static func touchedTrackpad(_ seconds: Double) -> InputSnapshot {
        var input = idle
        input.gesture = seconds
        return input
    }

    /// ⌘Tab: Tab pressed, then ⌘ let go just before the switch.
    static let commandTab = InputSnapshot(click: 60, keyPress: 0.3, modifierChange: 0.05, gesture: 60)

    static func event(
        _ app: AppInfo, at offset: TimeInterval, from previous: AppInfo? = nil, verdict: Verdict = .stole,
        cause: Cause = .none, heldFor: Double? = nil
    ) -> FocusEvent {
        FocusEvent(
            date: start.addingTimeInterval(offset), app: app, pid: pids[app.name] ?? 1, previous: previous,
            input: idle, cause: cause, verdict: verdict, heldFor: heldFor
        )
    }
}

extension InputSnapshot {
    func with(click: Double) -> InputSnapshot {
        var copy = self
        copy.click = click
        return copy
    }
}

/// Drives a tracker through a sequence of switches, one second apart unless told otherwise.
final class Scenario {
    var tracker: FocusTracker
    var clock: Date

    init(front: AppInfo = Fixture.xcode, rules: CauseRules = CauseRules(), limit: Int = FocusLog.defaultLimit) {
        tracker = FocusTracker(log: FocusLog(limit: limit), rules: rules, ownPID: Fixture.pid(Fixture.own))
        clock = Fixture.start
        // Started an hour earlier, so the input times in the fixtures come after tracking began.
        tracker.start(front: Fixture.pid(front), app: front, at: clock.addingTimeInterval(-3600))
    }

    @discardableResult
    func activate(
        _ app: AppInfo, after seconds: TimeInterval = 1, input: InputSnapshot = Fixture.idle, launcher: Bool = false,
        previousHasLeft: Bool = false, launchedAgo: TimeInterval? = nil
    ) -> FocusEvent? {
        clock = clock.addingTimeInterval(seconds)
        return tracker.appActivated(Activation(
            pid: Fixture.pid(app), app: app, date: clock, input: input,
            launchDate: launchedAgo.map { clock.addingTimeInterval(-$0) },
            isLauncher: launcher, previousHasLeft: previousHasLeft
        ))
    }

    func launch(_ app: AppInfo, after seconds: TimeInterval = 1, input: InputSnapshot = Fixture.idle) {
        clock = clock.addingTimeInterval(seconds)
        tracker.appLaunched(pid: Fixture.pid(app), at: clock, input: input)
    }

    func leave(_ app: AppInfo, after seconds: TimeInterval = 0) {
        clock = clock.addingTimeInterval(seconds)
        tracker.appLeft(pid: Fixture.pid(app), at: clock)
    }

    func finishFollowUp(
        _ id: UUID, keptTyping: Bool = false, spaceChanged: Bool = false, left: Set<AppInfo> = []
    ) -> FocusEvent? {
        clock = clock.addingTimeInterval(tracker.followUpDelay)
        let pids = Set(left.map(Fixture.pid))
        return tracker.finishFollowUp(id, keptTyping: keptTyping, spaceChanged: spaceChanged, at: clock) { pids.contains($0) }
    }

    func leave(_ app: AppInfo, quitting: Bool, after seconds: TimeInterval = 0) {
        clock = clock.addingTimeInterval(seconds)
        tracker.appLeft(pid: Fixture.pid(app), at: clock, quit: quitting ? app : nil)
    }

    func isPending(_ id: UUID) -> Bool {
        tracker.isPending(id)
    }

    var events: [FocusEvent] { tracker.log.events }
}
