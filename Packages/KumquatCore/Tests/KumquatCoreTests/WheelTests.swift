import AppKit
import XCTest
@testable import KumquatCore

final class WheelTests: XCTestCase {
    let wheel = WheelGeometry(count: 4, innerRadius: 30, outerRadius: 100)

    func testSegmentsAreClockwiseFromTop() {
        XCTAssertEqual(wheel.segment(at: CGPoint(x: 0, y: 80)), 0)    // top
        XCTAssertEqual(wheel.segment(at: CGPoint(x: 80, y: 0)), 1)    // right
        XCTAssertEqual(wheel.segment(at: CGPoint(x: 0, y: -80)), 2)   // bottom
        XCTAssertEqual(wheel.segment(at: CGPoint(x: -80, y: 0)), 3)   // left
        XCTAssertEqual(wheel.segment(at: CGPoint(x: -10, y: 80)), 0)  // just left of top still top
    }

    func testHubAndFarOutsideAreNil() {
        XCTAssertNil(wheel.segment(at: CGPoint(x: 5, y: 5)))
        XCTAssertNil(wheel.segment(at: CGPoint(x: 0, y: 500)))
        XCTAssertNotNil(wheel.segment(at: CGPoint(x: 0, y: 140)))     // forgiving overshoot
        XCTAssertNil(WheelGeometry(count: 0, innerRadius: 10, outerRadius: 50).segment(at: CGPoint(x: 0, y: 30)))
    }

    func testKeyboardStepWraps() {
        XCTAssertEqual(wheel.step(from: nil, by: 1), 0)
        XCTAssertEqual(wheel.step(from: nil, by: -1), 3)
        XCTAssertEqual(wheel.step(from: 3, by: 1), 0)
        XCTAssertEqual(wheel.step(from: 0, by: -1), 3)
    }

    func testCenterAngles() {
        XCTAssertEqual(wheel.centerAngle(of: 0), .pi / 2, accuracy: 0.0001)
        XCTAssertEqual(wheel.centerAngle(of: 1), 0, accuracy: 0.0001)
    }

    func testModifierBindingPicksMostSpecific() {
        var binding = ModifierBinding.default
        XCTAssertEqual(binding.kind(for: .shift), .convert)
        XCTAssertEqual(binding.kind(for: .command), .tools)
        XCTAssertEqual(binding.kind(for: .control), .actions)
        XCTAssertNil(binding.kind(for: .option))
        XCTAssertNil(binding.kind(for: []))
        // Store listing variant: Option+Shift opens tools.
        binding.tools = NSEvent.ModifierFlags([.option, .shift]).rawValue
        XCTAssertEqual(binding.kind(for: [.option, .shift]), .tools)
        XCTAssertEqual(binding.kind(for: .shift), .convert)
        XCTAssertEqual(binding.kind(for: [.shift, .capsLock]), .convert)  // irrelevant flags ignored
    }

    func testKeyPressesReportedOncePerPress() {
        var keys = KeyPresses()
        XCTAssertEqual(keys.update(down: [124]), [124])
        XCTAssertEqual(keys.update(down: [124]), [])          // still held: no repeat
        XCTAssertEqual(keys.update(down: [124, 36]), [36])
        XCTAssertEqual(keys.update(down: []), [])
        XCTAssertEqual(keys.update(down: [124]), [124])       // pressed again
    }

