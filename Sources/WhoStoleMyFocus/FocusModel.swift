import FocusCore
import Foundation
import Observation

/// Everything the menu and the log window show, and the one place events come in.
@MainActor
@Observable
final class FocusModel {
    private(set) var log: FocusLog
    /// Steals since you last opened the menu or the log, for the menu bar icon.
    private(set) var unseenSteals = 0

    var ignored: Set<String> {
        didSet { preferences.ignored = ignored }
    }

    var threshold: Double {
        didSet {
            tracker.rules.threshold = threshold
            preferences.threshold = threshold
        }
    }

    var notifies: Bool {
        didSet { preferences.notifies = notifies }
    }

    /// Called for each steal by an app that isn't ignored.
    @ObservationIgnored var onSteal: ((FocusEvent) -> Void)?

    @ObservationIgnored private var tracker: FocusTracker
    @ObservationIgnored private let store: LogStore?
    @ObservationIgnored private let preferences: Preferences
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    /// How long to wait after a change before saving, so a burst of switches is one write.
    @ObservationIgnored var saveDelay: Duration = .seconds(3)

    init(store: LogStore?, preferences: Preferences, ownPID: ProcessID?) {
        self.store = store
        self.preferences = preferences
        let log = store?.load() ?? FocusLog()
        self.log = log
        let threshold = preferences.threshold
        self.threshold = threshold
        self.ignored = preferences.ignored
        self.notifies = preferences.notifies
        tracker = FocusTracker(log: log, rules: CauseRules(threshold: threshold), ownPID: ownPID)
    }

    var followUpDelay: Double { tracker.followUpDelay }
    var frontPID: ProcessID? { tracker.frontPID }

    /// Whether this is the app in front right now, so "Still in front" is only said of that one.
    func isCurrent(_ event: FocusEvent) -> Bool {
        tracker.frontEventID == event.id
    }

    // MARK: Events from the monitor

    func start(front pid: ProcessID, app: AppInfo, at date: Date, isLauncher: Bool) {
        tracker.start(front: pid, app: app, at: date, isLauncher: isLauncher)
    }

    func appLaunched(pid: ProcessID, at date: Date, input: InputSnapshot) {
        tracker.appLaunched(pid: pid, at: date, input: input)
    }

    func appLeft(pid: ProcessID, at date: Date, quit app: AppInfo? = nil) {
        tracker.appLeft(pid: pid, at: date, quit: app)
    }

    @discardableResult
    func appActivated(_ activation: Activation) -> FocusEvent? {
        guard let event = tracker.appActivated(activation) else { return nil }
        changed()
        if event.verdict == .stole, !tracker.isPending(event.id) { stoleFocus(event) }
        return event
    }

    func isPending(_ id: UUID) -> Bool {
        tracker.isPending(id)
    }

    func finishFollowUp(
        _ id: UUID, keptTyping: Bool, spaceChanged: Bool, at date: Date, hasLeft: (ProcessID) -> Bool = { _ in false }
    ) {
        guard let event = tracker.finishFollowUp(id, keptTyping: keptTyping, spaceChanged: spaceChanged, at: date, hasLeft: hasLeft) else { return }
        changed()
        if event.verdict == .stole { stoleFocus(event) }
    }

    // MARK: What the menu and log show

    func isIgnored(_ app: AppInfo) -> Bool {
        ignored.contains(app.key)
    }

    func steals(since start: Date? = nil) -> [FocusEvent] {
        log.steals(ignoring: ignored, since: start)
    }

    func offenders(since start: Date? = nil) -> [Offender] {
        log.offenders(ignoring: ignored, since: start)
    }

    /// The newest name seen for each ignored app, for the Ignored Apps menu.
    var ignoredApps: [(key: String, name: String)] {
        var names: [String: String] = [:]
        for event in log.events where ignored.contains(event.app.key) {
            names[event.app.key] = Describe.name(event.app)
        }
        return ignored.map { key in
            (key, names[key] ?? SystemApps.ignoredDefaultNames[key] ?? key)
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    // MARK: Changes from the menu and log

    func ignore(_ app: AppInfo) {
        ignored.insert(app.key)
    }

    func stopIgnoring(_ key: String) {
        ignored.remove(key)
    }

    func markSeen() {
        unseenSteals = 0
    }

    func clearLog() {
        tracker.clearLog()
        unseenSteals = 0
        changed()
    }

    /// Stops tracking and saves right away, for quitting.
    func flush(at date: Date = Date()) {
        tracker.finish(at: date)
        log = tracker.log
        saveTask?.cancel()
        saveTask = nil
        try? store?.save(log)
    }

    private func stoleFocus(_ event: FocusEvent) {
        guard !isIgnored(event.app) else { return }
        unseenSteals += 1
        onSteal?(event)
    }

    private func changed() {
        log = tracker.log
        guard store != nil else { return }
        saveTask?.cancel()
        let delay = saveDelay
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            try? self.store?.save(self.log)
        }
    }
}
