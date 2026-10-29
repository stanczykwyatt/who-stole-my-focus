import CoreGraphics
import FocusCore

/// Reads how long ago you last clicked, typed or swiped.
protocol InputClock {
    func snapshot() -> InputSnapshot
}

/// The real clock. macOS answers these questions without asking for any permission, and the
/// answers are only times: never which key, what was typed or where you clicked.
struct SystemInputClock: InputClock {
    private static let clicks: [CGEventType] = [
        .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp, .otherMouseDown, .otherMouseUp,
    ]
    /// NSEvent's gesture, swipe, begin-gesture and end-gesture types, which CGEventType has no
    /// names for.
    private static let gestures: [CGEventType] = [29, 31, 19, 20].compactMap(CGEventType.init(rawValue:))

    func snapshot() -> InputSnapshot {
        let flags = CGEventSource.flagsState(.combinedSessionState)
        return InputSnapshot(
            click: Self.since(Self.clicks),
            keyPress: Self.since([.keyDown]),
            modifierChange: Self.since([.flagsChanged]),
            gesture: Self.since(Self.gestures),
            commandKeysHeld: !flags.intersection([.maskCommand, .maskAlternate, .maskControl]).isEmpty
        )
    }

    private static func since(_ types: [CGEventType]) -> Double {
        types.map { CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0) }.min()
            ?? InputSnapshot.longest
    }
}
