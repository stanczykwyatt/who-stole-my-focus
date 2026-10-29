import Foundation
import Testing
@testable import FocusCore

@Suite("Steals")
struct StealTests {
    @Test func appComingForwardWhileYouAreIdleStealsFocus() throws {
        let scenario = Scenario()
        let event = try #require(scenario.activate(Fixture.updater, input: Fixture.idle))
        #expect(event.verdict == .stole)
        #expect(event.cause == .none)
        #expect(event.previous == Fixture.xcode)
        #expect(scenario.events == [event])
    }

    @Test func typingStraightThroughASwitchIsASteal() throws {
        let scenario = Scenario()
        let event = try #require(scenario.activate(Fixture.updater, input: Fixture.typed(0.15)))
        #expect(event.verdict == .unsure)
        #expect(scenario.isPending(event.id))

        let settled = try #require(scenario.finishFollowUp(event.id, keptTyping: true))
        #expect(settled.verdict == .stole)
        #expect(settled.cause == .typing)
        #expect(scenario.events.last?.verdict == .stole)
        #expect(!scenario.isPending(event.id))
    }

    @Test func stoppingAfterAKeypressStaysUnsure() throws {
        let scenario = Scenario()
        let event = try #require(scenario.activate(Fixture.updater, input: Fixture.typed(0.4)))
        #expect(scenario.finishFollowUp(event.id, keptTyping: false)?.verdict == .unsure)
        #expect(!scenario.isPending(event.id))
    }

    @Test func clearSwitchesNeedNoFollowUp() throws {
        let scenario = Scenario()
        let event = try #require(scenario.activate(Fixture.notes, input: Fixture.clicked(0.1)))
        #expect(!scenario.isPending(event.id))
        #expect(scenario.finishFollowUp(event.id, keptTyping: true) == nil)
        #expect(scenario.events.last?.verdict == .switched)
    }

    @Test func followUpOnlyHappensOnce() throws {
        let scenario = Scenario()
        let event = try #require(scenario.activate(Fixture.updater, input: Fixture.typed(0.1)))
        #expect(scenario.finishFollowUp(event.id) != nil)
        #expect(scenario.finishFollowUp(event.id, keptTyping: true) == nil)
        #expect(scenario.events.last?.verdict == .unsure)
    }

    @Test func followUpForAnEventThatWasClearedDoesNothing() throws {
        let scenario = Scenario()
        let event = try #require(scenario.activate(Fixture.updater, input: Fixture.typed(0.1)))
        scenario.tracker.clearLog()
        #expect(scenario.finishFollowUp(event.id, keptTyping: true) == nil)
        #expect(scenario.events.isEmpty)
    }

    @Test func swipingToAnotherSpaceIsYours() throws {
        let scenario = Scenario()
        let event = try #require(scenario.activate(Fixture.notes, input: Fixture.touchedTrackpad(0.3)))
        #expect(scenario.isPending(event.id))
        let settled = try #require(scenario.finishFollowUp(event.id, spaceChanged: true))
        #expect(settled.verdict == .switched)
        #expect(settled.cause == .gesture)
    }

    @Test func touchingTheTrackpadWithoutASpaceChangeIsStillASteal() throws {
        let scenario = Scenario()
        let event = try #require(scenario.activate(Fixture.updater, input: Fixture.touchedTrackpad(0.2)))
        #expect(event.verdict == .stole)
        #expect(scenario.isPending(event.id))
        #expect(scenario.finishFollowUp(event.id)?.verdict == .stole)
    }

    @Test func spaceChangeWithoutATrackpadTouchIsntASwipe() throws {
        // An app on another Space jumping forward makes macOS switch Spaces too.
        let scenario = Scenario()
        let event = try #require(scenario.activate(Fixture.updater, input: Fixture.typed(0.1)))
        #expect(scenario.finishFollowUp(event.id, keptTyping: true, spaceChanged: true)?.verdict == .stole)
    }

