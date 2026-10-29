import Foundation

/// What happened when an app came to the front.
public enum Verdict: String, Codable, CaseIterable, Sendable {
    /// It came forward on its own: no click, shortcut or swipe just before, or you kept typing
    /// straight through it.
    case stole
    /// Right after a click, shortcut, swipe or launcher.
    case switched
    /// Its first trip to the front after you opened it.
    case opened
    /// Focus went back to it after the app in front quit, hid or was a system prompt.
    case returned
    /// Right after a plain keypress, and you stopped typing. Maybe you pressed Return on something
    /// that opens it, maybe not, so it isn't counted as a steal.
    case unsure
}

/// One app coming to the front.
public struct FocusEvent: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var date: Date
    public var app: AppInfo
    public var pid: ProcessID
    /// The app that was in front before.
    public var previous: AppInfo?
    public var input: InputSnapshot
    public var cause: Cause
    public var verdict: Verdict
    /// How long ago the app launched, when that was in the last ten minutes.
    public var secondsSinceLaunch: Double?
    /// How long it stayed in front. Nil while it's still there.
    public var heldFor: Double?
    /// What came to the front after it.
    public var next: AppInfo?
    public var nextVerdict: Verdict?

    public init(
        id: UUID = UUID(), date: Date, app: AppInfo, pid: ProcessID, previous: AppInfo?,
        input: InputSnapshot, cause: Cause, verdict: Verdict, secondsSinceLaunch: Double? = nil,
        heldFor: Double? = nil, next: AppInfo? = nil, nextVerdict: Verdict? = nil
    ) {
        self.id = id
        self.date = date
        self.app = app
        self.pid = pid
        self.previous = previous
        self.input = input
        self.cause = cause
        self.verdict = verdict
        self.secondsSinceLaunch = secondsSinceLaunch
        self.heldFor = heldFor
        self.next = next
        self.nextVerdict = nextVerdict
    }

    /// Whether it stayed in front only until you went straight back to the app it took focus from.
    public var youWentBack: Bool {
        guard let previous, let next else { return false }
        return next.key == previous.key && nextVerdict == .switched
    }
}
