/// How long ago you last did each thing that can bring an app to the front, in seconds.
///
/// macOS reports these times to any app without a permission prompt. They say when, never which
/// key or where you clicked.
public struct InputSnapshot: Codable, Hashable, Sendable {
    /// Any mouse button, pressed or released. Covers windows, the Dock, links and notifications.
    public var click: Double
    public var keyPress: Double
    /// ⌘, ⌥, ⌃, ⇧ or fn pressed or released.
    public var modifierChange: Double
    /// Trackpad gestures. macOS reports one whenever you touch the trackpad, even to move the
    /// pointer, so on its own this says little. It only counts with a Space change, as a swipe.
    public var gesture: Double
    /// Whether ⌘, ⌥ or ⌃ is held down right now.
    public var commandKeysHeld: Bool

    public init(click: Double, keyPress: Double, modifierChange: Double, gesture: Double, commandKeysHeld: Bool = false) {
        self.click = click
        self.keyPress = keyPress
        self.modifierChange = modifierChange
        self.gesture = gesture
        self.commandKeysHeld = commandKeysHeld
    }

    /// Ten days. macOS reports huge numbers for input that hasn't happened since startup.
    public static let longest: Double = 864_000

    /// Nothing at all for as long as macOS can tell.
    public static let none = InputSnapshot(click: longest, keyPress: longest, modifierChange: longest, gesture: longest)

    /// Seconds since the last click, keypress or modifier key: anything that could switch apps.
    /// Gestures aren't included, since touching the trackpad to move the pointer is one.
    public var latest: Double { Swift.min(click, keyPress, modifierChange) }

    /// Seconds since you last clicked or typed, the two ways of actually using an app.
    public var interaction: Double { Swift.min(click, keyPress) }

    /// Clamped to 0...ten days, so odd values from the system can't break the log or its JSON.
    public var sanitized: InputSnapshot {
        func clamp(_ value: Double) -> Double {
            value.isNaN ? Self.longest : Swift.min(Swift.max(value, 0), Self.longest)
        }
        return InputSnapshot(
            click: clamp(click), keyPress: clamp(keyPress), modifierChange: clamp(modifierChange),
            gesture: clamp(gesture), commandKeysHeld: commandKeysHeld
        )
    }
}

/// What most likely brought an app to the front.
public enum Cause: String, Codable, CaseIterable, Sendable {
    /// A click a moment before.
    case click
    /// A keyboard shortcut, like ⌘Tab or a launcher's hot key.
    case shortcut
    /// A trackpad swipe to another Space or full-screen app. Only decided after the switch, once
    /// it's clear the Space changed.
    case gesture
    /// A key pressed in a launcher like Spotlight, Raycast or Alfred, usually Return.
    case launcher
    /// A plain keypress a moment before. It could be Return on something that opens an app, or the
    /// app jumped in while you were typing. Settled by watching whether you keep typing.
    case keypress
    /// You were typing when it came forward and kept typing after, so you didn't switch on purpose.
    case typing
    /// No click, keypress or gesture for longer than the threshold.
    case none
    /// Part of macOS you open yourself, like Mission Control or Notification Center, often from a
    /// hot corner or gesture that leaves no click or keypress behind.
    case systemUI
    /// The same app starting again shortly after it quit, as apps do when they update themselves.
    case relaunch
    /// Before your first click or keypress since tracking started, like at login.
    case startup
}

/// Turns input times into a cause.
public struct CauseRules: Equatable, Sendable {
    /// How long after a click or keypress a switch still counts as yours. Links and busy apps can
    /// take a moment to come forward.
    public var threshold: Double
    /// ⌘Tab switches the moment you let go of ⌘, so a modifier only counts if it changed just before.
    public var modifierWindow: Double
    /// A modifier let go this recently is almost certainly what made the switch, since macOS
    /// switches the instant ⌘ comes up. Earlier than this, it may be ⇧ released while typing.
    public var instantModifierWindow: Double
    /// How recent a trackpad touch has to be to explain a switch to another Space.
    public var gestureWindow: Double

    public static let thresholdChoices: [Double] = [0.5, 1, 1.5, 2, 3]
    public static let defaultThreshold: Double = 1.5

    public init(
        threshold: Double = CauseRules.defaultThreshold, modifierWindow: Double = 0.5, instantModifierWindow: Double = 0.15,
        gestureWindow: Double = 1
    ) {
        self.threshold = threshold
        self.modifierWindow = modifierWindow
        self.instantModifierWindow = instantModifierWindow
        self.gestureWindow = gestureWindow
    }

    /// - Parameter frontIsLauncher: whether the app in front before the switch was a launcher or
    ///   menu bar app, where typing and pressing Return opens other apps.
    public func cause(of input: InputSnapshot, frontIsLauncher: Bool) -> Cause {
        // A click only explains the switch if you haven't typed since. Otherwise you were typing in
        // the window you clicked.
        if input.click <= threshold, input.click <= input.keyPress {
            return .click
        }
        // Letting go of a modifier after the last key is how ⌘Tab and most hot keys finish.
        if input.modifierChange <= modifierWindow, input.modifierChange <= input.keyPress {
            return .shortcut
        }
        if input.keyPress <= threshold {
            if input.commandKeysHeld { return .shortcut }
            if frontIsLauncher { return .launcher }
            return .keypress
        }
        return .none
    }
}