    @Test func everyStealGetsASecondLookBeforeItsAnnounced() throws {
        let scenario = Scenario()
        let event = try #require(scenario.activate(Fixture.updater, input: Fixture.touchedTrackpad(5)))
        #expect(scenario.isPending(event.id))
        #expect(scenario.finishFollowUp(event.id, spaceChanged: true)?.verdict == .stole)
    }

    @Test func quitReportedJustAfterTheSwitchIsAHandoff() throws {
        // macOS can bring the next app forward before it says the last one quit.
        let scenario = Scenario()
        scenario.activate(Fixture.notes, input: Fixture.clicked(0.1))
        let event = try #require(scenario.activate(Fixture.meetings, after: 30))
        #expect(event.verdict == .stole)
        scenario.leave(Fixture.notes, after: 0.1)
        #expect(scenario.finishFollowUp(event.id)?.verdict == .returned)
    }

    @Test func appThatHasLeftByTheSecondLookHandedFocusOver() throws {
        let scenario = Scenario()
        scenario.activate(Fixture.notes, input: Fixture.clicked(0.1))
        let event = try #require(scenario.activate(Fixture.meetings, after: 30))
        #expect(scenario.finishFollowUp(event.id, left: [Fixture.notes])?.verdict == .returned)
    }

    @Test func modifierLetGoRightAfterAKeyCouldBeShift() throws {
        // ⇧ released between capitals looks like the end of ⌘Tab, so typing on decides.
        let scenario = Scenario()
        let input = InputSnapshot(click: 60, keyPress: 0.25, modifierChange: 0.2, gesture: 60)
        let event = try #require(scenario.activate(Fixture.updater, input: input))
        #expect(event.verdict == .switched)
        #expect(scenario.isPending(event.id))
        #expect(scenario.finishFollowUp(event.id, keptTyping: true)?.verdict == .stole)
    }

    @Test func modifierLetGoAtTheSwitchIsCommandTab() throws {
        let scenario = Scenario()
        let event = try #require(scenario.activate(Fixture.notes, input: Fixture.commandTab))
        #expect(!scenario.isPending(event.id))
    }

    @Test func movingThePointerOverAThiefDoesntMakeItYours() throws {
        let scenario = Scenario()
        scenario.activate(Fixture.updater)
        // Pointer moved over its window five seconds ago: a gesture, but not a click or keypress.
        var input = Fixture.idle
        input.gesture = 5
        input.modifierChange = 60
        #expect(scenario.activate(Fixture.xcode, after: 30, input: input)?.verdict == .returned)
    }

    @Test func appThatLaunchedItselfAndJumpedForwardStealsFocus() throws {
        let scenario = Scenario()
        scenario.launch(Fixture.updater, input: Fixture.idle)
        let event = try #require(scenario.activate(Fixture.updater, after: 2, launchedAgo: 2))
        #expect(event.verdict == .stole)
        #expect(event.secondsSinceLaunch == 2)
    }

    @Test func launchesLongAgoArentMentioned() throws {
        let scenario = Scenario()
        let event = try #require(scenario.activate(Fixture.updater, launchedAgo: 3600))
        #expect(event.secondsSinceLaunch == nil)
    }
}

@Suite("Switches you made")
struct SwitchTests {
    @Test func clickJustBeforeIsYours() throws {
        let scenario = Scenario()
        let event = try #require(scenario.activate(Fixture.notes, input: Fixture.clicked(0.08)))
        #expect(event.verdict == .switched)
        #expect(event.cause == .click)
    }

    @Test func commandTabIsYours() throws {
        let scenario = Scenario()
        let event = try #require(scenario.activate(Fixture.notes, input: Fixture.commandTab))
        #expect(event.verdict == .switched)
        #expect(event.cause == .shortcut)
    }

    @Test func returnInALauncherIsYours() throws {
        let scenario = Scenario()
        scenario.activate(Fixture.launcher, input: Fixture.commandTab, launcher: true)
        let event = try #require(scenario.activate(Fixture.notes, input: Fixture.typed(0.2)))
        #expect(event.verdict == .switched)
        #expect(event.cause == .launcher)
    }

