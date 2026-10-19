// click X Y [count]
import CoreGraphics
import Foundation
let a = CommandLine.arguments
let p = CGPoint(x: Double(a[1])!, y: Double(a[2])!), n = a.count > 3 ? Int(a[3])! : 1
CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: p, mouseButton: .left)!.post(tap: .cghidEventTap); usleep(100_000)
for i in 1...n { for t in [CGEventType.leftMouseDown, .leftMouseUp] { let e = CGEvent(mouseEventSource: nil, mouseType: t, mouseCursorPosition: p, mouseButton: .left)!; e.setIntegerValueField(.mouseEventClickState, value: Int64(i)); e.post(tap: .cghidEventTap); usleep(40_000) } }
