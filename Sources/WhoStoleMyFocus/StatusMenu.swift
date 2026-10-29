import AppKit
import FocusCore
import ServiceManagement

/// What the menu's items do. The app delegate does them; tests record them.
@MainActor
protocol StatusMenuActions: AnyObject {
    func openLog()
    func copyStealsAsCSV()
    func clearLog()
    func setThreshold(_ seconds: Double)
    func toggleNotifications()
    func toggleOpenAtLogin()
    func showAbout()
}

/// Builds the menu bar menu fresh each time it opens, so times and counts are never stale.
@MainActor
final class StatusMenu: NSObject {
    private let model: FocusModel
    private let icons: AppIcons
    private weak var actions: StatusMenuActions?
    var now: () -> Date = Date.init
    var opensAtLogin: () -> Bool = { SMAppService.mainApp.status == .enabled }
    /// Whether macOS lets the app post notifications, as last checked.
    var notificationsAllowed = true

    static let recentLimit = 8
    static let offenderLimit = 10

    init(model: FocusModel, icons: AppIcons, actions: StatusMenuActions) {
        self.model = model
        self.icons = icons
        self.actions = actions
    }

    func build(into menu: NSMenu) {
        menu.removeAllItems()
        let now = now()
        let today = Calendar.current.startOfDay(for: now)
        let todaysSteals = model.steals(since: today).count

        menu.addItem(disabled(todaysSteals == 0 ? "No steals today" : "\(todaysSteals) \(todaysSteals == 1 ? "steal" : "steals") today"))
        menu.addItem(.separator())

        menu.addItem(.sectionHeader(title: "Recent Steals"))
        let recent = model.steals().prefix(Self.recentLimit)
        if recent.isEmpty {
            menu.addItem(disabled("Nothing yet. When your typing lands in the wrong window, look here."))
        }
        for event in recent {
            menu.addItem(stealItem(event, now: now))
        }

        menu.addItem(.separator())
        let offenders = NSMenuItem(title: "Top Offenders", action: nil, keyEquivalent: "")
        let ranked = model.offenders().prefix(Self.offenderLimit)
        if ranked.isEmpty {
            offenders.isEnabled = false
        } else {
            let submenu = NSMenu()
            for offender in ranked {
                submenu.addItem(offenderItem(offender, now: now))
            }
            offenders.submenu = submenu
        }
        menu.addItem(offenders)
        menu.addItem(item("Open Log…", #selector(openLog), key: "l"))
        let copy = item("Copy Steals as CSV", #selector(copyStealsAsCSV))
        copy.isEnabled = !model.steals().isEmpty
        menu.addItem(copy)

        menu.addItem(.separator())
        menu.addItem(thresholdItem())
        let notify = item("Notify Me About Steals", #selector(toggleNotifications))
        notify.state = model.notifies ? .on : .off
        menu.addItem(notify)
        if model.notifies && !notificationsAllowed {
            menu.addItem(disabled("Allow notifications in System Settings → Notifications"))
        }
        menu.addItem(ignoredItem())
        let login = item("Open at Login", #selector(toggleOpenAtLogin))
        login.state = opensAtLogin() ? .on : .off
        menu.addItem(login)

        menu.addItem(.separator())
        let clear = item("Clear Log…", #selector(clearLog))
        clear.isEnabled = !model.log.events.isEmpty
        menu.addItem(clear)
        menu.addItem(item("About Who Stole My Focus", #selector(showAbout)))
        menu.addItem(NSMenuItem(title: "Quit Who Stole My Focus", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    // MARK: Items

    private func stealItem(_ event: FocusEvent, now: Date) -> NSMenuItem {
        let item = NSMenuItem(title: Describe.headline(event), action: nil, keyEquivalent: "")
        item.attributedTitle = twoLines(
            Describe.headline(event),
            "\(Describe.relative(event.date, now: now)) · \(Describe.reason(event))"
        )
        item.image = icons.icon(for: event.app, size: 20)
        let details = NSMenu()
        details.addItem(disabled(Describe.reason(event)))
        details.addItem(disabled(Describe.aftermath(event, isCurrent: model.isCurrent(event))))
        details.addItem(disabled(Self.longDate(event.date)))
        if let note = Describe.systemNote(event.app) {
            details.addItem(disabled(note))
        }
        details.addItem(.separator())
        addAppActions(for: event.app, to: details)
        let copy = self.item("Copy Details", #selector(copyDetails(_:)))
        copy.representedObject = event
        details.addItem(copy)
        item.submenu = details
        return item
    }

    private func offenderItem(_ offender: Offender, now: Date) -> NSMenuItem {
        let name = Describe.name(offender.app)
        let item = NSMenuItem(title: name, action: nil, keyEquivalent: "")
        item.attributedTitle = twoLines(
            name,
            "\(offender.count) \(offender.count == 1 ? "steal" : "steals"), last \(Describe.relative(offender.lastDate, now: now))"
        )
        item.image = icons.icon(for: offender.app, size: 20)
        let details = NSMenu()
        if let victim = offender.usualVictim {
            details.addItem(disabled("Usually takes focus from \(Describe.name(victim))"))
        }
        if let note = Describe.systemNote(offender.app) {
            details.addItem(disabled(note))
        }
        if details.numberOfItems > 0 {
            details.addItem(.separator())
        }
        addAppActions(for: offender.app, to: details)
        item.submenu = details
        return item
    }

    private func addAppActions(for app: AppInfo, to menu: NSMenu) {
        if let path = app.path {
            let reveal = item("Show in Finder", #selector(showInFinder(_:)))
            reveal.representedObject = path
            reveal.isEnabled = FileManager.default.fileExists(atPath: path)
            menu.addItem(reveal)
        }
        let ignore = item("Ignore \(Describe.name(app))", #selector(ignore(_:)))
        ignore.representedObject = app
        menu.addItem(ignore)
    }

    private func thresholdItem() -> NSMenuItem {
        let submenu = NSMenu()
        submenu.addItem(disabled("A switch this soon after a click or keypress is yours"))
        for seconds in CauseRules.thresholdChoices {
            let choice = item(Describe.duration(seconds), #selector(chooseThreshold(_:)))
            choice.representedObject = seconds
            choice.state = seconds == model.threshold ? .on : .off
            submenu.addItem(choice)
        }
        let item = NSMenuItem(title: "Counts as You Within", action: nil, keyEquivalent: "")
        item.submenu = submenu
        return item
    }

    private func ignoredItem() -> NSMenuItem {
        let submenu = NSMenu()
        let apps = model.ignoredApps
        if apps.isEmpty {
            submenu.addItem(disabled("None. Ignore an app from its steal in the menu."))
        } else {
            submenu.addItem(disabled("Click an app to count its steals again"))
            for app in apps {
                let entry = item(app.name, #selector(stopIgnoring(_:)))
                entry.representedObject = app.key
                entry.state = .on
                submenu.addItem(entry)
            }
        }
        let item = NSMenuItem(title: "Ignored Apps", action: nil, keyEquivalent: "")
        item.submenu = submenu
        return item
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    private func disabled(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func twoLines(_ first: String, _ second: String) -> NSAttributedString {
        let text = NSMutableAttributedString(string: first, attributes: [.font: NSFont.menuFont(ofSize: 0)])
        text.append(NSAttributedString(string: "\n" + second, attributes: [
            .font: NSFont.menuFont(ofSize: NSFont.smallSystemFontSize),
            .foregroundColor: NSColor.secondaryLabelColor,
        ]))
        return text
    }

    static func longDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }

    // MARK: Actions

    @objc private func openLog() { actions?.openLog() }
    @objc private func copyStealsAsCSV() { actions?.copyStealsAsCSV() }
    @objc private func clearLog() { actions?.clearLog() }
    @objc private func toggleNotifications() { actions?.toggleNotifications() }
    @objc private func toggleOpenAtLogin() { actions?.toggleOpenAtLogin() }
    @objc private func showAbout() { actions?.showAbout() }

    @objc private func chooseThreshold(_ sender: NSMenuItem) {
        guard let seconds = sender.representedObject as? Double else { return }
        actions?.setThreshold(seconds)
    }

    @objc private func ignore(_ sender: NSMenuItem) {
        guard let app = sender.representedObject as? AppInfo else { return }
        model.ignore(app)
    }

    @objc private func stopIgnoring(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String else { return }
        model.stopIgnoring(key)
    }

    @objc private func showInFinder(_ sender: NSMenuItem) {
        guard let path = sender.representedObject as? String else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    @objc private func copyDetails(_ sender: NSMenuItem) {
        guard let event = sender.representedObject as? FocusEvent else { return }
        Clipboard.copy(Describe.details(event, date: Self.longDate(event.date), home: Home.path, isCurrent: model.isCurrent(event)))
    }
}

/// Your real home folder. Inside the sandbox, `NSHomeDirectory()` is the app's container instead.
enum Home {
    static let path: String? = {
        guard let entry = getpwuid(getuid()), let directory = entry.pointee.pw_dir else { return nil }
        return String(cString: directory)
    }()
}

enum Clipboard {
    static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
