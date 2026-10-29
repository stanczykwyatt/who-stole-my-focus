import Foundation

/// An app coming to the front, as macOS reported it.
public struct Activation: Sendable {
    public var pid: ProcessID
    public var app: AppInfo
    public var date: Date
    public var input: InputSnapshot
    public var launchDate: Date?
    /// Menu bar apps and launchers like Spotlight, Raycast and Alfred, where typing a few letters
    /// and pressing Return opens other apps.
    public var isLauncher: Bool
    /// Whether the app that was in front has quit or hidden by now. macOS doesn't always say so
    /// before it brings the next app forward.
    public var previousHasLeft: Bool

    public init(
        pid: ProcessID, app: AppInfo, date: Date, input: InputSnapshot, launchDate: Date? = nil,
        isLauncher: Bool = false, previousHasLeft: Bool = false
    ) {
        self.pid = pid
        self.app = app
        self.date = date
        self.input = input
        self.launchDate = launchDate
        self.isLauncher = isLauncher
        self.previousHasLeft = previousHasLeft
    }
}

/// Decides why each app came to the front and keeps the log.
///
/// It remembers the last few apps that were in front, so focus returning to the app you were using
/// after an interruption isn't blamed on that app. Anything that could still turn out differently
/// waits for a follow-up a moment later before anyone is told about it.
public struct FocusTracker: Sendable {
    public var rules: CauseRules
    /// How long after you open an app its first trip to the front still counts as you opening it.
    /// Big apps can take a while to start.
    public var openingTime: Double = 60
    /// How close to an app's arrival the app in front hiding or quitting counts as macOS handing
    /// focus over. macOS can report it a moment before or after.
    public var handoffTime: Double = 2
    /// How long to wait before the follow-up. Short enough that a key pressed by then was almost
    /// certainly typed before you'd noticed the switch.
    public var followUpDelay: Double = 0.4
    /// This app's own process. Its windows can be in front, but they're never logged.
    public let ownPID: ProcessID?
    public private(set) var log: FocusLog

    private struct Front: Sendable {
        var pid: ProcessID
        var app: AppInfo
        var since: Date
        var isLauncher: Bool
        /// Nil for the app that was in front when tracking started, and for this app.
        var verdict: Verdict?
        var eventID: UUID?
        /// Whether you clicked or typed while it was in front.
        var touched: Bool
        /// For an app that came back: whether it came back to being the app you were using.
        var backToYours = false
    }

    private enum LaunchOrigin: Sendable {
        /// A click, shortcut or launcher just before.
        case you
        /// A plain keypress just before: Return on a command that opens it, or just typing.
        case keypress
        case unknown
    }

    private struct Launch: Sendable {
        var date: Date
        var origin: LaunchOrigin
    }

    private struct Pending: Sendable {
        var previousPID: ProcessID?
        /// Whether typing straight through the switch would make it a steal.
        var typingDecides: Bool
    }

    /// Most recent first: `history[0]` is the app in front.
    private var history: [Front] = []
    private var pending: [UUID: Pending] = [:]
    private var launches: [ProcessID: Launch] = [:]
    private var departures: [ProcessID: Date] = [:]
    /// Apps that quit recently, by `AppInfo.key`, to recognize them coming back after an update.
    private var quits: [String: Date] = [:]
    /// When tracking last started. Until your first click or keypress after that, apps sorting
    /// themselves out, like at login, aren't stealing from you.
    private var trackingSince: Date?
    private static let historyLimit = 12

    public init(log: FocusLog = FocusLog(), rules: CauseRules = CauseRules(), ownPID: ProcessID? = nil) {
        self.log = log
        self.rules = rules
        self.ownPID = ownPID
    }

    /// The app in front right now, if known.
    public var frontPID: ProcessID? { history.first?.pid }

    /// The event for the app in front right now, if it was logged.
    public var frontEventID: UUID? { history.first?.eventID }

    /// Starts over from the app that's in front now, without logging it. Used at startup and when
    /// you come back to your user account.
    public mutating func start(front pid: ProcessID, app: AppInfo, at date: Date, isLauncher: Bool = false) {
        finish(at: date)
        history = [Front(pid: pid, app: app, since: date, isLauncher: isLauncher, verdict: nil, eventID: nil, touched: true)]
        launches.removeAll()
        departures.removeAll()
        trackingSince = date
    }

    /// Stops tracking: the app in front stops counting as in front. Used when quitting.
    public mutating func finish(at date: Date) {
        if let front = history.first, let id = front.eventID, log.event(id)?.heldFor == nil {
            log.close(id, heldFor: date.timeIntervalSince(front.since), next: nil, nextVerdict: nil)
        }
        history.removeAll()
    }

