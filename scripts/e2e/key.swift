import CoreGraphics
import Foundation
let code = CGKeyCode(Int(CommandLine.arguments[1])!)
let src = CGEventSource(stateID: .hidSystemState)
CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: true)!.post(tap: .cghidEventTap)
usleep(50_000)
CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: false)!.post(tap: .cghidEventTap)
