// Test helper: a window that starts a real file drag (like Finder) when the mouse is dragged in it.
// Like Finder it stays open after the drop; run.sh kills it before the next drag.
import AppKit
let files = CommandLine.arguments.dropFirst().map { URL(fileURLWithPath: $0) }
final class Source: NSView, NSDraggingSource {
    override func draw(_ r: NSRect) { NSColor.systemTeal.setFill(); bounds.fill() }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) {}
    override func mouseDragged(with event: NSEvent) {

        guard !dragging else { return }
        dragging = true
        let items = files.map { file -> NSDraggingItem in
            let item = NSDraggingItem(pasteboardWriter: file as NSURL)
            item.setDraggingFrame(NSRect(x: 0, y: 0, width: 64, height: 64), contents: NSWorkspace.shared.icon(forFile: file.path))
            return item
        }
        beginDraggingSession(with: items, event: event, source: self)
    }
    var dragging = false
    func draggingSession(_ s: NSDraggingSession, sourceOperationMaskFor c: NSDraggingContext) -> NSDragOperation { .copy }
    func draggingSession(_ s: NSDraggingSession, endedAt p: NSPoint, operation: NSDragOperation) {
        print("drag ended op=\(operation.rawValue)"); fflush(stdout)
    }
}
let app = NSApplication.shared
app.setActivationPolicy(.regular)
let screen = NSScreen.main!.frame
let w = NSWindow(contentRect: NSRect(x: 100, y: screen.height - 400, width: 200, height: 200), styleMask: [.titled], backing: .buffered, defer: false)
w.contentView = Source()
w.makeKeyAndOrderFront(nil)
app.activate(ignoringOtherApps: true)
print("ready"); fflush(stdout)
app.run()
