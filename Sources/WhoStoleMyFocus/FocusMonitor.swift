import AppKit
import FocusCore

extension AppInfo {
    init(_ app: NSRunningApplication) {
        let url = app.bundleURL ?? app.executableURL
        self.init(
            name: app.localizedName ?? url?.deletingPathExtension().lastPathComponent ?? "Process \(app.processIdentifier)",
            bundleID: app.bundleIdentifier,
            path: url?.path
        )
    }
}

/// Watches macOS for apps coming to the front and passes them to the model.
///
/// It only listens to notifications every app can receive, and reads input times. It never
/// activates, hides or changes another app.
@MainActor
final class FocusMonitor {
    private let model: FocusModel
    private let center: NotificationCenter
    private let clock: InputClock
    private let now: () -> Date
    private let frontmost: () -> NSRunningApplication?
    private let lookup: (ProcessID) -> NSRunningApplication?
    /// Runs the typing check later. Swappable so tests don't have to wait.
    private let schedule: (Double, @escaping @MainActor () -> Void) -> Void
    private var observers: [NSObjectProtocol] = []
    /// While you're switched to another user account, nothing here is yours.
    private var paused = false
    /// When macOS last switched Spaces, to tell a swipe from just touching the trackpad.
    private var lastSpaceChange: Date?
    /// How close a Space change has to be to an app's arrival to be the reason for it.
    private let spaceWindow: TimeInterval = 1

    init(
        model: FocusModel,
        center: NotificationCenter = NSWorkspace.shared.notificationCenter,
        clock: InputClock = SystemInputClock(),
        now: @escaping () -> Date = Date.init,
        frontmost: @escaping () -> NSRunningApplication? = { NSWorkspace.shared.frontmostApplication },
        lookup: @escaping (ProcessID) -> NSRunningApplication? = { NSRunningApplication(processIdentifier: $0) },
        schedule: @escaping (Double, @escaping @MainActor () -> Void) -> Void = FocusMonitor.later
    ) {
        self.model = model
        self.center = center
        self.clock = clock
        self.now = now
        self.frontmost = frontmost
        self.lookup = lookup
        self.schedule = schedule
    }

    func start() {
        guard observers.isEmpty else { return }
        observe(NSWorkspace.didActivateApplicationNotification) { monitor, app in monitor.activated(app) }
        observe(NSWorkspace.willLaunchApplicationNotification) { monitor, app in monitor.launched(app) }
        observe(NSWorkspace.didHideApplicationNotification) { monitor, app in monitor.left(app, quit: false) }
        observe(NSWorkspace.didTerminateApplicationNotification) { monitor, app in monitor.left(app, quit: true) }
        observe(NSWorkspace.activeSpaceDidChangeNotification) { monitor, _ in monitor.lastSpaceChange = monitor.now() }
        observe(NSWorkspace.sessionDidResignActiveNotification) { monitor, _ in monitor.paused = true }
        observe(NSWorkspace.sessionDidBecomeActiveNotification) { monitor, _ in
            monitor.paused = false
            monitor.startFromFrontmost()
        }
        startFromFrontmost()
    }

    func stop() {
        observers.forEach(center.removeObserver)
        observers.removeAll()
    }

    private func observe(_ name: Notification.Name, _ handle: @escaping @MainActor (FocusMonitor, NSRunningApplication?) -> Void) {
        let observer = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated {
                guard let self else { return }
                handle(self, app)
            }
        }
        observers.append(observer)
    }

    private func startFromFrontmost() {
        guard let app = frontmost() else { return }
        model.start(front: app.processIdentifier, app: AppInfo(app), at: now(), isLauncher: app.activationPolicy != .regular)
    }

    private func activated(_ app: NSRunningApplication?) {
        guard !paused, let app else { return }
        let date = now()
        var previousHasLeft = false
        if let pid = model.frontPID, pid != app.processIdentifier {
            // Gone from the list means it quit.
            previousHasLeft = lookup(pid).map { $0.isTerminated || $0.isHidden } ?? true
        }
        let activation = Activation(
            pid: app.processIdentifier, app: AppInfo(app), date: date, input: clock.snapshot(),
            launchDate: app.launchDate, isLauncher: app.activationPolicy != .regular,
            previousHasLeft: previousHasLeft
        )
        guard let event = model.appActivated(activation), model.isPending(event.id) else { return }
        // A menu bar app with no windows can be napped, which would make the follow-up late.
        let activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .latencyCritical], reason: "Checking a focus change")
        schedule(model.followUpDelay) { [weak self] in
            ProcessInfo.processInfo.endActivity(activity)
            self?.followUp(event)
        }
    }

    private func followUp(_ event: FocusEvent) {
        let date = now()
        let elapsed = date.timeIntervalSince(event.date)
        let input = clock.snapshot()
        // A key pressed after the app came forward means you were still typing, unless it was a
        // shortcut aimed at the new app, like ⌘T. A check that ran late can't tell either way.
        let onTime = elapsed <= model.followUpDelay + 0.6
        let shortcut = input.commandKeysHeld || input.modifierChange < input.keyPress
        let keptTyping = onTime && input.keyPress < elapsed && !shortcut
        let spaceChanged = lastSpaceChange.map { abs($0.timeIntervalSince(event.date)) <= spaceWindow } ?? false
        model.finishFollowUp(event.id, keptTyping: keptTyping, spaceChanged: spaceChanged, at: date) { [lookup] pid in
            lookup(pid).map { $0.isTerminated || $0.isHidden } ?? true
        }
    }

    private func launched(_ app: NSRunningApplication?) {
        guard !paused, let app else { return }
        model.appLaunched(pid: app.processIdentifier, at: now(), input: clock.snapshot())
    }

    private func left(_ app: NSRunningApplication?, quit: Bool) {
        guard let app else { return }
        model.appLeft(pid: app.processIdentifier, at: now(), quit: quit ? AppInfo(app) : nil)
    }

    nonisolated static func later(_ seconds: Double, _ work: @escaping @MainActor () -> Void) {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(seconds))
            work()
        }
    }
}
