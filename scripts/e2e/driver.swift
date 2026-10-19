// drive MOD DX DY [KEYS] [SHOT]  — drag from helper window, tap MOD, press KEYS (comma keycodes) at wheel center,
// glide to DX,DY, optional screenshot, drop. MOD "none" skips the modifier.
import AppKit
let a = CommandLine.arguments
let mod = a[1], dx = Double(a[2])!, dy = Double(a[3])!
let keys = a.count > 4 && !a[4].isEmpty ? a[4].split(separator: ",").map { CGKeyCode(Int($0)!) } : []
let shot = a.count > 5 ? a[5] : nil
let src = CGEventSource(stateID: .hidSystemState)
func mouse(_ t: CGEventType, _ p: CGPoint) { CGEvent(mouseEventSource: src, mouseType: t, mouseCursorPosition: p, mouseButton: .left)!.post(tap: .cghidEventTap) }
func key(_ c: CGKeyCode, _ down: Bool, _ f: CGEventFlags) { let e = CGEvent(keyboardEventSource: src, virtualKey: c, keyDown: down)!; e.flags = f; e.post(tap: .cghidEventTap) }
let start = CGPoint(x: 200, y: 300)
mouse(.mouseMoved, start); usleep(200_000); mouse(.leftMouseDown, start); usleep(150_000)
var p = start
for _ in 0..<15 { p.x += 4; mouse(.leftMouseDragged, p); usleep(30_000) }
usleep(300_000)
if mod != "none" {
  let (c, f): (CGKeyCode, CGEventFlags) = mod == "command" ? (55, .maskCommand) : mod == "control" ? (59, .maskControl) : (56, .maskShift)
  key(c, true, f); usleep(400_000); key(c, false, []); usleep(300_000)
}
for k in keys { key(k, true, []); usleep(100_000); key(k, false, []); usleep(350_000) }
let c = p
for i in 1...20 { let t = Double(i) / 20; mouse(.leftMouseDragged, CGPoint(x: c.x + dx * t, y: c.y + dy * t)); usleep(30_000) }
usleep(400_000)
if let shot { let pr = Process(); pr.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture"); pr.arguments = ["-x", "-R", "\(Int(c.x) - 200),\(Int(c.y) - 200),400,400", shot]; try! pr.run(); pr.waitUntilExit() }
mouse(.leftMouseUp, CGPoint(x: c.x + dx, y: c.y + dy))
