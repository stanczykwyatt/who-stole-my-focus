import Foundation
import Testing
@testable import FocusCore

@Suite("Wording")
struct DescribeTests {
    @Test(arguments: [
        (0.0, "0 s"), (0.04, "0 s"), (0.43, "0.4 s"), (2.0, "2 s"), (2.96, "3 s"), (9.94, "9.9 s"),
        (9.96, "10 s"), (41.4, "41 s"), (59.4, "59 s"), (59.6, "1 min"), (65.0, "1 min 5 s"),
        (3599.6, "1 h"), (3600.0, "1 h"), (7380.0, "2 h 3 min"), (86_400.0, "1 day"),
        (3 * 86_400.0, "3 days"), (-1.0, "0 s"), (Double.infinity, "a long time"),
    ])
    func durations(seconds: Double, expected: String) {
        #expect(Describe.duration(seconds) == expected)
    }

    @Test func relativeTimes() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let locale = Locale(identifier: "en_US_POSIX")
        let now = Fixture.start // Friday, Jan 15 2027, 08:00 UTC
        func relative(_ offset: TimeInterval) -> String {
            // Date formatting puts a narrow no-break space before AM and PM.
            Describe.relative(now.addingTimeInterval(-offset), now: now, calendar: calendar, locale: locale)
                .replacingOccurrences(of: "\u{202F}", with: " ")
        }
        #expect(relative(3) == "just now")
        #expect(relative(42) == "42 s ago")
        #expect(relative(600) == "10 min ago")
        #expect(relative(3 * 3600) == "at 5:00 AM")
        #expect(relative(9 * 3600) == "yesterday at 11:00 PM")
        #expect(relative(3 * 86_400) == "Jan 12 at 8:00 AM")
        #expect(relative(30 * 86_400) == "Dec 16, 2026 at 8:00 AM")
    }

    @Test func compactTimes() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let locale = Locale(identifier: "en_US_POSIX")
        let now = Fixture.start
        func compact(_ offset: TimeInterval) -> String {
            Describe.compactTime(now.addingTimeInterval(-offset), now: now, calendar: calendar, locale: locale)
                .replacingOccurrences(of: "\u{202F}", with: " ")
        }
        #expect(compact(5) == "just now")
        #expect(compact(600) == "10 min ago")
        #expect(compact(3 * 3600) == "5:00 AM")
        #expect(compact(9 * 3600) == "Yesterday 11:00 PM")
        #expect(compact(3 * 86_400) == "Jan 12, 8:00 AM")
        #expect(compact(30 * 86_400) == "Dec 16, 2026, 8:00 AM")
    }

    @Test func shortReasons() {
        var event = Fixture.event(Fixture.updater, at: 0, from: Fixture.xcode)
        event.input = InputSnapshot(click: 120, keyPress: 41, modifierChange: 300, gesture: 300)
        #expect(Describe.shortReason(event) == "No input for 41 s")
        event.cause = .typing
        #expect(Describe.shortReason(event) == "Between your keystrokes")
        event.verdict = .unsure
        event.cause = .keypress
        event.input.keyPress = 0.6
        #expect(Describe.shortReason(event) == "0.6 s after a keypress")
        event.verdict = .returned
        event.previous = Fixture.securityAgent
        #expect(Describe.shortReason(event) == "Back after SecurityAgent")
        for cause in Cause.allCases {
            event.verdict = .switched
            event.cause = cause
            #expect(Describe.shortReason(event).count < 40)
        }
    }

    @Test func headlines() {
        #expect(Describe.headline(Fixture.event(Fixture.updater, at: 0, from: Fixture.xcode)) == "SyncHelper (CloudSync) stole focus from Xcode")
        #expect(Describe.headline(Fixture.event(Fixture.updater, at: 0)) == "SyncHelper (CloudSync) stole focus")
        #expect(Describe.headline(Fixture.event(Fixture.notes, at: 0, verdict: .switched)) == "You switched to Notes")
        #expect(Describe.headline(Fixture.event(Fixture.notes, at: 0, verdict: .opened)) == "You opened Notes")
        #expect(Describe.headline(Fixture.event(Fixture.xcode, at: 0, verdict: .returned)) == "Xcode came back to the front")
        #expect(Describe.headline(Fixture.event(Fixture.notes, at: 0, verdict: .unsure, cause: .keypress)) == "Notes came forward right after a keypress")
        #expect(Describe.headline(Fixture.event(Fixture.notes, at: 0, verdict: .unsure, cause: .startup)) == "Notes came forward before you'd clicked or typed")
        #expect(Describe.headline(Fixture.event(Fixture.notes, at: 0, verdict: .opened, cause: .relaunch)) == "Notes came back after relaunching")
    }

    @Test func everyVerdictHasWords() {
        let words = Verdict.allCases.map(Describe.verdict)
        #expect(Set(words).count == Verdict.allCases.count)
        #expect(Describe.verdict(.stole) == "Stole focus")
    }

    @Test func reasons() {
        var event = Fixture.event(Fixture.updater, at: 0, from: Fixture.xcode)
        event.input = InputSnapshot(click: 120, keyPress: 41, modifierChange: 300, gesture: 300)
        #expect(Describe.reason(event) == "No click or keypress for 41 s")

        event.secondsSinceLaunch = 2
        #expect(Describe.reason(event) == "No click or keypress for 41 s, 2 s after it launched by itself")

        event.cause = .typing
        #expect(Describe.reason(event) == "While you were typing: it came forward between your keystrokes")

        event.verdict = .switched
        event.cause = .click
        event.input.click = 0.2
        #expect(Describe.reason(event) == "0.2 s after a click")

        event.cause = .launcher
        event.previous = Fixture.launcher
        #expect(Describe.reason(event) == "After you typed in Launcher")

        event.verdict = .returned
        event.previous = Fixture.securityAgent
        #expect(Describe.reason(event) == "Focus went back to it after SecurityAgent")

        event.verdict = .opened
        event.secondsSinceLaunch = 12
        #expect(Describe.reason(event) == "Came to the front 12 s after you opened it")
    }

    @Test func everyCauseHasAReason() {
        for cause in Cause.allCases {
            var event = Fixture.event(Fixture.notes, at: 0, from: Fixture.xcode)
            event.cause = cause
            event.verdict = cause == .typing || cause == .none ? .stole : .switched
            #expect(!Describe.reason(event).isEmpty)
        }
    }

    @Test func aftermath() {
        var event = Fixture.event(Fixture.updater, at: 0, from: Fixture.xcode)
        #expect(Describe.aftermath(event) == "Still in front")
        event.heldFor = 2
        event.next = Fixture.xcode
        event.nextVerdict = .switched
        #expect(Describe.aftermath(event) == "In front for 2 s, then you went back to Xcode")
        event.nextVerdict = .returned
        #expect(Describe.aftermath(event) == "In front for 2 s, until Xcode came back")
        event.next = Fixture.notes
        event.nextVerdict = .switched
        #expect(Describe.aftermath(event) == "In front for 2 s")
    }

    @Test func detailsHaveEverythingForABugReport() {
        var event = Fixture.event(Fixture.securityAgent, at: 0, from: Fixture.xcode, heldFor: 9)
        event.input = InputSnapshot(click: 75, keyPress: 75, modifierChange: 75, gesture: 75)
        let details = Describe.details(event, date: "Friday 8:00")
        #expect(details == """
        SecurityAgent stole focus from Xcode
        Friday 8:00
        No click or keypress for 1 min 15 s
        In front for 9 s
        SecurityAgent is macOS asking for your password to approve a change.
        App: SecurityAgent (com.apple.SecurityAgent)
        Path: /System/Library/Frameworks/Security.framework/Versions/A/MachServices/SecurityAgent.bundle
        """)
    }

    @Test func homeFolderIsShortened() {
        #expect(Describe.path("/Users/sam/Applications/Tool.app", home: "/Users/sam") == "~/Applications/Tool.app")
        #expect(Describe.path("/Users/sam", home: "/Users/sam/") == "~")
        #expect(Describe.path("/Users/samantha/Tool.app", home: "/Users/sam") == "/Users/samantha/Tool.app")
        #expect(Describe.path("/Applications/Tool.app", home: nil) == "/Applications/Tool.app")
        var event = Fixture.event(AppInfo(name: "Tool", path: "/Users/sam/Applications/Tool.app"), at: 0)
        event.heldFor = 1
        #expect(Describe.details(event, date: "now", home: "/Users/sam").hasSuffix("Path: ~/Applications/Tool.app"))
    }

    @Test func eventLeftOpenByACrashIsntStillInFront() {
        let event = Fixture.event(Fixture.updater, at: 0)
        #expect(Describe.aftermath(event, isCurrent: true) == "Still in front")
        #expect(Describe.aftermath(event, isCurrent: false) == "In front until Who Stole My Focus stopped watching")
    }

    @Test func namesOfHelpersIncludeTheirApp() {
        #expect(Describe.name(Fixture.updater) == "SyncHelper (CloudSync)")
        #expect(Describe.name(Fixture.xcode) == "Xcode")
    }

    @Test func systemNotes() {
        #expect(Describe.systemNote(Fixture.securityAgent) == "SecurityAgent is macOS asking for your password to approve a change.")
        #expect(Describe.systemNote(Fixture.xcode) == nil)
    }
}