    func testDragSessionOpensOnlyDuringFileDrag() {
        var session = DragSession()
        let binding = ModifierBinding.default
        session.mouseDown(pasteboardChangeCount: 10)
        // Shift without a drag: nothing.
        XCTAssertNil(session.update(pasteboardChangeCount: 10, hasFiles: true, flags: .shift, binding: binding))
        // Drag of text (no files): nothing.
        XCTAssertNil(session.update(pasteboardChangeCount: 11, hasFiles: false, flags: .shift, binding: binding))
        // File drag starts, no modifier yet.
        XCTAssertNil(session.update(pasteboardChangeCount: 12, hasFiles: true, flags: [], binding: binding))
        XCTAssertTrue(session.isDraggingFiles)
        // Tap shift -> convert wheel, once.
        XCTAssertEqual(session.update(pasteboardChangeCount: 12, hasFiles: true, flags: .shift, binding: binding), .convert)
        XCTAssertNil(session.update(pasteboardChangeCount: 12, hasFiles: true, flags: .shift, binding: binding))
        // Releasing keeps it open (tap, don't hold); switching modifier swaps wheels.
        XCTAssertNil(session.update(pasteboardChangeCount: 12, hasFiles: true, flags: [], binding: binding))
        XCTAssertEqual(session.visibleWheel, .convert)
        XCTAssertEqual(session.update(pasteboardChangeCount: 12, hasFiles: true, flags: .control, binding: binding), .actions)
        // Dismissed mid-drag (Escape): stays closed even with Shift held, until the next drag.
        session.dismiss()
        XCTAssertNil(session.update(pasteboardChangeCount: 12, hasFiles: true, flags: .shift, binding: binding))
        session.mouseDown(pasteboardChangeCount: 12)
        XCTAssertEqual(session.update(pasteboardChangeCount: 13, hasFiles: true, flags: .shift, binding: binding), .convert)
        session.mouseUp()
        XCTAssertNil(session.visibleWheel)
        XCTAssertFalse(session.isDraggingFiles)
    }
}

final class FileActionTests: XCTestCase {
    func testCopyFilesAndPaths() throws {
        let pasteboard = NSPasteboard(name: .init("kumquat-test-\(UUID())"))
        defer { pasteboard.releaseGlobally() }
        let a = try Fixtures.copy("txt"), b = try Fixtures.copy("md")
        FileActions.copyPaths([a, b], to: pasteboard)
        XCTAssertEqual(pasteboard.string(forType: .string), "\(a.path)\n\(b.path)")
        FileActions.copyFiles([a], to: pasteboard)
        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]
        XCTAssertEqual(urls?.map(\.standardizedFileURL), [a.standardizedFileURL])
    }

    func testMoveRenamesOnCollision() throws {
        let a = try Fixtures.copy("txt")
        let folder = try TempDir.make()
        try Data().write(to: folder.appendingPathComponent("sample.txt"))
        let moved = try FileActions.move([a], to: folder)
        XCTAssertEqual(moved.map(\.lastPathComponent), ["sample 2.txt"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: a.path))
    }

    func testTerminalDirectory() throws {
        let a = try Fixtures.copy("txt")
        XCTAssertEqual(FileActions.terminalDirectory(for: a).standardizedFileURL, a.deletingLastPathComponent().standardizedFileURL)
        XCTAssertEqual(FileActions.terminalDirectory(for: a.deletingLastPathComponent()).standardizedFileURL,
                       a.deletingLastPathComponent().standardizedFileURL)
    }
}

final class ParsingTests: XCTestCase {
    func testCSVRoundTripWithQuotes() {
        let rows = [["a", "b,c", "say \"hi\""], ["1", "", "line\nbreak"]]
        XCTAssertEqual(Spreadsheet.parseDelimited(Spreadsheet.formatDelimited(rows, separator: ","), separator: ","), rows)
        XCTAssertEqual(Spreadsheet.parseDelimited("x,y\r\n1,2\r\n", separator: ","), [["x", "y"], ["1", "2"]])
    }

    func testSubtitleTimes() {
        XCTAssertEqual(Subtitles.time("01:02:03,500"), 3723.5)
        XCTAssertEqual(Subtitles.time("02:03.250"), 123.25)
        XCTAssertNil(Subtitles.time("abc"))
        XCTAssertEqual(Subtitles.srt([Cue(start: 1, end: 2.5, text: "Hi")]), "1\n00:00:01,000 --> 00:00:02,500\nHi\n")
    }

    func testRangesAndTimes() throws {
        XCTAssertEqual(try parseRanges("1-2, 0:03-0:04.5"), [1...2, 3...4.5])
        XCTAssertThrowsError(try parseRanges("3-1"))
        XCTAssertEqual(try parseTime("1:30"), 90)
        XCTAssertEqual(try PDFTools.pageGroups("1-2, 3", pageCount: 3), [[0, 1], [2]])
        XCTAssertEqual(try Tools.pageEdits("2:90, 1", pageCount: 2), [.init(index: 1, rotation: 90), .init(index: 0)])
    }