    @Test func thresholdChangesWhatCountsAsYours() throws {
        let scenario = Scenario(rules: CauseRules(threshold: 3))
        #expect(scenario.activate(Fixture.notes, input: Fixture.clicked(2.5))?.verdict == .switched)

        let strict = Scenario(rules: CauseRules(threshold: 0.5))
        #expect(strict.activate(Fixture.notes, input: Fixture.clicked(1))?.verdict == .stole)
    }

    @Test func thresholdCanChangeWhileRunning() throws {
        let scenario = Scenario()
        scenario.tracker.rules.threshold = 0.5
        #expect(scenario.activate(Fixture.notes, input: Fixture.clicked(1))?.verdict == .stole)
    }
}

@Suite("Apps you opened")
struct OpenTests {
    @Test func appLaunchedWhileYouTypeIsStillCheckedForTyping() throws {
        let scenario = Scenario()
        scenario.launch(Fixture.updater, input: Fixture.typed(0.1))
        let event = try #require(scenario.activate(Fixture.updater, after: 3, input: Fixture.typed(0.1)))
        #expect(event.verdict == .opened)
        #expect(scenario.isPending(event.id))
        #expect(scenario.finishFollowUp(event.id, keptTyping: true)?.verdict == .stole)
    }

    @Test func commandThatOpensAnAppIsYours() throws {
        // Return on `code .` in Terminal, then waiting for the editor to come up.
        let scenario = Scenario()
        scenario.launch(Fixture.meetings, input: Fixture.typed(0.1))
        let event = try #require(scenario.activate(Fixture.meetings, after: 3))
        #expect(scenario.finishFollowUp(event.id, keptTyping: false)?.verdict == .opened)
    }

    @Test func appRelaunchingAfterAnUpdateIsntAThief() throws {
        let scenario = Scenario()
        scenario.activate(Fixture.meetings, input: Fixture.clicked(0.1))
        scenario.activate(Fixture.xcode, input: Fixture.clicked(0.1))
        scenario.leave(Fixture.meetings, quitting: true, after: 5)
        let event = try #require(scenario.activate(Fixture.meetings, after: 12, launchedAgo: 3))
        #expect(event.verdict == .opened)
        #expect(event.cause == .relaunch)
    }

    @Test func relaunchLongAfterQuittingIsJudgedNormally() throws {
        let scenario = Scenario()
        scenario.leave(Fixture.meetings, quitting: true, after: 5)
        #expect(scenario.activate(Fixture.meetings, after: 120, launchedAgo: 3)?.verdict == .stole)
    }

    @Test func appYouOpenedIsntBlamedForTakingAWhile() throws {
        let scenario = Scenario()
        scenario.launch(Fixture.meetings, input: Fixture.clicked(0.1))
        let event = try #require(scenario.activate(Fixture.meetings, after: 12, launchedAgo: 12))
        #expect(event.verdict == .opened)
    }

    @Test func openingFromALauncherCounts() throws {
        let scenario = Scenario()
        scenario.activate(Fixture.launcher, input: Fixture.commandTab, launcher: true)
        scenario.launch(Fixture.meetings, input: Fixture.typed(0.1))
        #expect(scenario.activate(Fixture.meetings, after: 5)?.verdict == .opened)
    }

    @Test func onlyTheFirstTripToTheFrontCounts() throws {
        let scenario = Scenario()
        scenario.launch(Fixture.meetings, input: Fixture.clicked(0.1))
        scenario.activate(Fixture.meetings, after: 3)
        scenario.activate(Fixture.xcode, input: Fixture.clicked(0.1))
        scenario.activate(Fixture.notes, input: Fixture.clicked(0.1))
        #expect(scenario.activate(Fixture.meetings)?.verdict == .stole)
    }

    @Test func openingTimeRunsOut() throws {
        let scenario = Scenario()
        scenario.launch(Fixture.meetings, input: Fixture.clicked(0.1))
        #expect(scenario.activate(Fixture.meetings, after: 61)?.verdict == .stole)
    }

