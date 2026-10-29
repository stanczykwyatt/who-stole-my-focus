import AppKit
import FocusCore
import SwiftUI
import Testing
@testable import WhoStoleMyFocus

/// Renders the log window into a bitmap from a window that's never shown, so nothing appears on
/// screen or takes focus. Set SCREENSHOT_DIR to also save the renders as the README screenshots:
///
///   SCREENSHOT_DIR=docs swift test --filter "Log window"
@MainActor
@Suite("Log window")
struct LogViewTests {
    @Test func rendersStealsAndOffenders() throws {
        let (model, icons) = Gallery.make()
        let image = render(LogView(model: model, icons: icons), name: "screenshot-light", dark: false)
        #expect(image.pixelsWide >= Int(Gallery.stealsSize.width))
        #expect(colors(in: image) > 40)
    }

    @Test func rendersInDarkMode() throws {
        let (model, icons) = Gallery.make()
        let image = render(LogView(model: model, icons: icons), name: "screenshot-dark", dark: true)
        #expect(colors(in: image) > 40)
    }

    @Test func rendersEverySwitch() throws {
        let (model, icons) = Gallery.make()
        let image = render(LogView(model: model, icons: icons, filter: .everything), name: nil, dark: false, size: Gallery.everythingSize)
        #expect(colors(in: image) > 40)
    }

    @Test func rendersTheEmptyState() throws {
        let model = FocusModel(store: nil, preferences: scratchPreferences(), ownPID: nil)
        let image = render(LogView(model: model, icons: AppIcons()), name: nil, dark: false)
        #expect(colors(in: image) > 4)
    }

    @Test func verdictsHaveDistinctSymbols() {
        let symbols = Verdict.allCases.map(VerdictLabel.symbol)
        #expect(Set(symbols).count == Verdict.allCases.count)
        for symbol in symbols {
            #expect(NSImage(systemSymbolName: symbol, accessibilityDescription: nil) != nil, "Missing symbol \(symbol)")
        }
    }

    // MARK: Rendering

    private func render(_ view: LogView, name: String?, dark: Bool, size: NSSize = Gallery.stealsSize) -> NSBitmapImageRep {
        let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
        host.frame = NSRect(origin: .zero, size: size)
        host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        // Never ordered front: it only gives the view a backing to draw into.
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
        host.layoutSubtreeIfNeeded()
        let image = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
        host.cacheDisplay(in: host.bounds, to: image)
        if let name, let folder = ProcessInfo.processInfo.environment["SCREENSHOT_DIR"] {
            let url = URL(fileURLWithPath: folder).appendingPathComponent("\(name).png")
            try? image.representation(using: .png, properties: [:])?.write(to: url)
        }
        return image
    }

    /// Distinct colors in a coarse grid: a blank or broken render has only a few.
    private func colors(in image: NSBitmapImageRep) -> Int {
        var seen = Set<UInt32>()
        for x in stride(from: 0, to: image.pixelsWide, by: 7) {
            for y in stride(from: 0, to: image.pixelsHigh, by: 7) {
                guard let color = image.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                let r = UInt32(color.redComponent * 31), g = UInt32(color.greenComponent * 31), b = UInt32(color.blueComponent * 31)
                seen.insert(r << 10 | g << 5 | b)
            }
        }
        return seen.count
    }
}

/// A made-up morning of focus thieves, for the screenshots. The thieves are invented apps, so no
/// real developer's app is shown misbehaving; the victims are apps that ship with macOS.
@MainActor
enum Gallery {
    /// Sized to fit the gallery's rows without empty space under them.
    static let stealsSize = NSSize(width: 980, height: 372)
    static let everythingSize = NSSize(width: 980, height: 540)

    static let cloudSync = AppInfo(
        name: "Driftwood Agent", bundleID: "com.example.driftwood.agent",
        path: "/Applications/Driftwood Sync.app/Contents/Library/LoginItems/Driftwood Agent.app"
    )
    static let huddle = AppInfo(name: "Huddle", bundleID: "com.example.huddle", path: "/Applications/Huddle.app")
    static let printHub = AppInfo(name: "PrintHub Updater", bundleID: "com.example.printhub.updater", path: "/Applications/PrintHub Updater.app")
    static let securityAgent = AppInfo(
        name: "SecurityAgent", bundleID: "com.apple.SecurityAgent",
        path: "/System/Library/Frameworks/Security.framework/Versions/A/MachServices/SecurityAgent.bundle"
    )
    static let notes = AppInfo(name: "Notes", bundleID: "com.apple.Notes", path: "/System/Applications/Notes.app")
    static let mail = AppInfo(name: "Mail", bundleID: "com.apple.mail", path: "/System/Applications/Mail.app")
    static let terminal = AppInfo(name: "Terminal", bundleID: "com.apple.Terminal", path: "/System/Applications/Utilities/Terminal.app")
    static let safari = AppInfo(name: "Safari", bundleID: "com.apple.Safari", path: "/Applications/Safari.app")

