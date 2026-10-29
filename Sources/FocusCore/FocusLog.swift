import Foundation

/// Every app that came to the front, oldest first, up to a limit.
public struct FocusLog: Equatable, Sendable {
    public static let defaultLimit = 5_000

    public private(set) var events: [FocusEvent]
    public let limit: Int

    public init(events: [FocusEvent] = [], limit: Int = FocusLog.defaultLimit) {
        self.limit = max(1, limit)
        self.events = Array(events.suffix(self.limit))
    }

    /// Adds an event, dropping the oldest once the log is full.
    public mutating func append(_ event: FocusEvent) {
        events.append(event)
        if events.count > limit {
            events.removeFirst(events.count - limit)
        }
    }

    public func event(_ id: UUID) -> FocusEvent? {
        events.last { $0.id == id }
    }

    /// Changes an event in place. Returns the changed event, or nil if it has been dropped.
    @discardableResult
    public mutating func update(_ id: UUID, _ change: (inout FocusEvent) -> Void) -> FocusEvent? {
        // Nearly always the newest event or the one before, so search from the end.
        guard let index = events.lastIndex(where: { $0.id == id }) else { return nil }
        change(&events[index])
        return events[index]
    }

    /// Records how long an app stayed in front, once the next one comes forward or tracking stops.
    public mutating func close(_ id: UUID, heldFor: Double, next: AppInfo?, nextVerdict: Verdict?) {
        update(id) { event in
            event.heldFor = max(0, heldFor)
            event.next = next
            event.nextVerdict = nextVerdict
        }
    }

    public mutating func removeAll() {
        events.removeAll()
    }
}

// MARK: Steals and offenders

/// An app that keeps stealing focus.
public struct Offender: Hashable, Identifiable, Sendable {
    /// As it was the last time it stole focus.
    public var app: AppInfo
    public var count: Int
    public var lastDate: Date
    /// The app it took focus from most often.
    public var usualVictim: AppInfo?

    public var id: String { app.key }
}

extension FocusLog {
    /// Steals, newest first, leaving out apps you've chosen to ignore.
    public func steals(ignoring ignored: Set<String> = [], since start: Date? = nil) -> [FocusEvent] {
        events.reversed().filter { event in
            event.verdict == .stole && !ignored.contains(event.app.key) && start.map { event.date >= $0 } != false
        }
    }

    /// Apps ranked by how often they stole focus: most steals first, then the most recent.
    public func offenders(ignoring ignored: Set<String> = [], since start: Date? = nil) -> [Offender] {
        struct Tally {
            var offender: Offender
            var victims: [String: (app: AppInfo, count: Int)] = [:]
        }
        var tallies: [String: Tally] = [:]
        for event in events where event.verdict == .stole && !ignored.contains(event.app.key) {
            if let start, event.date < start { continue }
            var tally = tallies[event.app.key] ?? Tally(offender: Offender(app: event.app, count: 0, lastDate: event.date))
            tally.offender.app = event.app
            tally.offender.count += 1
            tally.offender.lastDate = max(tally.offender.lastDate, event.date)
            if let victim = event.previous {
                let seen = tally.victims[victim.key]?.count ?? 0
                tally.victims[victim.key] = (victim, seen + 1)
            }
            tallies[event.app.key] = tally
        }
        return tallies.values.map { tally in
            var offender = tally.offender
            offender.usualVictim = tally.victims.values.max { a, b in
                a.count != b.count ? a.count < b.count : a.app.name > b.app.name
            }?.app
            return offender
        }.sorted { a, b in
            if a.count != b.count { return a.count > b.count }
            if a.lastDate != b.lastDate { return a.lastDate > b.lastDate }
            return a.app.name.localizedStandardCompare(b.app.name) == .orderedAscending
        }
    }
}

// MARK: Saving

/// The log as it's saved to disk: versioned JSON, so a newer app's file is never misread.
public enum LogFile {
    public static let version = 1

    public enum ReadError: Error, Equatable {
        /// Written by a newer version of the app.
        case newerVersion(Int)
    }

    private struct Envelope: Codable {
        var version: Int
        var events: [FocusEvent]
    }

    public static func encode(_ log: FocusLog) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        return try encoder.encode(Envelope(version: version, events: log.events))
    }

    public static func decode(_ data: Data, limit: Int = FocusLog.defaultLimit) throws -> FocusLog {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        struct VersionOnly: Decodable { var version: Int }
        let found = try decoder.decode(VersionOnly.self, from: data).version
        guard found <= version else { throw ReadError.newerVersion(found) }
        return FocusLog(events: try decoder.decode(Envelope.self, from: data).events, limit: limit)
    }
}