    func testMarkdownRendering() {
        let html = Markdown.html("# T\n\nA **b** *i* `c` [l](http://x)\n\n1. one\n2. two\n\n> q")
        XCTAssertTrue(html.contains("<h1>T</h1>"))
        XCTAssertTrue(html.contains("<b>b</b>") && html.contains("<i>i</i>") && html.contains("<code>c</code>"))
        XCTAssertTrue(html.contains("<a href=\"http://x\">l</a>"))
        XCTAssertTrue(html.contains("<ol>") && html.contains("<blockquote>"))
        XCTAssertTrue(Markdown.html("<script>").contains("&lt;script&gt;"))
    }

    func testColumnNames() {
        XCTAssertEqual(OOXML.columnName(0), "A")
        XCTAssertEqual(OOXML.columnName(25), "Z")
        XCTAssertEqual(OOXML.columnName(26), "AA")
        XCTAssertEqual(OOXML.columnIndex("AB12"), 27)
    }
}

final class OpenInActionTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("openin-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("Project"), withIntermediateDirectories: true)
        for name in ["main.swift", "app.tsx", "photo.png", ".gitignore", "Makefile", "notes.pdf"] {
            try Data().write(to: dir.appendingPathComponent(name))
        }
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    private func url(_ name: String) -> URL { dir.appendingPathComponent(name) }

    func testFolderGetsTerminalAndITermButNotVSCode() {
        let actions = FileAction.applicable(to: [url("Project")], isInstalled: { _ in true })
        XCTAssertTrue(actions.contains(.terminal))
        XCTAssertTrue(actions.contains(.iTerm))
        XCTAssertFalse(actions.contains(.vsCode))
        XCTAssertEqual(FileAction.terminal.title(for: [url("Project")]), "Open folder in Terminal")
    }

    func testCodeFilesGetVSCodeButNotITerm() {
        for name in ["main.swift", "app.tsx", ".gitignore", "Makefile"] {
            let actions = FileAction.applicable(to: [url(name)], isInstalled: { _ in true })
            XCTAssertTrue(actions.contains(.vsCode), name)
            XCTAssertFalse(actions.contains(.iTerm), name)
        }
        XCTAssertEqual(FileAction.terminal.title(for: [url("main.swift")]), "Terminal")
    }

    func testOtherFilesGetNeither() {
        let actions = FileAction.applicable(to: [url("photo.png"), url("notes.pdf")], isInstalled: { _ in true })
        XCTAssertFalse(actions.contains(.vsCode))
        XCTAssertFalse(actions.contains(.iTerm))
    }

    func testMixedSelectionsAndMissingApps() {
        XCTAssertFalse(FileAction.applicable(to: [url("main.swift"), url("photo.png")], isInstalled: { _ in true }).contains(.vsCode))
        XCTAssertFalse(FileAction.applicable(to: [url("Project"), url("main.swift")], isInstalled: { _ in true }).contains(.iTerm))
        let none = FileAction.applicable(to: [url("Project")], isInstalled: { _ in false })
        XCTAssertFalse(none.contains(.iTerm))
        XCTAssertTrue(none.contains(.terminal)) // Terminal ships with macOS
    }

    func testActionsWheelOrder() {
        XCTAssertEqual(FileAction.applicable(to: [url("photo.png")], isInstalled: { _ in true }),
                       [.copy, .copyPath, .move, .float, .airDrop, .terminal])
    }

    func testOpenInEntriesForTheToolsWheel() {
        XCTAssertEqual(FileAction.openIn(for: [url("Project")], isInstalled: { _ in true }), [.terminal, .iTerm])
        XCTAssertEqual(FileAction.openIn(for: [url("main.swift")], isInstalled: { _ in true }), [.vsCode])
        XCTAssertEqual(FileAction.openIn(for: [url("photo.png")], isInstalled: { _ in true }), [])
    }
}