    @Test func appThatQuitIsForgotten() throws {
        let scenario = Scenario()
        scenario.launch(Fixture.meetings, input: Fixture.clicked(0.1))
        scenario.leave(Fixture.meetings, after: 1)
        #expect(scenario.activate(Fixture.meetings, after: 5)?.verdict == .stole)
    }
}

@Suite("Focus coming back")
struct ReturnTests {
    @Test func focusGoingBackAfterAStealIsntASecondSteal() throws {
        let scenario = Scenario()
        let theft = try #require(scenario.activate(Fixture.updater))
        let back = try #require(scenario.activate(Fixture.xcode, after: 0.6))
        #expect(back.verdict == .returned)

        let closed = try #require(scenario.tracker.log.event(theft.id))
        #expect(abs(try #require(closed.heldFor) - 0.6) < 0.001)
        #expect(closed.next == Fixture.xcode)
        #expect(closed.nextVerdict == .returned)
    }

    @Test func goingBackYourselfIsNoted() throws {
        let scenario = Scenario()
        let theft = try #require(scenario.activate(Fixture.updater))
        scenario.activate(Fixture.xcode, after: 2, input: Fixture.clicked(0.1))
        #expect(scenario.tracker.log.event(theft.id)?.youWentBack == true)
    }

    @Test func thiefThatKeepsComingBackStealsEachTime() throws {
        let scenario = Scenario()
        #expect(scenario.activate(Fixture.updater)?.verdict == .stole)
        #expect(scenario.activate(Fixture.xcode)?.verdict == .returned)
        #expect(scenario.activate(Fixture.updater)?.verdict == .stole)
        #expect(scenario.activate(Fixture.xcode)?.verdict == .returned)
        #expect(scenario.tracker.log.steals().count == 2)
    }

    @Test func backPastSeveralInterruptions() throws {
        let scenario = Scenario()
        scenario.activate(Fixture.updater)
        scenario.activate(Fixture.meetings)
        #expect(scenario.activate(Fixture.xcode)?.verdict == .returned)
    }

    @Test func backToYourAppAfterItAlreadyCameBackOnce() throws {
        let scenario = Scenario()
        scenario.activate(Fixture.updater)
        scenario.activate(Fixture.xcode)
        scenario.activate(Fixture.meetings)
        #expect(scenario.activate(Fixture.xcode)?.verdict == .returned)
    }

    @Test func anAppYouStartedUsingIsYoursEvenIfItStoleFocus() throws {
        let scenario = Scenario()
        scenario.activate(Fixture.updater)
        // You typed into it for a while, so the next app is interrupting it, not you.
        #expect(scenario.activate(Fixture.xcode, after: 30, input: Fixture.typed(5))?.verdict == .stole)
    }

    @Test func appYouSwitchedAwayFromDoesntGetToComeBackOnItsOwn() throws {
        let scenario = Scenario()
        scenario.activate(Fixture.notes, input: Fixture.clicked(0.1))
        #expect(scenario.activate(Fixture.xcode, after: 20)?.verdict == .stole)
    }

    @Test func afterAPasswordPromptFocusGoesBackWithoutBlame() throws {
        let scenario = Scenario()
        #expect(scenario.activate(Fixture.updater)?.verdict == .stole)
        #expect(scenario.activate(Fixture.securityAgent)?.verdict == .stole)
        // You typed your password, then waited for it to be checked.
        #expect(scenario.activate(Fixture.updater, after: 8, input: Fixture.typed(3))?.verdict == .returned)
        #expect(scenario.activate(Fixture.xcode)?.verdict == .returned)
    }

    @Test func unlockingWithTouchIDGoesBackToYourApp() throws {
        let scenario = Scenario()
        scenario.activate(Fixture.loginWindow, after: 300)
        #expect(scenario.activate(Fixture.xcode, after: 600)?.verdict == .returned)
    }

    @Test func startingWhileTheScreenIsLockedDoesntBlameTheAppThatComesBack() throws {
        // Seen for real: the app started at login with the lock screen in front, and the app
        // that came back after unlocking was logged as a steal.
        let scenario = Scenario(front: Fixture.loginWindow)
        #expect(scenario.activate(Fixture.xcode, after: 400)?.verdict == .returned)
        #expect(scenario.activate(Fixture.updater)?.verdict == .stole)
    }

