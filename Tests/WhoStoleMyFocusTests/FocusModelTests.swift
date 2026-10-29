import FocusCore
import Foundation
import Testing
@testable import WhoStoleMyFocus

@MainActor
@Suite("Model")
struct FocusModelTests {
    private func activation(_ app: AppInfo, pid: ProcessID, at offset: TimeInterval, input: InputSnapshot) -> Activation {
        Activation(pid: pid, app: app, date: Sample.start.addingTimeInterval(offset), input: input)
    }

    private let idle = InputSnapshot(click: 60, keyPress: 60, modifierChange: 60, gesture: 60)

    @Test func stealsAreCountedUntilSeen() throws {
        let model = FocusModel(store: nil, preferences: scratchPreferences(), ownPID: nil)
        var stolen: [FocusEvent] = []
        model.onSteal = { stolen.append($0) }
        model.start(front: 1, app: Sample.xcode, at: Sample.start.addingTimeInterval(-3600), isLauncher: false)
        let event = try #require(model.appActivated(activation(Sample.syncHelper, pid: 2, at: 5, input: idle)))
        // Every steal gets a second look before it's announced.
        #expect(model.unseenSteals == 0)
        model.finishFollowUp(event.id, keptTyping: false, spaceChanged: false, at: Sample.start)
        #expect(model.unseenSteals == 1)
        #expect(stolen.map(\.app) == [Sample.syncHelper])
        model.markSeen()
        #expect(model.unseenSteals == 0)
    }

    @Test func ignoredAppsArentCountedOrAnnounced() throws {
        let model = FocusModel(store: nil, preferences: scratchPreferences(), ownPID: nil)
        var stolen = 0
        model.onSteal = { _ in stolen += 1 }
        model.ignore(Sample.syncHelper)
        model.start(front: 1, app: Sample.xcode, at: Sample.start.addingTimeInterval(-3600), isLauncher: false)
        let event = try #require(model.appActivated(activation(Sample.syncHelper, pid: 2, at: 5, input: idle)))
        model.finishFollowUp(event.id, keptTyping: false, spaceChanged: false, at: Sample.start)
        #expect(stolen == 0)
        #expect(model.unseenSteals == 0)
        #expect(model.steals().isEmpty)
        #expect(model.log.events.count == 1)
    }

    @Test func followUpCanTurnAnEventIntoASteal() throws {
        let model = FocusModel(store: nil, preferences: scratchPreferences(), ownPID: nil)
        var stolen = 0
        model.onSteal = { _ in stolen += 1 }
        model.start(front: 1, app: Sample.xcode, at: Sample.start.addingTimeInterval(-3600), isLauncher: false)
        let event = try #require(model.appActivated(activation(
            Sample.syncHelper, pid: 2, at: 5, input: InputSnapshot(click: 60, keyPress: 0.1, modifierChange: 60, gesture: 60)
        )))
        #expect(stolen == 0)
        model.finishFollowUp(event.id, keptTyping: true, spaceChanged: false, at: Sample.start)
        #expect(stolen == 1)
        #expect(model.steals().count == 1)
    }

    @Test func possibleSwipeIsntAnnouncedUntilSettled() throws {
        let model = FocusModel(store: nil, preferences: scratchPreferences(), ownPID: nil)
        var stolen = 0
        model.onSteal = { _ in stolen += 1 }
        model.start(front: 1, app: Sample.xcode, at: Sample.start.addingTimeInterval(-3600), isLauncher: false)
        let event = try #require(model.appActivated(activation(
            Sample.syncHelper, pid: 2, at: 5, input: InputSnapshot(click: 60, keyPress: 60, modifierChange: 60, gesture: 0.2)
        )))
        #expect(model.isPending(event.id))
        #expect(stolen == 0)
        #expect(model.unseenSteals == 0)
        model.finishFollowUp(event.id, keptTyping: false, spaceChanged: false, at: Sample.start)
        #expect(stolen == 1)
    }

    @Test func settingsAreSaved() {
        let preferences = scratchPreferences()
        let model = FocusModel(store: nil, preferences: preferences, ownPID: nil)
        model.threshold = 3
        model.notifies = true
        model.ignore(Sample.meetings)
        model.stopIgnoring("com.apple.loginwindow")

        let reopened = FocusModel(store: nil, preferences: preferences, ownPID: nil)
        #expect(reopened.threshold == 3)
        #expect(reopened.notifies)
        #expect(reopened.ignored == ["com.example.meetings", "com.apple.ScreenSaver.Engine"])
    }

    @Test func thresholdChangesDetection() {
        let model = FocusModel(store: nil, preferences: scratchPreferences(), ownPID: nil)
        model.threshold = 0.5
        model.start(front: 1, app: Sample.xcode, at: Sample.start.addingTimeInterval(-3600), isLauncher: false)
        let event = model.appActivated(activation(Sample.notes, pid: 2, at: 5, input: InputSnapshot(click: 1, keyPress: 60, modifierChange: 60, gesture: 60)))
        #expect(event?.verdict == .stole)
    }

    @Test func logSurvivesARestart() throws {
        let store = LogStore(url: scratchFolder().appendingPathComponent("log.json"))
        let model = FocusModel(store: store, preferences: scratchPreferences(), ownPID: nil)
        model.start(front: 1, app: Sample.xcode, at: Sample.start.addingTimeInterval(-3600), isLauncher: false)
        model.appActivated(activation(Sample.syncHelper, pid: 2, at: 5, input: idle))
        model.flush(at: Sample.start.addingTimeInterval(65))

        let reopened = FocusModel(store: store, preferences: scratchPreferences(), ownPID: nil)
        #expect(reopened.log.events.map(\.app) == [Sample.syncHelper])
        // Quitting closed it, so it doesn't stay "Still in front" forever.
        #expect(reopened.log.events.first?.heldFor == 60)
    }

    @Test func changesAreSavedAfterAShortWait() async throws {
        let store = LogStore(url: scratchFolder().appendingPathComponent("log.json"))
        let model = FocusModel(store: store, preferences: scratchPreferences(), ownPID: nil)
        model.saveDelay = .milliseconds(20)
        model.start(front: 1, app: Sample.xcode, at: Sample.start.addingTimeInterval(-3600), isLauncher: false)
        model.appActivated(activation(Sample.syncHelper, pid: 2, at: 5, input: idle))
        #expect(store.load().events.isEmpty)
        // Other tests can hold the main thread for a moment, so wait up to a few seconds.
        for _ in 0..<100 where store.load().events.isEmpty {
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(store.load().events.count == 1)
    }

    @Test func clearingEmptiesTheLog() {
        let model = model(with: [Sample.steal(Sample.syncHelper, from: Sample.xcode, at: Sample.start)])
        #expect(model.log.events.count == 1)
        model.clearLog()
        #expect(model.log.events.isEmpty)
        #expect(model.unseenSteals == 0)
    }

    @Test func ignoredAppsHaveReadableNames() {
        let model = model(with: [Sample.steal(Sample.syncHelper, from: Sample.xcode, at: Sample.start)])
        model.ignore(Sample.syncHelper)
        model.ignored.insert("com.example.never-seen")
        #expect(model.ignoredApps.map(\.name) == [
            "com.example.never-seen", "Lock screen (loginwindow)", "Screen saver (ScreenSaverEngine)", "SyncHelper (CloudSync)",
        ])
    }
}

