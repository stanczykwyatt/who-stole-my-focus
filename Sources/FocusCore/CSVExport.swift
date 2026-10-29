import Foundation

/// The log as CSV, for spreadsheets and bug reports.
public enum CSVExport {
    public static let header = [
        "Time", "App", "Part Of", "Bundle ID", "Path", "Took Focus From", "What Happened", "Why",
        "Seconds Since Input", "Seconds In Front",
    ]

    /// Events in the order given, one row each, with a header row. Times are ISO 8601 with the
    /// time zone offset, so they sort correctly and convert anywhere. Paths in `home` are shortened
    /// to "~", so a shared file doesn't include your username.
    public static func csv(_ events: [FocusEvent], timeZone: TimeZone = .current, home: String? = nil) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = timeZone
        formatter.formatOptions = [.withInternetDateTime]
        var lines = [header.map(field).joined(separator: ",")]
        for event in events {
            let row = [
                formatter.string(from: event.date),
                event.app.name,
                event.app.containingAppName ?? "",
                event.app.bundleID ?? "",
                event.app.path.map { Describe.path($0, home: home) } ?? "",
                event.previous?.name ?? "",
                Describe.verdict(event.verdict),
                event.cause.rawValue,
                number(event.input.latest),
                event.heldFor.map(number) ?? "",
            ]
            lines.append(row.map(field).joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// Quotes a field when needed. App names come from other apps, so a name that starts like a
    /// formula gets a leading apostrophe and opens in a spreadsheet as plain text.
    static func field(_ value: String) -> String {
        var value = value
        if let first = value.unicodeScalars.first, "=+-@\t\r".unicodeScalars.contains(first) {
            value = "'" + value
        }
        // Scalars, not Characters: "\r\n" is a single Character in Swift and wouldn't match either.
        let needsQuotes = value.unicodeScalars.contains { "\",\n\r".unicodeScalars.contains($0) }
            || value.first == " " || value.last == " "
        guard needsQuotes else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    private static func number(_ value: Double) -> String {
        String(format: "%.1f", value)
    }
}