    @Test func somethingElseJumpingInAfterUnlockingStillSteals() throws {
        let scenario = Scenario()
        scenario.activate(Fixture.loginWindow, after: 300)
        #expect(scenario.activate(Fixture.updater, after: 600)?.verdict == .stole)
    }

    @Test func appThatQuitHandsFocusToTheNextApp() throws {
        let scenario = Scenario()
        scenario.activate(Fixture.notes, input: Fixture.clicked(0.1))
        #expect(scenario.activate(Fixture.meetings, after: 40, previousHasLeft: true)?.verdict == .returned)
    }

    @Test func hideNoticedJustBeforeCounts() throws {
        let scenario = Scenario()
        scenario.activate(Fixture.notes, input: Fixture.clicked(0.1))
        scenario.leave(Fixture.notes, after: 10)
        #expect(scenario.activate(Fixture.meetings, after: 0.2)?.verdict == .returned)
    }

    @Test func hideLongBeforeDoesntCount() throws {
        let scenario = Scenario()
        scenario.activate(Fixture.notes, input: Fixture.clicked(0.1))
        scenario.leave(Fixture.notes, after: 10)
        #expect(scenario.activate(Fixture.meetings, after: 5)?.verdict == .stole)
    }

    @Test func startingOverForgetsWhoWasInFront() throws {
        let scenario = Scenario()
        scenario.activate(Fixture.updater)
        scenario.tracker.start(front: Fixture.pid(Fixture.notes), app: Fixture.notes, at: scenario.clock.addingTimeInterval(-3600))
        #expect(scenario.activate(Fixture.xcode)?.verdict == .stole)
    }
}

@Suite("Parts of macOS")
struct SystemTests {
    @Test(arguments: SystemApps.onRequest.sorted())
    func systemScreensYouOpenNeverSteal(bundleID: String) throws {
        // Hot corners and gestures open these without a click or keypress.
        let scenario = Scenario()
        let app = AppInfo(name: bundleID, bundleID: bundleID)
        let event = try #require(scenario.activate(app))
        #expect(event.verdict == .switched)
        #expect(event.cause == .systemUI)
        #expect(!scenario.isPending(event.id))
    }

    @Test func leavingMissionControlForAnotherAppIsYours() throws {
        let scenario = Scenario()
        scenario.activate(AppInfo(name: "Dock", bundleID: "com.apple.dock"))
        #expect(scenario.activate(Fixture.notes, input: Fixture.clicked(0.1))?.verdict == .switched)
    }
}

@Suite("Starting up")
struct StartupTests {
    @Test func appsSortingThemselvesOutAtLoginArentSteals() throws {
        let tracker = Scenario(front: Fixture.notes)
        // Starts now, with nothing clicked or typed since.
        tracker.tracker.start(front: Fixture.pid(Fixture.notes), app: Fixture.notes, at: tracker.clock)
        let event = try #require(tracker.activate(Fixture.updater, after: 4, input: Fixture.idle))
        #expect(event.verdict == .unsure)
        #expect(event.cause == .startup)
        // Once you've clicked, steals count again.
        #expect(tracker.activate(Fixture.meetings, after: 20, input: Fixture.idle.with(click: 10))?.verdict == .stole)
    }

    @Test func firstAppWithNothingInFrontJustStartsTracking() {
        var tracker = FocusTracker()
        #expect(tracker.appActivated(Activation(pid: 1, app: Fixture.xcode, date: Fixture.start, input: Fixture.idle)) == nil)
        #expect(tracker.frontPID == 1)
        #expect(tracker.log.events.isEmpty)
    }

    @Test func quittingClosesTheEventInFront() throws {
        let scenario = Scenario()
        let event = try #require(scenario.activate(Fixture.notes, input: Fixture.clicked(0.1)))
        scenario.tracker.finish(at: scenario.clock.addingTimeInterval(30))
        #expect(scenario.tracker.log.event(event.id)?.heldFor == 30)
        #expect(scenario.tracker.frontEventID == nil)
    }

