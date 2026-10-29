import Foundation
import Testing
@testable import FocusCore

@Suite("Log")
struct FocusLogTests {
    @Test func dropsTheOldestOnceFull() {
        var log = FocusLog(limit: 2)
        let events = (0..<3).map { Fixture.event(Fixture.updater, at: Double($0)) }
        events.forEach { log.append($0) }
        #expect(log.events == Array(events.suffix(2)))
    }

    @Test func startingFullKeepsTheNewest() {
        let events = (0..<5).map { Fixture.event(Fixture.updater, at: Double($0)) }
        #expect(FocusLog(events: events, limit: 3).events == Array(events.suffix(3)))
        #expect(FocusLog(events: events, limit: 0).limit == 1)
    }

    @Test func updatesInPlace() throws {
        var log = FocusLog()
        let event = Fixture.event(Fixture.updater, at: 0)
        log.append(event)
        let changed = try #require(log.update(event.id) { $0.verdict = .returned })
        #expect(changed.verdict == .returned)
        #expect(log.events.first?.verdict == .returned)
        #expect(log.update(UUID()) { $0.verdict = .stole } == nil)
    }

    @Test func closingRecordsWhatCameNext() throws {
        var log = FocusLog()
        let event = Fixture.event(Fixture.updater, at: 0, from: Fixture.xcode)
        log.append(event)
        log.close(event.id, heldFor: -1, next: Fixture.xcode, nextVerdict: .switched)
        let closed = try #require(log.event(event.id))
        #expect(closed.heldFor == 0)
        #expect(closed.youWentBack)
    }

    @Test func stealsAreNewestFirstWithoutIgnoredApps() {
        let log = FocusLog(events: [
            Fixture.event(Fixture.updater, at: 0),
            Fixture.event(Fixture.notes, at: 1, verdict: .switched, cause: .click),
            Fixture.event(Fixture.meetings, at: 2),
            Fixture.event(Fixture.loginWindow, at: 3),
        ])
        #expect(log.steals().map(\.app) == [Fixture.loginWindow, Fixture.meetings, Fixture.updater])
        #expect(log.steals(ignoring: SystemApps.ignoredByDefault).map(\.app) == [Fixture.meetings, Fixture.updater])
        #expect(log.steals(since: Fixture.start.addingTimeInterval(2)).map(\.app) == [Fixture.loginWindow, Fixture.meetings])
    }

    @Test func offendersAreRankedByCountThenRecency() throws {
        let log = FocusLog(events: [
            Fixture.event(Fixture.meetings, at: 0, from: Fixture.notes),
            Fixture.event(Fixture.updater, at: 1, from: Fixture.xcode),
            Fixture.event(Fixture.updater, at: 2, from: Fixture.xcode),
            Fixture.event(Fixture.updater, at: 3, from: Fixture.notes),
            Fixture.event(Fixture.securityAgent, at: 4, from: Fixture.xcode),
            Fixture.event(Fixture.notes, at: 5, verdict: .switched, cause: .click),
        ])
        let offenders = log.offenders()
        #expect(offenders.map(\.app) == [Fixture.updater, Fixture.securityAgent, Fixture.meetings])
        let top = try #require(offenders.first)
        #expect(top.count == 3)
        #expect(top.lastDate == Fixture.start.addingTimeInterval(3))
        #expect(top.usualVictim == Fixture.xcode)
    }

    @Test func offendersLeaveOutIgnoredAppsAndOldSteals() {
        let log = FocusLog(events: [
            Fixture.event(Fixture.updater, at: 0),
            Fixture.event(Fixture.meetings, at: 10),
        ])
        #expect(log.offenders(ignoring: [Fixture.meetings.key]).map(\.app) == [Fixture.updater])
        #expect(log.offenders(since: Fixture.start.addingTimeInterval(5)).map(\.app) == [Fixture.meetings])
    }

    @Test func offendersWithEqualCountsAndTimesSortByName() {
        let a = AppInfo(name: "Alpha", bundleID: "a")
        let b = AppInfo(name: "beta", bundleID: "b")
        let log = FocusLog(events: [Fixture.event(b, at: 0), Fixture.event(a, at: 0)])
        #expect(log.offenders().map(\.app.name) == ["Alpha", "beta"])
    }

    @Test func offenderUsesItsNewestName() {
        var renamed = Fixture.updater
        renamed.name = "SyncHelper 2"
        let log = FocusLog(events: [Fixture.event(Fixture.updater, at: 0), Fixture.event(renamed, at: 1)])
        #expect(log.offenders().first?.app.name == "SyncHelper 2")
        #expect(log.offenders().first?.count == 2)
    }
}

@Suite("Log file")
struct LogFileTests {
    @Test func roundTrips() throws {
        var event = Fixture.event(Fixture.updater, at: 0.25, from: Fixture.xcode, heldFor: 1.5)
        event.input = InputSnapshot(click: 1, keyPress: 2, modifierChange: 3, gesture: 4, commandKeysHeld: true)
        event.next = Fixture.xcode
        event.nextVerdict = .switched
        event.secondsSinceLaunch = 3
        let log = FocusLog(events: [event, Fixture.event(Fixture.notes, at: 1, verdict: .opened)])
        #expect(try LogFile.decode(LogFile.encode(log)) == log)
    }

    @Test func refusesAFileFromANewerVersion() {
        let data = Data(#"{"version": 99, "events": []}"#.utf8)
        #expect(throws: LogFile.ReadError.newerVersion(99)) { try LogFile.decode(data) }
    }

    @Test func refusesGarbage() {
        #expect(throws: (any Error).self) { try LogFile.decode(Data("not json".utf8)) }
        #expect(throws: (any Error).self) { try LogFile.decode(Data(#"{"events": []}"#.utf8)) }
    }

    @Test func appliesTheLimitWhenReading() throws {
        let log = FocusLog(events: (0..<10).map { Fixture.event(Fixture.updater, at: Double($0)) })
        #expect(try LogFile.decode(LogFile.encode(log), limit: 4).events.count == 4)
    }

    @Test func readsAFileWrittenByVersionOne() throws {
        // A saved file as 0.1.0 writes it, so later changes to the format can't break old logs.
        let json = """
        {"version":1,"events":[{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","date":1800000000,
        "app":{"name":"SyncHelper","bundleID":"com.example.sync.helper"},"pid":103,
        "previous":{"name":"Xcode","bundleID":"com.apple.dt.Xcode","path":"/Applications/Xcode.app"},
        "input":{"click":60,"keyPress":0.1,"modifierChange":60,"gesture":60,"commandKeysHeld":false},
        "cause":"typing","verdict":"stole","heldFor":2}]}
        """
        let event = try #require(LogFile.decode(Data(json.utf8)).events.first)
        #expect(event.app.name == "SyncHelper")
        #expect(event.cause == .typing)
        #expect(event.verdict == .stole)
        #expect(event.heldFor == 2)
        #expect(event.next == nil)
    }
}
