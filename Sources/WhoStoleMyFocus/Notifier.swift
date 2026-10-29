import FocusCore
import Foundation
import UserNotifications

/// Optional notifications when an app steals focus. Off until you turn them on.
@MainActor
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    /// Called when you click a notification.
    var onOpen: (() -> Void)?
    private var lastPosted: [String: Date] = [:]
    /// An app that steals focus over and over gets one notification per this many seconds.
    private let quietTime: TimeInterval = 30

    private var center: UNUserNotificationCenter { .current() }

    func activate() {
        center.delegate = self
    }

    /// Asks macOS for permission. Calls back with whether notifications can be shown.
    func requestPermission(_ done: @escaping @MainActor (Bool) -> Void) {
        Task { done(await Self.requestAuthorization()) }
    }

    /// Checks whether notifications are allowed in System Settings.
    func checkPermission(_ done: @escaping @MainActor (Bool) -> Void) {
        Task {
            let status = await Self.authorizationStatus()
            done(status == .authorized || status == .provisional)
        }
    }

    // macOS runs these callbacks on a background queue. They're written in nonisolated functions,
    // because a closure written in this main-actor class would trap when called there.

    private nonisolated static func requestAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
                continuation.resume(returning: granted)
            }
        }
    }

    private nonisolated static func authorizationStatus() async -> UNAuthorizationStatus {
        await withCheckedContinuation { continuation in
            UNUserNotificationCenter.current().getNotificationSettings { settings in
                continuation.resume(returning: settings.authorizationStatus)
            }
        }
    }

    func post(_ event: FocusEvent, now: Date = Date()) {
        if let last = lastPosted[event.app.key], now.timeIntervalSince(last) < quietTime { return }
        lastPosted[event.app.key] = now
        let content = UNMutableNotificationContent()
        content.title = "\(Describe.name(event.app)) stole focus"
        content.body = [
            event.previous.map { "From \(Describe.name($0))." },
            Describe.reason(event) + ".",
        ].compactMap { $0 }.joined(separator: " ")
        content.threadIdentifier = event.app.key
        let request = UNNotificationRequest(identifier: event.id.uuidString, content: content, trigger: nil)
        center.add(request)
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        await MainActor.run { onOpen?() }
    }
}
