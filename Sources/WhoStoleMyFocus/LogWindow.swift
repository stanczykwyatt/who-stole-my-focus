import AppKit
import FocusCore
import SwiftUI

/// The log window: every steal, or every switch, with the worst offenders on top.
struct LogView: View {
    let model: FocusModel
    let icons: AppIcons
    /// Copies the rows being shown.
    var copyCSV: ([FocusEvent]) -> Void = { _ in }
    var clear: () -> Void = {}

    enum Filter: String, CaseIterable, Identifiable {
        case steals = "Steals"
        case everything = "Everything"
        var id: Self { self }
    }

    @State var filter: Filter = .steals
    @State private var selection: Set<FocusEvent.ID> = []

    private var rows: [FocusEvent] {
        switch filter {
        case .steals: model.steals()
        case .everything: model.log.events.reversed()
        }
    }

    var body: some View {
        // Redraws every half minute so "2 min ago" doesn't go stale while the window is open.
        TimelineView(.periodic(from: .now, by: 30)) { context in
            VStack(spacing: 0) {
                header(now: context.date)
                Divider()
                if rows.isEmpty {
                    emptyState
                } else {
                    table(now: context.date)
                }
                Divider()
                footer
            }
        }
        .frame(minWidth: 760, minHeight: 360)
        // The window draws this anyway; drawing it here too keeps off-screen renders right in dark mode.
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: Parts

    private func header(now: Date) -> some View {
        HStack(alignment: .center, spacing: 10) {
            let offenders = model.offenders()
            if offenders.isEmpty {
                Label("No steals yet", systemImage: "checkmark.seal")
                    .foregroundStyle(.secondary)
            } else {
                Text("Top offenders")
                    .font(.headline)
                ForEach(offenders.prefix(4)) { offender in
                    OffenderChip(offender: offender, icon: icons.icon(for: offender.app, size: 22), now: now)
                }
            }
            Spacer(minLength: 12)
            Picker("Show", selection: $filter) {
                ForEach(Filter.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func table(now: Date) -> some View {
        Table(rows, selection: $selection) {
            TableColumn("Time") { event in
                Text(Describe.compactTime(event.date, now: now))
                    .help(StatusMenu.longDate(event.date))
            }
            .width(min: 80, ideal: 130)
            TableColumn("App") { event in
                AppCell(app: event.app, icon: icons.icon(for: event.app, size: 16), ignored: model.isIgnored(event.app))
            }
            .width(min: 150, ideal: 250)
            TableColumn("What Happened") { event in
                VerdictLabel(verdict: event.verdict)
            }
            .width(min: 120, ideal: 150)
            TableColumn("From") { event in
                Text(event.previous.map { $0.name } ?? "—")
                    .foregroundStyle(event.previous == nil ? .secondary : .primary)
                    .help(event.previous.map(Describe.name) ?? "")
            }
            .width(min: 80, ideal: 110)
            TableColumn("Why") { event in
                Text(Describe.shortReason(event))
                    .foregroundStyle(.secondary)
                    .help([Describe.reason(event), Describe.aftermath(event, isCurrent: model.isCurrent(event)), Describe.systemNote(event.app)].compactMap { $0 }.joined(separator: "\n"))
            }
            .width(min: 120, ideal: 190)
            TableColumn("In Front") { event in
                Text(event.heldFor.map(Describe.duration) ?? (model.isCurrent(event) ? "Now" : "—"))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .width(min: 56, ideal: 76)
        }
        .contextMenu(forSelectionType: FocusEvent.ID.self) { ids in
            contextMenu(for: rows.filter { ids.contains($0.id) })
        }
    }

    @ViewBuilder
    private func contextMenu(for events: [FocusEvent]) -> some View {
        if !events.isEmpty {
            Button(events.count == 1 ? "Copy Details" : "Copy Details of \(events.count) Events") {
                Clipboard.copy(events.map {
                    Describe.details($0, date: StatusMenu.longDate($0.date), home: Home.path, isCurrent: model.isCurrent($0))
                }.joined(separator: "\n\n"))
            }
        }
        if events.count == 1, let event = events.first {
            if let path = event.app.path, FileManager.default.fileExists(atPath: path) {
                Button("Show \(event.app.name) in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
                }
            }
            Divider()
            if model.isIgnored(event.app) {
                Button("Count \(Describe.name(event.app))'s Steals Again") { model.stopIgnoring(event.app.key) }
            } else {
                Button("Ignore \(Describe.name(event.app))") { model.ignore(event.app) }
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if filter == .steals {
            ContentUnavailableView {
                Label("No steals yet", systemImage: "viewfinder")
            } description: {
                Text("Leave Who Stole My Focus running. The next time your typing lands in the wrong window, the app that grabbed focus shows up here and in the menu bar.")
            }
        } else {
            ContentUnavailableView {
                Label("Nothing yet", systemImage: "macwindow.on.rectangle")
            } description: {
                Text("Every app that comes to the front shows up here, with what brought it there.")
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Text("A steal is an app coming to the front with no click, shortcut or swipe in the \(Describe.duration(model.threshold)) before, or between your keystrokes while you type.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 12)
            Button(filter == .steals ? "Copy Steals as CSV" : "Copy All as CSV") { copyCSV(rows.reversed()) }
                .disabled(rows.isEmpty)
            Button("Clear Log…", action: clear)
                .disabled(model.log.events.isEmpty)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

private struct OffenderChip: View {
    let offender: Offender
    let icon: NSImage
    let now: Date

    var body: some View {
        HStack(spacing: 7) {
            Image(nsImage: icon)
            VStack(alignment: .leading, spacing: 0) {
                Text(offender.app.name)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                Text(([offender.app.containingAppName].compactMap { $0 } + ["\(offender.count) \(offender.count == 1 ? "steal" : "steals")"]).joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
        .help("Last stole focus \(Describe.relative(offender.lastDate, now: now))" + (offender.usualVictim.map { ", usually from \(Describe.name($0))" } ?? ""))
    }
}

private struct AppCell: View {
    let app: AppInfo
    let icon: NSImage
    let ignored: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(nsImage: icon)
            Text(app.name)
                .lineLimit(1)
                .layoutPriority(1)
            if let parent = app.containingAppName {
                Text(parent)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if ignored {
                Text("Ignored")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
                    .background(.quaternary, in: Capsule())
            }
        }
        .opacity(ignored ? 0.6 : 1)
        .help(app.path ?? app.name)
    }
}

struct VerdictLabel: View {
    let verdict: Verdict

    var body: some View {
        Label {
            Text(Describe.verdict(verdict))
                .fontWeight(verdict == .stole ? .semibold : .regular)
        } icon: {
            Image(systemName: Self.symbol(verdict))
                .foregroundStyle(Self.color(verdict))
        }
    }

    static func symbol(_ verdict: Verdict) -> String {
        switch verdict {
        case .stole: "exclamationmark.triangle.fill"
        case .switched: "cursorarrow.click"
        case .opened: "arrow.up.forward.app"
        case .returned: "arrow.uturn.backward"
        case .unsure: "questionmark.circle"
        }
    }

    static func color(_ verdict: Verdict) -> Color {
        switch verdict {
        case .stole: .red
        case .unsure: .orange
        case .switched, .opened, .returned: .secondary
        }
    }
}

/// Opens the log in its own window and remembers where you put it.
@MainActor
final class LogWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let makeView: () -> LogView
    /// Called when you close the window.
    var onClose: (() -> Void)?

    init(makeView: @escaping () -> LogView) {
        self.makeView = makeView
    }

    var isVisible: Bool { window?.isVisible == true }

    func show() {
        let window = self.window ?? makeWindow()
        self.window = window
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        onClose?()
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(contentViewController: NSHostingController(rootView: makeView()))
        window.title = "Who Stole My Focus"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.setContentSize(NSSize(width: 960, height: 540))
        if !window.setFrameUsingName("LogWindow") {
            window.center()
        }
        window.setFrameAutosaveName("LogWindow")
        return window
    }
}