@Suite("Saving")
struct LogStoreTests {
    @Test func missingFileIsAnEmptyLog() {
        #expect(LogStore(url: scratchFolder().appendingPathComponent("log.json")).load().events.isEmpty)
    }

    @Test func roundTripsAndCreatesItsFolder() throws {
        let url = scratchFolder().appendingPathComponent("nested/folder/log.json")
        let store = LogStore(url: url)
        let log = FocusLog(events: [Sample.steal(Sample.syncHelper, from: Sample.xcode, at: Sample.start)])
        try store.save(log)
        #expect(store.load() == log)
    }

    @Test(arguments: ["not json at all", #"{"version": 2, "events": []}"#])
    func unreadableFilesAreMovedAsideNotOverwritten(contents: String) throws {
        let folder = scratchFolder()
        let url = folder.appendingPathComponent("log.json")
        try Data(contents.utf8).write(to: url)
        let store = LogStore(url: url)
        #expect(store.load().events.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: url.path))
        let aside = try FileManager.default.contentsOfDirectory(atPath: folder.path).filter { $0.hasPrefix("log-unreadable-") }
        #expect(aside.count == 1)
        #expect(try String(contentsOf: folder.appendingPathComponent(aside[0]), encoding: .utf8) == contents)
    }

    @Test func defaultLocationIsInApplicationSupport() {
        #expect(LogStore.defaultURL.path.hasSuffix("Application Support/Who Stole My Focus/log.json"))
    }
}

@Suite("Preferences")
struct PreferencesTests {
    @Test func defaults() {
        let preferences = scratchPreferences()
        #expect(preferences.threshold == CauseRules.defaultThreshold)
        #expect(!preferences.notifies)
        #expect(preferences.ignored == SystemApps.ignoredByDefault)
        #expect(!preferences.launchedBefore)
    }

    @Test func onlyOfferedThresholdsAreAccepted() {
        let preferences = scratchPreferences()
        preferences.threshold = 2
        #expect(preferences.threshold == 2)
        preferences.defaults.set(17.0, forKey: "threshold")
        #expect(preferences.threshold == CauseRules.defaultThreshold)
    }

    @Test func ignoringNothingIsRemembered() {
        let preferences = scratchPreferences()
        preferences.ignored = []
        #expect(preferences.ignored.isEmpty)
    }
}