    /// Notes an app starting up, and whether you started it.
    public mutating func appLaunched(pid: ProcessID, at date: Date, input: InputSnapshot) {
        forgetOld(before: date)
        let origin: LaunchOrigin
        switch rules.cause(of: input.sanitized, frontIsLauncher: history.first?.isLauncher ?? false) {
        case .click, .shortcut, .gesture, .launcher: origin = .you
        case .keypress: origin = .keypress
        case .typing, .none, .systemUI, .relaunch, .startup: origin = .unknown
        }
        launches[pid] = Launch(date: date, origin: origin)
    }

    /// Notes an app hiding or quitting. macOS then brings another app forward on its own.
    ///
    /// - Parameter app: the app, if it quit rather than hid, so it can be recognized relaunching.
    public mutating func appLeft(pid: ProcessID, at date: Date, quit app: AppInfo? = nil) {
        forgetOld(before: date)
        departures[pid] = date
        launches[pid] = nil
        if let app {
            quits[app.key] = date
        }
    }

    /// Logs an app coming to the front and returns the event. Returns nil for this app's own
    /// windows, for an app that was already in front, and when there's nothing to compare it with.
    @discardableResult
    public mutating func appActivated(_ activation: Activation) -> FocusEvent? {
        forgetOld(before: activation.date)
        // Without knowing what was in front before, there's nothing to judge it against.
        guard !history.isEmpty else {
            start(front: activation.pid, app: activation.app, at: activation.date, isLauncher: activation.isLauncher)
            return nil
        }
        guard history.first?.pid != activation.pid else { return nil }
        let input = activation.input.sanitized

        if let front = history.first, !front.touched, input.interaction < activation.date.timeIntervalSince(front.since) {
            history[0].touched = true
        }

        var event: FocusEvent?
        var backToYours = false
        if activation.pid != ownPID {
            let judged = judge(activation, input: input)
            backToYours = judged.backToYours
            let launchAge = activation.launchDate.map { max(0, activation.date.timeIntervalSince($0)) }
            let logged = FocusEvent(
                date: activation.date, app: activation.app, pid: activation.pid, previous: history.first?.app,
                input: input, cause: judged.cause, verdict: judged.verdict,
                secondsSinceLaunch: launchAge.flatMap { $0 <= 600 ? $0 : nil }
            )
            if judged.typingDecides || logged.verdict == .stole || logged.verdict == .unsure {
                pending[logged.id] = Pending(previousPID: history.first?.pid, typingDecides: judged.typingDecides)
            }
            event = logged
        }

        if let front = history.first, let id = front.eventID {
            log.close(id, heldFor: activation.date.timeIntervalSince(front.since), next: activation.app, nextVerdict: event?.verdict)
        }
        if let event {
            log.append(event)
        }
        launches[activation.pid] = nil
        history.insert(
            Front(
                pid: activation.pid, app: activation.app, since: activation.date, isLauncher: activation.isLauncher,
                verdict: event?.verdict, eventID: event?.id, touched: false, backToYours: backToYours
            ),
            at: 0
        )
        if history.count > Self.historyLimit {
            history.removeLast(history.count - Self.historyLimit)
        }
        return event
    }

    /// Whether an event is waiting for `finishFollowUp`. Until then it shouldn't be announced.
    public func isPending(_ id: UUID) -> Bool {
        pending[id] != nil
    }

    /// Takes a second look at an event a moment after it happened, and returns it as it now stands.
    /// Returns nil if it wasn't waiting.
    ///
    /// - Parameters:
    ///   - keptTyping: whether a key was pressed after the app came forward. If you were typing
    ///     before and after, the keys were meant for the app you were in.
    ///   - spaceChanged: whether macOS switched Spaces around the same moment. With a recent
    ///     trackpad touch, that's you swiping to another Space or full-screen app.
    ///   - date: now, to tell which departures macOS has reported by the time of the second look.
    ///   - hasLeft: whether an app has quit or hidden by now. macOS sometimes says so only after
    ///     it has brought the next app forward.
    @discardableResult
    public mutating func finishFollowUp(
        _ id: UUID, keptTyping: Bool, spaceChanged: Bool, at date: Date, hasLeft: (ProcessID) -> Bool = { _ in false }
    ) -> FocusEvent? {
        guard let info = pending.removeValue(forKey: id), let event = log.event(id) else { return nil }
        var verdict = event.verdict
        var cause = event.cause
        var backToYours = false
        let blamed = verdict == .stole || verdict == .unsure
        if blamed, let previous = info.previousPID, hasLeft(previous) || departed(previous, near: event.date, by: date) {
            verdict = .returned
            backToYours = true
        } else if blamed, spaceChanged, event.input.gesture <= rules.gestureWindow {
            verdict = .switched
            cause = .gesture
        } else if info.typingDecides, keptTyping {
            verdict = .stole
            cause = .typing
        }
        guard verdict != event.verdict || cause != event.cause else { return event }
        if let index = history.firstIndex(where: { $0.eventID == id }) {
            history[index].verdict = verdict
            history[index].backToYours = backToYours
        }
        return log.update(id) { event in
            event.verdict = verdict
            event.cause = cause
        }
    }

