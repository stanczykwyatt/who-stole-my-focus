import FocusCore
import Foundation

/// Settings, kept in the app's sandbox container.
struct Preferences {
    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private enum Key {
        static let threshold = "threshold"
        static let notifies = "notifies"
        static let ignored = "ignoredApps"
        static let launchedBefore = "launchedBefore"
    }

    /// Seconds after a click or keypress during which a switch counts as yours. Only the choices
    /// offered in the menu are accepted, so a hand-edited value can't break detection.
    var threshold: Double {
        get {
            let saved = defaults.double(forKey: Key.threshold)
            return CauseRules.thresholdChoices.contains(saved) ? saved : CauseRules.defaultThreshold
        }
        nonmutating set { defaults.set(newValue, forKey: Key.threshold) }
    }

    var notifies: Bool {
        get { defaults.bool(forKey: Key.notifies) }
        nonmutating set { defaults.set(newValue, forKey: Key.notifies) }
    }

    /// Apps whose steals aren't counted, by `AppInfo.key`. Starts with the lock screen and screen saver.
    var ignored: Set<String> {
        get {
            guard let saved = defaults.stringArray(forKey: Key.ignored) else { return SystemApps.ignoredByDefault }
            return Set(saved)
        }
        nonmutating set { defaults.set(newValue.sorted(), forKey: Key.ignored) }
    }

    var launchedBefore: Bool {
        get { defaults.bool(forKey: Key.launchedBefore) }
        nonmutating set { defaults.set(newValue, forKey: Key.launchedBefore) }
    }
}
