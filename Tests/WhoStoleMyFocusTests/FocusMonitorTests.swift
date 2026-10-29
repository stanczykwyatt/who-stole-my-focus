import AppKit
import FocusCore
import Testing
@testable import WhoStoleMyFocus

/// The monitor, fed notifications on a private center. Nothing here activates or changes a real app.
@MainActor
@Suite("Monitor", .enabled(if: Sample.desktopIsRunning, "Needs Finder and the Dock, which every logged-in Mac runs"))
final class FocusMonitorTests {
    let center = NotificationCenter()
    let clock = FakeClock()
    var now = Sample.start
    var front: NSRunningApplication? = Sample.dock
    var running: Set<ProcessID> = [Sample.finder.processIdentifier, Sample.dock.processIdentifier, Sample.me.processIdentifier]
    var pending: [@MainActor () -> Void] = []
    let model = FocusModel(store: nil, preferences: scratchPreferences(), ownPID: nil)
    lazy var monitor = FocusMonitor(
        model: model, center: center, clock: clock,
        now: { [unowned self] in now },
        frontmost: { [unowned self] in front },
        lookup: { [unowned self] pid in
            running.contains(pid) ? NSRunningApplication(processIdentifier: pid) : nil
        },
        schedule: { [unowned self] _, work in pending.append(work) }
    )

    private func post(_ name: Notification.Name, _ app: NSRunningApplication?, after seconds: TimeInterval = 1) {
        now = now.addingTimeInterval(seconds)
        center.post(name: name, object: nil, userInfo: app.map { [NSWorkspace.applicationUserInfoKey: $0] })
    }

    private func startMonitor() {
        monitor.start()
        now = now.addingTimeInterval(120)
    }

    /// Runs the pending follow-up, as the real scheduler would a moment later.
    private func followUp(after seconds: TimeInterval = 0.4) throws {
        let check = try #require(pending.first)
        pending.removeFirst()
        now = now.addingTimeInterval(seconds)
        check()
    }

    private func activate(_ app: NSRunningApplication, after seconds: TimeInterval = 1) {
        post(NSWorkspace.didActivateApplicationNotification, app, after: seconds)
    }

    @Test func logsAnAppComingForwardWithWhatWasInFront() throws {
        startMonitor()
        clock.input.click = 0.1
        activate(Sample.finder)
        let event = try #require(model.log.events.last)
        #expect(event.app.bundleID == "com.apple.finder")
        #expect(event.app.path == "/System/Library/CoreServices/Finder.app")
        #expect(event.previous?.bundleID == "com.apple.dock")
        #expect(event.verdict == .switched)
        #expect(event.date == now)
    }

    @Test func idleArrivalIsASteal() throws {
        var stolen: [FocusEvent] = []
        model.onSteal = { stolen.append($0) }
        // From Finder: anything coming forward after the Dock, a system screen, counts as a return.
        front = Sample.finder
        startMonitor()
        activate(Sample.me, after: 5)
        #expect(model.log.events.last?.verdict == .stole)
        #expect(stolen.isEmpty)
        try followUp()
        #expect(stolen.count == 1)
        #expect(model.unseenSteals == 1)
    }

    @Test func typingThroughTheSwitchBecomesASteal() throws {
        // Finder, not the Dock: typing in the Dock's Launchpad and pressing Return opens apps,
        // so a keypress there counts as yours.
        front = Sample.finder
        startMonitor()
        clock.input.keyPress = 0.1
        activate(Sample.me)
        #expect(model.log.events.last?.verdict == .unsure)
        #expect(pending.count == 1)

        clock.input.keyPress = 0.2 // a key pressed after the switch
        try followUp()
        #expect(model.log.events.last?.verdict == .stole)
        #expect(model.log.events.last?.cause == .typing)
    }

    @Test func stoppingAfterTheKeypressStaysUnsure() throws {
        front = Sample.finder
        startMonitor()
        clock.input.keyPress = 0.3
        activate(Sample.me)
        clock.input.keyPress = 1.0 // nothing since
        try followUp()
        #expect(model.log.events.last?.verdict == .unsure)
    }

    @Test func shortcutAimedAtTheNewAppIsntTyping() throws {
        front = Sample.finder
        startMonitor()
        clock.input.keyPress = 0.1
        activate(Sample.me)
        // ⌘T in the app that just came forward: a key after the switch, with ⌘ still held.
        clock.input.keyPress = 0.1
        clock.input.commandKeysHeld = true
        try followUp()
        #expect(model.log.events.last?.verdict == .unsure)
    }

