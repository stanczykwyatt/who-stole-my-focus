import AppKit
import FocusCore
import Testing
@testable import WhoStoleMyFocus

@MainActor
final class RecordedActions: StatusMenuActions {
    var calls: [String] = []
    func openLog() { calls.append("openLog") }
    func copyStealsAsCSV() { calls.append("copyStealsAsCSV") }
    func clearLog() { calls.append("clearLog") }
    func setThreshold(_ seconds: Double) { calls.append("threshold \(seconds)") }
    func toggleNotifications() { calls.append("notifications") }
    func toggleOpenAtLogin() { calls.append("login") }
    func showAbout() { calls.append("about") }
}

/// The menu, built into an NSMenu that's never shown.
@MainActor
@Suite("Menu")
struct StatusMenuTests {
    let actions = RecordedActions()

    private func build(_ model: FocusModel, now: Date = Date()) -> NSMenu {
        let statusMenu = StatusMenu(model: model, icons: AppIcons(), actions: actions)
        statusMenu.now = { now }
        statusMenu.opensAtLogin = { true }
        let menu = NSMenu()
        statusMenu.build(into: menu)
        // Keeps the builder alive for the menu's targets, as the app delegate does.
        objc_setAssociatedObject(menu, "builder", statusMenu, .OBJC_ASSOCIATION_RETAIN)
        return menu
    }

    /// Matches the first line, since two-line items carry both lines in their title.
    private func item(_ menu: NSMenu, _ title: String) throws -> NSMenuItem {
        try #require(menu.items.first { firstLine($0) == title }, "No item titled \(title)")
    }

    private func firstLine(_ item: NSMenuItem) -> String {
        item.title.components(separatedBy: "\n")[0]
    }

    private func click(_ item: NSMenuItem) {
        _ = (item.target as? NSObject)?.perform(item.action, with: item)
    }

    @Test func emptyLog() throws {
        let menu = build(FocusModel(store: nil, preferences: scratchPreferences(), ownPID: nil))
        #expect(menu.items.first?.title == "No steals today")
        #expect(menu.items.contains { $0.title.hasPrefix("Nothing yet.") && !$0.isEnabled })
        #expect(try !item(menu, "Top Offenders").isEnabled)
        #expect(try !item(menu, "Copy Steals as CSV").isEnabled)
        #expect(try !item(menu, "Clear Log…").isEnabled)
        #expect(try item(menu, "Open at Login").state == .on)
    }

    @Test func stealsShowUpWithDetails() throws {
        // A whole second, so 30 s earlier is exactly 30 s and not 29.9999.
        let now = Date(timeIntervalSinceReferenceDate: Date().timeIntervalSinceReferenceDate.rounded())
        let model = model(with: [
            Sample.steal(Sample.syncHelper, from: Sample.xcode, at: now.addingTimeInterval(-120)),
            Sample.switched(Sample.notes, from: Sample.xcode, at: now.addingTimeInterval(-60)),
            Sample.steal(Sample.meetings, from: Sample.notes, at: now.addingTimeInterval(-30)),
        ])
        let menu = build(model, now: now)
        #expect(menu.items.first?.title == "2 steals today")

        let newest = try item(menu, "Meetings stole focus from Notes")
        #expect(newest.attributedTitle?.string.contains("30 s ago") == true)
        let details = try #require(newest.submenu)
        #expect(details.items.map(\.title).contains("No click or keypress for 41 s"))
        #expect(details.items.map(\.title).contains("In front for 2 s, then you went back to Notes"))
        let reveal = try item(details, "Show in Finder")
        #expect(!reveal.isEnabled) // the sample app isn't installed
        #expect(menu.items.firstIndex(of: newest)! < menu.items.firstIndex { $0.title.hasPrefix("SyncHelper") }!)
        #expect(!menu.items.contains { $0.title.hasPrefix("You switched") })
    }

    @Test func recentStealsAreCapped() {
        let now = Date()
        let model = model(with: (0..<12).map { Sample.steal(Sample.syncHelper, from: Sample.xcode, at: now.addingTimeInterval(Double(-$0))) })
        let menu = build(model, now: now)
        #expect(menu.items.filter { $0.title.hasPrefix("SyncHelper") }.count == StatusMenu.recentLimit)
    }

    @Test func topOffendersAreRanked() throws {
        let now = Date()
        let model = model(with: [
            Sample.steal(Sample.meetings, from: Sample.xcode, at: now.addingTimeInterval(-50)),
            Sample.steal(Sample.syncHelper, from: Sample.xcode, at: now.addingTimeInterval(-40)),
            Sample.steal(Sample.syncHelper, from: Sample.notes, at: now.addingTimeInterval(-30)),
        ])
        let menu = build(model, now: now)
        let offenders = try #require(item(menu, "Top Offenders").submenu)
        #expect(offenders.items.map(firstLine) == ["SyncHelper (CloudSync)", "Meetings"])
        #expect(offenders.items[0].attributedTitle?.string.contains("2 steals") == true)
    }

    @Test func ignoringFromTheMenu() throws {
        let now = Date()
        let model = model(with: [Sample.steal(Sample.syncHelper, from: Sample.xcode, at: now.addingTimeInterval(-5))])
        let menu = build(model, now: now)
        let details = try #require(item(menu, "SyncHelper (CloudSync) stole focus from Xcode").submenu)
        click(try item(details, "Ignore SyncHelper (CloudSync)"))
        #expect(model.isIgnored(Sample.syncHelper))

        let rebuilt = build(model, now: now)
        #expect(rebuilt.items.first?.title == "No steals today")
        let ignored = try #require(item(rebuilt, "Ignored Apps").submenu)
        let entry = try item(ignored, "SyncHelper (CloudSync)")
        #expect(entry.state == .on)
        click(entry)
        #expect(!model.isIgnored(Sample.syncHelper))
    }

    @Test func thresholdChoices() throws {
        let model = FocusModel(store: nil, preferences: scratchPreferences(), ownPID: nil)
        // Menu items hold their targets weakly, so the menu has to outlive the click.
        let menu = build(model)
        let submenu = try #require(item(menu, "Counts as You Within").submenu)
        let choices = submenu.items.filter(\.isEnabled)
        #expect(choices.map(\.title) == ["0.5 s", "1 s", "1.5 s", "2 s", "3 s"])
        #expect(choices.filter { $0.state == .on }.map(\.title) == ["1.5 s"])
        click(choices[3])
        #expect(actions.calls == ["threshold 2.0"])
    }

    @Test func actionsReachTheDelegate() throws {
        let model = model(with: [Sample.steal(Sample.syncHelper, from: Sample.xcode, at: Date())])
        let menu = build(model)
        for title in ["Open Log…", "Copy Steals as CSV", "Notify Me About Steals", "Open at Login", "Clear Log…", "About Who Stole My Focus"] {
            click(try item(menu, title))
        }
        #expect(actions.calls == ["openLog", "copyStealsAsCSV", "notifications", "login", "clearLog", "about"])
    }

    @Test func blockedNotificationsAreExplained() throws {
        let model = FocusModel(store: nil, preferences: scratchPreferences(), ownPID: nil)
        model.notifies = true
        let statusMenu = StatusMenu(model: model, icons: AppIcons(), actions: actions)
        statusMenu.notificationsAllowed = false
        let menu = NSMenu()
        statusMenu.build(into: menu)
        #expect(menu.items.contains { $0.title.hasPrefix("Allow notifications in System Settings") })
        #expect(try item(menu, "Notify Me About Steals").state == .on)
    }
}