    public mutating func clearLog() {
        log.removeAll()
        pending.removeAll()
        for index in history.indices {
            history[index].eventID = nil
        }
    }

    // MARK: Deciding

    private struct Judgment {
        var verdict: Verdict
        var cause: Cause
        var backToYours = false
        var typingDecides = false
    }

    private func judge(_ activation: Activation, input: InputSnapshot) -> Judgment {
        // Mission Control, Notification Center and the like open when you ask, often from a hot
        // corner or a gesture that leaves no click or keypress behind.
        if SystemApps.opensOnRequest(activation.app) {
            return Judgment(verdict: .switched, cause: .systemUI)
        }
        let cause = rules.cause(of: input, frontIsLauncher: history.first?.isLauncher ?? false)
        switch cause {
        case .click, .gesture, .launcher:
            return Judgment(verdict: .switched, cause: cause)
        case .shortcut:
            // ⌘Tab switches the instant ⌘ is let go. A modifier let go a little earlier, right after
            // a key, may be ⇧ between capitals, so whether typing carries on decides.
            let maybeShift = !input.commandKeysHeld && input.modifierChange > rules.instantModifierWindow
                && input.keyPress <= rules.modifierWindow
            return Judgment(verdict: .switched, cause: .shortcut, typingDecides: maybeShift)
        case .keypress, .typing, .none, .systemUI, .relaunch, .startup:
            break
        }
        if let launch = launches[activation.pid], activation.date.timeIntervalSince(launch.date) <= openingTime {
            switch launch.origin {
            case .you: return Judgment(verdict: .opened, cause: cause)
            // Return on a command that opens it, or typing when it happened to launch.
            case .keypress: return Judgment(verdict: .opened, cause: cause, typingDecides: true)
            case .unknown: break
            }
        }
        if isRelaunch(activation) {
            return Judgment(verdict: .opened, cause: .relaunch)
        }
        if let backToYours = returnKind(activation) {
            return Judgment(verdict: .returned, cause: cause, backToYours: backToYours)
        }
        if let since = trackingSince, input.interaction >= activation.date.timeIntervalSince(since) {
            return Judgment(verdict: .unsure, cause: .startup)
        }
        if cause == .keypress {
            return Judgment(verdict: .unsure, cause: .keypress, typingDecides: true)
        }
        return Judgment(verdict: .stole, cause: .none)
    }

    /// The same app starting again shortly after it quit, as apps do when they update themselves.
    private func isRelaunch(_ activation: Activation) -> Bool {
        guard let quit = quits[activation.app.key], let launched = activation.launchDate else { return false }
        return launched >= quit && activation.date.timeIntervalSince(quit) <= openingTime
    }

    /// Nil if the app isn't coming back. Otherwise, whether it's coming back to being the app you
    /// were using, as opposed to a thief getting focus back after a system prompt.
    private func returnKind(_ activation: Activation) -> Bool? {
        guard let front = history.first else { return nil }
        // macOS brings the next app forward when the one in front hides or quits: the app you were
        // using before it.
        if activation.previousHasLeft || departed(front.pid, near: activation.date, by: activation.date) {
            return true
        }
        if SystemApps.isInterruption(front.app) {
            // Nothing known from before it, like when this app starts while the screen is locked:
            // whatever comes next is focus being handed back.
            guard history.count > 1 else { return true }
            // Straight back after a system prompt, like a password dialog or the lock screen. Even to
            // an app that stole focus itself: it didn't take it a second time.
            if history[1].pid == activation.pid { return isYours(history[1]) }
        }
        // Back to the app you were using, past anything that grabbed focus without you touching it.
        // An app that only ever interrupted you doesn't qualify, or a thief could keep coming back.
        for entry in history where isYours(entry) {
            if entry.pid == activation.pid { return true }
            if !SystemApps.isInterruption(entry.app) { return nil }
        }
        return nil
    }

    /// Whether an app hid or quit close to `date`, as known by `now`.
    private func departed(_ pid: ProcessID, near date: Date, by now: Date) -> Bool {
        guard let left = departures[pid], left <= now else { return false }
        return abs(date.timeIntervalSince(left)) <= handoffTime
    }

    /// Whether you were using this app, as opposed to it interrupting you.
    private func isYours(_ entry: Front) -> Bool {
        switch entry.verdict {
        case nil, .switched, .opened: true
        case .returned: entry.backToYours || entry.touched
        case .stole, .unsure: entry.touched
        }
    }

    private mutating func forgetOld(before date: Date) {
        let cutoff = date.addingTimeInterval(-max(openingTime, handoffTime) - 1)
        launches = launches.filter { $0.value.date >= cutoff }
        departures = departures.filter { $0.value >= cutoff }
        quits = quits.filter { $0.value >= cutoff }
    }
}