    @Test func startingOverClosesTheEventInFront() throws {
        let scenario = Scenario()
        let event = try #require(scenario.activate(Fixture.notes, input: Fixture.clicked(0.1)))
        #expect(scenario.tracker.frontEventID == event.id)
        scenario.tracker.start(front: 1, app: Fixture.xcode, at: scenario.clock.addingTimeInterval(10))
        #expect(scenario.tracker.log.event(event.id)?.heldFor == 10)
    }
}

@Suite("Bookkeeping")
struct BookkeepingTests {
    @Test func ownWindowIsNeverLogged() throws {
        let scenario = Scenario()
        #expect(scenario.activate(Fixture.own, input: Fixture.clicked(0.1)) == nil)
        #expect(scenario.events.isEmpty)
        let back = try #require(scenario.activate(Fixture.xcode, input: Fixture.clicked(0.1)))
        #expect(back.previous == Fixture.own)
        #expect(back.verdict == .switched)
    }

    @Test func ownWindowClosesTheEventBeforeIt() throws {
        let scenario = Scenario()
        let theft = try #require(scenario.activate(Fixture.updater))
        scenario.activate(Fixture.own, after: 4, input: Fixture.clicked(0.1))
        let closed = try #require(scenario.tracker.log.event(theft.id))
        #expect(closed.heldFor == 4)
        #expect(closed.next == Fixture.own)
        #expect(closed.nextVerdict == nil)
    }

    @Test func appAlreadyInFrontIsIgnored() throws {
        let scenario = Scenario()
        #expect(scenario.activate(Fixture.xcode) == nil)
        #expect(scenario.events.isEmpty)
    }

    @Test func lastEventStaysOpen() throws {
        let scenario = Scenario()
        let event = try #require(scenario.activate(Fixture.notes, input: Fixture.clicked(0.1)))
        #expect(scenario.tracker.log.event(event.id)?.heldFor == nil)
    }

    @Test func clearingTheLogDoesntBringEventsBack() throws {
        let scenario = Scenario()
        scenario.activate(Fixture.updater)
        scenario.tracker.clearLog()
        let next = try #require(scenario.activate(Fixture.notes, input: Fixture.clicked(0.1)))
        #expect(scenario.events == [next])
    }

    @Test func logLimitHolds() throws {
        let scenario = Scenario(limit: 3)
        for index in 0..<10 {
            scenario.activate(index.isMultiple(of: 2) ? Fixture.notes : Fixture.xcode, input: Fixture.clicked(0.1))
        }
        #expect(scenario.events.count == 3)
    }

    @Test func oddInputTimesAreClamped() throws {
        let scenario = Scenario()
        let event = try #require(scenario.activate(
            Fixture.updater, input: InputSnapshot(click: .nan, keyPress: -4, modifierChange: .infinity, gesture: 1e12)
        ))
        #expect(event.input.click == InputSnapshot.longest)
        #expect(event.input.keyPress == 0)
        #expect(event.input.modifierChange == InputSnapshot.longest)
        #expect(event.input.gesture == InputSnapshot.longest)
    }

    @Test func frontIsTracked() {
        let scenario = Scenario()
        #expect(scenario.tracker.frontPID == Fixture.pid(Fixture.xcode))
        scenario.activate(Fixture.notes, input: Fixture.clicked(0.1))
        #expect(scenario.tracker.frontPID == Fixture.pid(Fixture.notes))
    }

    @Test func longSessionsKeepWorking() throws {
        let scenario = Scenario()
        // Thirty seconds apart, with your last input a minute ago: you never touch the thief.
        for round in 0..<200 {
            scenario.activate(round.isMultiple(of: 2) ? Fixture.updater : Fixture.xcode, after: 30)
        }
        #expect(scenario.tracker.log.steals().count == 100)
        #expect(scenario.events.filter { $0.verdict == .returned }.count == 100)
    }
}