    static func make(now: Date = Date()) -> (FocusModel, AppIcons) {
        func at(_ minutesAgo: Double) -> Date { now.addingTimeInterval(-minutesAgo * 60) }
        func input(click: Double = 90, key: Double = 90) -> InputSnapshot {
            InputSnapshot(click: click, keyPress: key, modifierChange: max(click, key), gesture: max(click, key))
        }
        func event(
            _ app: AppInfo, from previous: AppInfo, _ minutesAgo: Double, _ verdict: Verdict, _ cause: Cause,
            input: InputSnapshot, held: Double, next: AppInfo? = nil, nextVerdict: Verdict? = nil
        ) -> FocusEvent {
            FocusEvent(
                date: at(minutesAgo), app: app, pid: 1, previous: previous, input: input, cause: cause, verdict: verdict,
                heldFor: held, next: next ?? previous, nextVerdict: nextVerdict ?? .switched
            )
        }
        let events = [
            event(cloudSync, from: notes, 172, .stole, .none, input: input(click: 48, key: 37), held: 3.2),
            event(notes, from: cloudSync, 171.9, .switched, .click, input: input(click: 0.2), held: 900),
            event(huddle, from: notes, 156, .stole, .typing, input: input(key: 0.1), held: 1.8),
            event(notes, from: huddle, 155.9, .switched, .click, input: input(click: 0.3), held: 1500),
            event(safari, from: notes, 131, .switched, .shortcut, input: input(key: 0.2), held: 600),
            event(printHub, from: safari, 121, .stole, .none, input: input(click: 312, key: 300), held: 41, nextVerdict: .returned),
            event(safari, from: printHub, 120.3, .returned, .none, input: input(click: 330), held: 2400),
            event(terminal, from: safari, 80, .switched, .click, input: input(click: 0.1), held: 1200),
            event(securityAgent, from: terminal, 60, .stole, .none, input: input(click: 20, key: 12), held: 9, nextVerdict: .returned),
            event(terminal, from: securityAgent, 59.8, .returned, .keypress, input: input(key: 0.4), held: 1300),
            event(cloudSync, from: terminal, 38, .stole, .typing, input: input(key: 0.08), held: 2.4),
            event(terminal, from: cloudSync, 37.9, .switched, .click, input: input(click: 0.2), held: 700),
            event(mail, from: terminal, 26, .unsure, .keypress, input: input(key: 0.6), held: 420),
            event(cloudSync, from: mail, 19, .stole, .none, input: input(click: 21, key: 25), held: 1.1),
            event(mail, from: cloudSync, 18.9, .switched, .click, input: input(click: 0.2), held: 540),
            event(huddle, from: mail, 9, .stole, .none, input: input(click: 64, key: 58), held: 2.9),
            event(mail, from: huddle, 8.9, .switched, .click, input: input(click: 0.2), held: 500),
            event(cloudSync, from: mail, 0.4, .stole, .typing, input: input(key: 0.12), held: 1.6),
            event(mail, from: cloudSync, 0.35, .switched, .click, input: input(click: 0.1), held: 20),
        ]
        let store = LogStore(url: scratchFolder().appendingPathComponent("log.json"))
        try? store.save(FocusLog(events: events))
        let model = FocusModel(store: store, preferences: scratchPreferences(), ownPID: nil)
        let icons = AppIcons()
        icons.custom = [
            cloudSync.key: tile("arrow.triangle.2.circlepath.icloud.fill", top: (0.36, 0.62, 0.98), bottom: (0.16, 0.36, 0.86)),
            huddle.key: tile("video.fill", top: (0.42, 0.86, 0.52), bottom: (0.13, 0.60, 0.33)),
            printHub.key: tile("printer.fill", top: (0.99, 0.66, 0.30), bottom: (0.93, 0.40, 0.16)),
        ]
        return (model, icons)
    }

    /// An app icon for a made-up app: a gradient tile with a symbol on it.
    static func tile(_ symbol: String, top: (CGFloat, CGFloat, CGFloat), bottom: (CGFloat, CGFloat, CGFloat)) -> NSImage {
        NSImage(size: NSSize(width: 64, height: 64), flipped: false) { rect in
            let body = NSBezierPath(roundedRect: rect.insetBy(dx: 5, dy: 5), xRadius: 13, yRadius: 13)
            NSGradient(
                starting: NSColor(srgbRed: top.0, green: top.1, blue: top.2, alpha: 1),
                ending: NSColor(srgbRed: bottom.0, green: bottom.1, blue: bottom.2, alpha: 1)
            )!.draw(in: body, angle: -90)
            let config = NSImage.SymbolConfiguration(pointSize: 28, weight: .semibold).applying(.init(paletteColors: [.white]))
            if let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?.withSymbolConfiguration(config) {
                let size = image.size
                image.draw(in: NSRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2, width: size.width, height: size.height))
            }
            return true
        }
    }
}
