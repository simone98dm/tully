import CoreGraphics
import Foundation
@testable import tully

/// Isolated defaults per test.
func makeDefaults() -> UserDefaults {
    let name = "tully.tests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    return defaults
}

func keyEvent(_ keyCode: CGKeyCode, down: Bool = true, flags: CGEventFlags = []) -> CGEvent {
    let event = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: down)!
    event.flags = flags
    return event
}

func flagsEvent(_ flags: CGEventFlags) -> CGEvent {
    let event = CGEvent(keyboardEventSource: nil, virtualKey: 58, keyDown: true)!
    event.type = .flagsChanged
    event.flags = flags
    return event
}

/// Lets queued `DispatchQueue.main.async` work run.
func drainMainQueue() async {
    await withCheckedContinuation { continuation in
        DispatchQueue.main.async { continuation.resume() }
    }
}

enum KeyCode {
    static let a: CGKeyCode = 0
    static let q: CGKeyCode = 12
    static let tab: CGKeyCode = 48
    static let space: CGKeyCode = 49
    static let returnKey: CGKeyCode = 36
    static let escape: CGKeyCode = 53
    static let left: CGKeyCode = 123
    static let right: CGKeyCode = 124
    static let down: CGKeyCode = 125
    static let up: CGKeyCode = 126
}
