import AppKit
import KumquatCore
import Testing
@testable import tully

@MainActor
struct FileConverterTests {
    final class Counts {
        var starts = 0
        var stops = 0
    }

    func makeController(defaults: UserDefaults = makeDefaults()) -> (FileConverterController, Counts) {
        let counts = Counts()
        let controller = FileConverterController(
            settings: ConverterSettings(defaults: defaults),
            startMonitor: { _ in counts.starts += 1 },
            stopMonitor: { _ in counts.stops += 1 }
        )
        return (controller, counts)
    }

    @Test func onByDefaultAndStartsMonitoring() {
        let (controller, counts) = makeController()
        #expect(controller.settings.isEnabled)
        controller.settings.hasOnboarded = true
        controller.apply()
        #expect(controller.isRunning && counts.starts == 1)
        controller.apply() // idempotent
        #expect(counts.starts == 1)
    }

    @Test func switchingOffRemovesMonitorsAndMenuItems() {
        let (controller, counts) = makeController()
        controller.settings.hasOnboarded = true
        controller.apply()
        #expect(!controller.menuItems().isEmpty)
        controller.setEnabled(false)
        #expect(!controller.isRunning && counts.stops == 1)
        #expect(controller.menuItems().isEmpty)
        controller.setEnabled(true)
        #expect(controller.isRunning && counts.starts == 2)
    }

    @Test func offStatePersists() {
        let defaults = makeDefaults()
        let (controller, _) = makeController(defaults: defaults)
        controller.setEnabled(false)
        #expect(!ConverterSettings(defaults: defaults).isEnabled)
    }

    @Test func menuOffersEveryEntryPoint() {
        let (controller, _) = makeController()
        let titles = controller.menuItems().map(\.title)
        #expect(titles.contains("Convert Files…"))
        #expect(titles.contains("File Tools…"))
        #expect(titles.contains("File Actions…"))
        #expect(titles.contains("Recent Conversions"))
    }

    @Test func keysArePrefixedAndOldKumquatKeysIgnored() {
        let defaults = makeDefaults()
        defaults.set(true, forKey: "hasOnboarded")   // Kumquat's unprefixed key
        defaults.set(["/old"], forKey: "recents")
        let settings = ConverterSettings(defaults: defaults)
        #expect(!settings.hasOnboarded && settings.recents.isEmpty)
        settings.revealOutput = true
        #expect(defaults.bool(forKey: "tully.converter.revealOutput"))
        #expect(defaults.object(forKey: "revealOutput") == nil)
    }

    @Test func recentsAreUniqueAndCapped() {
        let settings = ConverterSettings(defaults: makeDefaults())
        let urls = (0..<15).map { URL(fileURLWithPath: "/tmp/file\($0)") }
        settings.addRecents(urls)
        settings.addRecents([urls[14]])
        #expect(settings.recents.count == ConverterSettings.recentsLimit)
        #expect(settings.recents.first == urls[14].path)
        #expect(Set(settings.recents).count == settings.recents.count)
    }

    @Test func bindingConflictAndReset() {
        let settings = ConverterSettings(defaults: makeDefaults())
        #expect(!settings.hasConflict)
        settings.binding.tools = settings.binding.convert
        #expect(settings.hasConflict)
        settings.reset()
        #expect(settings.binding == .default && settings.isEnabled)
    }

    @Test func wheelItemsComeFromTheEngine() {
        let png = URL(fileURLWithPath: "/tmp/photo.png")
        #expect(!DragMonitor.items(for: .convert, urls: [png]).isEmpty)
        let ids = DragMonitor.items(for: .actions, urls: [png]).map(\.id)
        #expect(ids.contains("terminal") && !ids.contains("vsCode") && !ids.contains("iTerm"))
        // a folder gets folder wording on the Terminal action
        let folder = FileManager.default.temporaryDirectory
        let labels = DragMonitor.items(for: .actions, urls: [folder]).map(\.label)
        #expect(labels.contains("Open folder in Terminal"))
        #expect(!labels.contains("Open in VS Code"))
    }
}

@MainActor
struct FileConverterMenuTests {
    @Test func symbolsForEveryTargetCategory() {
        for target in ["jpg", "mp4", "mp3", "pdf", "xlsx", "srt", "zip", "folder", "pptx", "docx", "md"] {
            let symbol = DragMonitor.symbol(forTarget: target)
            #expect(NSImage(systemSymbolName: symbol, accessibilityDescription: nil) != nil, "\(target) → \(symbol)")
        }
    }

    @Test func toolsWheelOffersOpenInForFoldersAndCode() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("tully-openin-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let js = dir.appendingPathComponent("app.js")
        try Data().write(to: js)
        let folderLabels = DragMonitor.items(for: .tools, urls: [dir]).map(\.label)
        #expect(folderLabels.first == "Open folder in Terminal")
        #expect(folderLabels.contains("Zip"))
        let jsIDs = DragMonitor.items(for: .tools, urls: [js]).map(\.id)
        #expect(!jsIDs.contains("terminal"))
        if FileActions.isInstalled("com.microsoft.VSCode") { #expect(jsIDs.first == "vsCode") }
    }

    @Test func toolsAndBatchItems() {
        let pngs = [URL(fileURLWithPath: "/tmp/a.png"), URL(fileURLWithPath: "/tmp/b.png")]
        #expect(!DragMonitor.items(for: .tools, urls: pngs).isEmpty)
        #expect(DragMonitor.items(for: .convert, urls: pngs).map(\.id).contains("jpg"))
    }

    @Test func recentsSubmenuListsExistingFiles() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("tully-recent-\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: file) }
        try Data("x".utf8).write(to: file)
        let settings = ConverterSettings(defaults: makeDefaults())
        settings.addRecents([file, URL(fileURLWithPath: "/nonexistent/gone.txt")])
        let controller = FileConverterController(settings: settings, startMonitor: { _ in }, stopMonitor: { _ in })
        let recents = controller.menuItems().first { $0.title == "Recent Conversions" }?.submenu
        let titles = recents?.items.map(\.title) ?? []
        #expect(titles.contains(file.lastPathComponent))
        #expect(!titles.contains("gone.txt"))
        #expect(titles.contains("Clear Recents"))
    }

    @Test func dragMonitorStartStop() {
        let monitor = DragMonitor()
        monitor.start()
        #expect(monitor.isRunning)
        monitor.stop()
        #expect(!monitor.isRunning)
    }
}
