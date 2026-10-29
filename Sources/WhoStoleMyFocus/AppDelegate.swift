import AppKit
import FocusCore
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, StatusMenuActions {
    private let preferences = Preferences()
    private let icons = AppIcons()
    private let notifier = Notifier()
    private let menu = NSMenu()
    private var statusItem: NSStatusItem!
    private lazy var model = FocusModel(
        store: LogStore(), preferences: preferences, ownPID: ProcessInfo.processInfo.processIdentifier
    )
    private lazy var monitor = FocusMonitor(model: model)
    private lazy var statusMenu = StatusMenu(model: model, icons: icons, actions: self)
    private lazy var logWindow = LogWindowController { [unowned self] in
        LogView(
            model: model, icons: icons,
            copyCSV: { rows in Clipboard.copy(CSVExport.csv(rows, home: Home.path)) },
            clear: { [unowned self] in clearLog() }
        )
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        menu.delegate = self
        statusItem.menu = menu
        updateStatusItem()

        model.onSteal = { [weak self] event in self?.stoleFocus(event) }
        notifier.onOpen = { [weak self] in self?.openLog() }
        notifier.activate()
        refreshNotificationPermission()
        // Gives the keyboard back to the app you were using.
        logWindow.onClose = { NSApp.hide(nil) }
        monitor.start()

        // The first time, open at login like most menu bar utilities, and show the log so it's
        // clear what the app does. After that it starts quietly. Turn off login in the menu.
        if !preferences.launchedBefore {
            preferences.launchedBefore = true
            try? SMAppService.mainApp.register()
            openLog()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.flush()
    }

    private func stoleFocus(_ event: FocusEvent) {
        updateStatusItem()
        if model.notifies {
            notifier.post(event)
        }
    }

    private func updateStatusItem() {
        guard let button = statusItem?.button else { return }
        let alert = model.unseenSteals > 0
        button.image = NSImage(
            systemSymbolName: alert ? "viewfinder.trianglebadge.exclamationmark" : "viewfinder",
            accessibilityDescription: alert ? "Who Stole My Focus, new steals" : "Who Stole My Focus"
        )
        var tip = "Who Stole My Focus"
        let today = model.steals(since: Calendar.current.startOfDay(for: Date()))
        if let last = today.first {
            let time = DateFormatter.localizedString(from: last.date, dateStyle: .none, timeStyle: .short)
            tip += "\n\(today.count) \(today.count == 1 ? "steal" : "steals") today. Last: \(Describe.name(last.app)) at \(time)."
        } else {
            tip += "\nNo steals today."
        }
        button.toolTip = tip
    }

    private func refreshNotificationPermission() {
        notifier.checkPermission { [weak self] allowed in
            self?.statusMenu.notificationsAllowed = allowed
        }
    }

    // MARK: Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        statusMenu.build(into: menu)
    }

    func menuWillOpen(_ menu: NSMenu) {
        model.markSeen()
        updateStatusItem()
        refreshNotificationPermission()
    }

    // MARK: StatusMenuActions

    func openLog() {
        model.markSeen()
        updateStatusItem()
        logWindow.show()
    }

    func copyStealsAsCSV() {
        Clipboard.copy(CSVExport.csv(model.steals().reversed(), home: Home.path))
    }

    func clearLog() {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = "Clear the log?"
        alert.informativeText = "This deletes every switch and steal Who Stole My Focus has recorded. It can't be undone."
        alert.addButton(withTitle: "Clear Log")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            model.clearLog()
            updateStatusItem()
        }
        if !logWindow.isVisible {
            NSApp.hide(nil)
        }
    }

    func setThreshold(_ seconds: Double) {
        model.threshold = seconds
    }

    func toggleNotifications() {
        if model.notifies {
            model.notifies = false
            return
        }
        notifier.requestPermission { [weak self] granted in
            guard let self else { return }
            statusMenu.notificationsAllowed = granted
            model.notifies = true
        }
    }

    func toggleOpenAtLogin() {
        if SMAppService.mainApp.status == .enabled {
            try? SMAppService.mainApp.unregister()
        } else {
            try? SMAppService.mainApp.register()
        }
    }

    func showAbout() {
        NSApp.activate()
        NSApp.orderFrontStandardAboutPanel(options: [
            .credits: NSAttributedString(
                string: "Free and open source. No internet access.\ngithub.com/stanczykwyatt/who-stole-my-focus",
                attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor]
            ),
        ])
    }
}
