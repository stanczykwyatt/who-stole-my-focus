import Foundation

/// The words the menu, the log window, notifications and the CSV use for events.
public enum Describe {
    public static func verdict(_ verdict: Verdict) -> String {
        switch verdict {
        case .stole: "Stole focus"
        case .switched: "You switched"
        case .opened: "You opened it"
        case .returned: "Came back"
        case .unsure: "Not sure"
        }
    }

    /// The app's name, plus the app it ships inside when that's different, so helpers make sense.
    public static func name(_ app: AppInfo) -> String {
        app.containingAppName.map { "\(app.name) (\($0))" } ?? app.name
    }

    /// One line saying what happened, like "Zoom stole focus from Xcode".
    public static func headline(_ event: FocusEvent) -> String {
        let app = name(event.app)
        switch (event.verdict, event.cause) {
        case (.stole, _):
            return event.previous.map { "\(app) stole focus from \(name($0))" } ?? "\(app) stole focus"
        case (.switched, _):
            return "You switched to \(app)"
        case (.opened, .relaunch):
            return "\(app) came back after relaunching"
        case (.opened, _):
            return "You opened \(app)"
        case (.returned, _):
            return "\(app) came back to the front"
        case (.unsure, .keypress):
            return "\(app) came forward right after a keypress"
        case (.unsure, .startup):
            return "\(app) came forward before you'd clicked or typed"
        case (.unsure, _):
            return "\(app) came forward"
        }
    }

    /// Why it was judged that way.
    public static func reason(_ event: FocusEvent) -> String {
        switch (event.verdict, event.cause) {
        case (.opened, .relaunch):
            return "Started again soon after it quit, as apps do when they update themselves"
        case (.opened, _):
            let wait = event.secondsSinceLaunch.map { " \(duration($0)) after" } ?? " after"
            return "Came to the front\(wait) you opened it"
        case (.returned, _):
            return event.previous.map { "Focus went back to it after \(name($0))" } ?? "Focus went back to it"
        default:
            break
        }
        switch event.cause {
        case .click:
            return "\(duration(event.input.click)) after a click"
        case .shortcut:
            return "Right after a keyboard shortcut"
        case .gesture:
            return "Right after a trackpad swipe to another Space"
        case .launcher:
            return event.previous.map { "After you typed in \(name($0))" } ?? "After you typed in a launcher"
        case .systemUI:
            return "Part of macOS that opens when you ask for it, so it's never counted"
        case .keypress:
            return "\(duration(event.input.keyPress)) after a keypress, then you stopped typing. If you pressed Return to open it, that was you."
        case .typing:
            return "While you were typing: it came forward between your keystrokes"
        case .startup:
            return "Before your first click or keypress since Who Stole My Focus started, like at login"
        case .relaunch:
            return "Started again soon after it quit"
        case .none:
            var line = "No click or keypress for \(duration(event.input.latest))"
            if let launched = event.secondsSinceLaunch, launched <= 60 {
                line += ", \(duration(launched)) after it launched by itself"
            }
            return line
        }
    }

    /// A few words of the reason, for a table cell: "No input for 41 s", "Between your keystrokes".
    public static func shortReason(_ event: FocusEvent) -> String {
        switch (event.verdict, event.cause) {
        case (.opened, .relaunch):
            return "Relaunched after quitting"
        case (.opened, _):
            return event.secondsSinceLaunch.map { "\(duration($0)) after you opened it" } ?? "After you opened it"
        case (.returned, _):
            return event.previous.map { "Back after \(name($0))" } ?? "Focus went back to it"
        default:
            break
        }
        switch event.cause {
        case .click: return "\(duration(event.input.click)) after a click"
        case .shortcut: return "After a shortcut"
        case .gesture: return "After a swipe"
        case .launcher: return event.previous.map { "After typing in \(name($0))" } ?? "After typing in a launcher"
        case .systemUI: return "Opened from macOS"
        case .keypress: return "\(duration(event.input.keyPress)) after a keypress"
        case .typing: return "Between your keystrokes"
        case .startup: return "Before your first input"
        case .relaunch: return "Relaunched after quitting"
        case .none: return "No input for \(duration(event.input.latest))"
        }
    }

    /// What happened next, like "In front for 2 s, then you went back to Xcode".
    ///
    /// - Parameter isCurrent: whether it's the app in front right now. One that never got a time,
    ///   because the app stopped unexpectedly, isn't.
    public static func aftermath(_ event: FocusEvent, isCurrent: Bool = true) -> String {
        guard let held = event.heldFor else {
            return isCurrent ? "Still in front" : "In front until Who Stole My Focus stopped watching"
        }
        let stay = "In front for \(duration(held))"
        if event.youWentBack, let previous = event.previous {
            return "\(stay), then you went back to \(name(previous))"
        }
        if let next = event.next, event.nextVerdict == .returned {
            return "\(stay), until \(name(next)) came back"
        }
        return stay
    }

