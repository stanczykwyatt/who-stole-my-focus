import Testing
@testable import FocusCore

@Suite("Causes")
struct CauseRulesTests {
    let rules = CauseRules()

    @Test func clickJustBefore() {
        #expect(rules.cause(of: Fixture.clicked(0.1), frontIsLauncher: false) == .click)
    }

    @Test func slowLinkOpenStillCountsAsTheClick() {
        #expect(rules.cause(of: Fixture.clicked(1.4), frontIsLauncher: false) == .click)
    }

    @Test func clickThenTypingIsTypingNotTheClick() {
        let input = InputSnapshot(click: 1.0, keyPress: 0.1, modifierChange: 60, gesture: 60)
        #expect(rules.cause(of: input, frontIsLauncher: false) == .keypress)
    }

    @Test func commandTab() {
        #expect(rules.cause(of: Fixture.commandTab, frontIsLauncher: false) == .shortcut)
    }

    @Test func heldHotKey() {
        var input = Fixture.typed(0.05)
        input.commandKeysHeld = true
        #expect(rules.cause(of: input, frontIsLauncher: false) == .shortcut)
    }

    @Test func modifierLetGoTooLongAgoDoesntCount() {
        let input = InputSnapshot(click: 60, keyPress: 2, modifierChange: 0.9, gesture: 60)
        #expect(rules.cause(of: input, frontIsLauncher: false) == .none)
    }

    @Test func shiftPressedBeforeTheLastKeyIsJustTyping() {
        let input = InputSnapshot(click: 60, keyPress: 0.1, modifierChange: 0.3, gesture: 60)
        #expect(rules.cause(of: input, frontIsLauncher: false) == .keypress)
    }

    @Test func returnInALauncher() {
        #expect(rules.cause(of: Fixture.typed(0.2), frontIsLauncher: true) == .launcher)
    }

    @Test func trackpadTouchAloneIsntACause() {
        // Moving the pointer counts as a gesture, so a swipe is only decided once the Space changes.
        let input = InputSnapshot(click: 60, keyPress: 3, modifierChange: 60, gesture: 0.1)
        #expect(rules.cause(of: input, frontIsLauncher: false) == .none)
    }

    @Test func nothingRecent() {
        #expect(rules.cause(of: Fixture.idle, frontIsLauncher: false) == .none)
        #expect(rules.cause(of: .none, frontIsLauncher: true) == .none)
    }

    @Test func thresholdIsInclusive() {
        #expect(rules.cause(of: Fixture.clicked(1.5), frontIsLauncher: false) == .click)
        #expect(rules.cause(of: Fixture.clicked(1.51), frontIsLauncher: false) == .none)
    }

    @Test func thresholdChoicesIncludeTheDefault() {
        #expect(CauseRules.thresholdChoices.contains(CauseRules.defaultThreshold))
        #expect(CauseRules.thresholdChoices == CauseRules.thresholdChoices.sorted())
    }

    @Test func latestLeavesOutTrackpadTouches() {
        let input = InputSnapshot(click: 4, keyPress: 2, modifierChange: 9, gesture: 1)
        #expect(input.latest == 2)
        #expect(InputSnapshot(click: 4, keyPress: 6, modifierChange: 3, gesture: 1).latest == 3)
    }

    @Test func interactionIsClicksAndKeys() {
        #expect(InputSnapshot(click: 4, keyPress: 6, modifierChange: 1, gesture: 0.5).interaction == 4)
    }

    @Test func sanitizingClampsOddValues() {
        let input = InputSnapshot(click: -1, keyPress: .nan, modifierChange: 5, gesture: .infinity, commandKeysHeld: true).sanitized
        #expect(input == InputSnapshot(click: 0, keyPress: InputSnapshot.longest, modifierChange: 5, gesture: InputSnapshot.longest, commandKeysHeld: true))
    }
}