    @Test func lateFollowUpCantTellTyping() throws {
        front = Sample.finder
        startMonitor()
        clock.input.keyPress = 0.1
        activate(Sample.me)
        clock.input.keyPress = 0.2
        // Ran seconds late, so a key pressed by now could be ordinary typing in the new app.
        try followUp(after: 4)
        #expect(model.log.events.last?.verdict == .unsure)
    }

    @Test func quitReportedAfterTheSwitchHandsFocusOver() throws {
        front = Sample.finder
        startMonitor()
        activate(Sample.me, after: 30)
        #expect(model.log.events.last?.verdict == .stole)
        // Finder's quit only reported now.
        running.remove(Sample.finder.processIdentifier)
        try followUp()
        #expect(model.log.events.last?.verdict == .returned)
        #expect(model.unseenSteals == 0)
    }

    @Test func keypressInAMenuBarAppOrLauncherIsYours() {
        startMonitor()
        clock.input.keyPress = 0.2
        activate(Sample.finder)
        #expect(model.log.events.last?.verdict == .switched)
        #expect(model.log.events.last?.cause == .launcher)
        #expect(pending.isEmpty)
    }

    @Test func swipeToAnotherSpaceIsYours() throws {
        front = Sample.finder
        startMonitor()
        clock.input.gesture = 0.2
        post(NSWorkspace.activeSpaceDidChangeNotification, nil, after: 1)
        activate(Sample.me, after: 0.1)
        try followUp()
        #expect(model.log.events.last?.verdict == .switched)
        #expect(model.log.events.last?.cause == .gesture)
        #expect(model.unseenSteals == 0)
    }

    @Test func spaceChangeLongBeforeDoesntExcuseAnApp() throws {
        front = Sample.finder
        startMonitor()
        clock.input.gesture = 0.2
        post(NSWorkspace.activeSpaceDidChangeNotification, nil, after: 1)
        activate(Sample.me, after: 5)
        try followUp()
        #expect(model.log.events.last?.verdict == .stole)
        #expect(model.unseenSteals == 1)
    }

    @Test func clicksNeverNeedATypingCheck() {
        startMonitor()
        clock.input.click = 0.1
        activate(Sample.finder)
        #expect(pending.isEmpty)
    }

    @Test func appYouLaunchedIsOpenedNotStolen() {
        startMonitor()
        clock.input.click = 0.1
        post(NSWorkspace.willLaunchApplicationNotification, Sample.finder)
        clock.input.click = 9
        activate(Sample.finder, after: 8)
        #expect(model.log.events.last?.verdict == .opened)
    }

    @Test func appThatQuitHandsFocusOver() {
        front = Sample.finder
        startMonitor()
        running.remove(Sample.finder.processIdentifier)
        activate(Sample.me, after: 30)
        #expect(model.log.events.last?.verdict == .returned)
    }

    @Test func hideNotificationHandsFocusOver() {
        front = Sample.finder
        startMonitor()
        post(NSWorkspace.didHideApplicationNotification, Sample.finder, after: 30)
        activate(Sample.me, after: 0.1)
        #expect(model.log.events.last?.verdict == .returned)
    }

    @Test func nothingIsLoggedWhileYouAreInAnotherAccount() {
        startMonitor()
        post(NSWorkspace.sessionDidResignActiveNotification, nil)
        activate(Sample.finder, after: 60)
        #expect(model.log.events.isEmpty)

        front = Sample.finder
        post(NSWorkspace.sessionDidBecomeActiveNotification, nil, after: 60)
        clock.input.click = 0.1
        activate(Sample.me)
        #expect(model.log.events.count == 1)
        #expect(model.log.events.last?.previous?.bundleID == "com.apple.finder")
    }

    @Test func notificationsWithoutAnAppAreIgnored() {
        startMonitor()
        post(NSWorkspace.didActivateApplicationNotification, nil)
        #expect(model.log.events.isEmpty)
    }

    @Test func stoppingRemovesEveryObserver() {
        startMonitor()
        monitor.stop()
        activate(Sample.finder)
        #expect(model.log.events.isEmpty)
    }

    @Test func startingTwiceDoesntDoubleLog() {
        monitor.start()
        startMonitor()
        clock.input.click = 0.1
        activate(Sample.finder)
        #expect(model.log.events.count == 1)
    }

    @Test func appInfoFromARunningApp() {
        let info = AppInfo(Sample.finder)
        #expect(info.name == "Finder")
        #expect(info.bundleID == "com.apple.finder")
        #expect(info.path == "/System/Library/CoreServices/Finder.app")
    }

    @Test func realClockGivesSaneTimes() {
        let input = SystemInputClock().snapshot()
        for value in [input.click, input.keyPress, input.modifierChange, input.gesture] {
            #expect(value >= 0)
            #expect(!value.isNaN)
        }
    }
}