    /// Plain words for parts of macOS with cryptic names, like "SecurityAgent".
    public static func systemNote(_ app: AppInfo) -> String? {
        SystemApps.description(for: app).map { "\(app.name) is \($0)." }
    }

    /// A path with your home folder shortened to "~", so shared details don't include your username.
    public static func path(_ path: String, home: String?) -> String {
        guard let home, !home.isEmpty else { return path }
        let folder = home.hasSuffix("/") ? String(home.dropLast()) : home
        if path == folder { return "~" }
        return path.hasPrefix(folder + "/") ? "~" + path.dropFirst(folder.count) : path
    }

    /// Everything about one event, for pasting into a bug report to the app's developer.
    public static func details(_ event: FocusEvent, date: String, home: String? = nil, isCurrent: Bool = true) -> String {
        var lines = [headline(event), date, reason(event), aftermath(event, isCurrent: isCurrent)]
        if let note = systemNote(event.app) {
            lines.append(note)
        }
        lines.append("App: \(event.app.name)" + (event.app.bundleID.map { " (\($0))" } ?? ""))
        if let path = event.app.path {
            lines.append("Path: \(Self.path(path, home: home))")
        }
        return lines.joined(separator: "\n")
    }

    /// A short duration: "0.4 s", "41 s", "3 min 5 s", "2 h 10 min", "3 days".
    public static func duration(_ seconds: Double) -> String {
        guard seconds.isFinite else { return "a long time" }
        let seconds = max(0, seconds)
        if seconds < 9.95 {
            let tenths = (seconds * 10).rounded() / 10
            return tenths == tenths.rounded() ? "\(Int(tenths)) s" : String(format: "%.1f s", tenths)
        }
        let whole = Int(seconds.rounded())
        if whole < 60 { return "\(whole) s" }
        if whole < 3600 {
            let rest = whole % 60
            return rest == 0 ? "\(whole / 60) min" : "\(whole / 60) min \(rest) s"
        }
        if whole < 86_400 {
            let minutes = (whole % 3600) / 60
            return minutes == 0 ? "\(whole / 3600) h" : "\(whole / 3600) h \(minutes) min"
        }
        let days = whole / 86_400
        return days == 1 ? "1 day" : "\(days) days"
    }

    /// When something happened, relative to now: "just now", "5 min ago", "yesterday at 3:41 PM".
    public static func relative(_ date: Date, now: Date, calendar: Calendar = .current, locale: Locale = .current) -> String {
        if let recent = recent(date, now: now) { return recent }
        let parts = DateParts(date, now: now, calendar: calendar, locale: locale)
        if parts.isToday { return "at \(parts.time)" }
        if parts.isYesterday { return "yesterday at \(parts.time)" }
        return "\(parts.day) at \(parts.time)"
    }

    /// The same, shorter, for a table column: "5 min ago", "3:41 PM", "Yesterday 3:41 PM", "Oct 27, 3:41 PM".
    public static func compactTime(_ date: Date, now: Date, calendar: Calendar = .current, locale: Locale = .current) -> String {
        if let recent = recent(date, now: now) { return recent }
        let parts = DateParts(date, now: now, calendar: calendar, locale: locale)
        if parts.isToday { return parts.time }
        if parts.isYesterday { return "Yesterday \(parts.time)" }
        return "\(parts.day), \(parts.time)"
    }

    private static func recent(_ date: Date, now: Date) -> String? {
        let elapsed = now.timeIntervalSince(date)
        if elapsed < 10 { return "just now" }
        if elapsed < 60 { return "\(Int(elapsed)) s ago" }
        if elapsed < 3600 { return "\(Int(elapsed / 60)) min ago" }
        return nil
    }

    private struct DateParts {
        var time: String
        var day: String
        var isToday: Bool
        var isYesterday: Bool

        init(_ date: Date, now: Date, calendar: Calendar, locale: Locale) {
            let formatter = DateFormatter()
            formatter.locale = locale
            formatter.calendar = calendar
            formatter.timeZone = calendar.timeZone
            formatter.dateStyle = .none
            formatter.timeStyle = .short
            time = formatter.string(from: date)
            let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
            formatter.setLocalizedDateFormatFromTemplate(sameYear ? "MMMd" : "MMMdyyyy")
            day = formatter.string(from: date)
            isToday = calendar.isDate(date, inSameDayAs: now)
            isYesterday = calendar.date(byAdding: .day, value: -1, to: now).map { calendar.isDate(date, inSameDayAs: $0) } ?? false
        }
    }
}
