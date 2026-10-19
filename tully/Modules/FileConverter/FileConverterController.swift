import AppKit
import KumquatCore
import SwiftUI

/// The File Converter feature: drag wheels, menu entry points and dispatch of conversions, tools
/// and file actions. Everything runs locally.
@Observable
final class FileConverterController: NSObject {
    let settings: ConverterSettings
    @ObservationIgnored private let monitor = DragMonitor()
    @ObservationIgnored private let jobs = JobRunner()
    @ObservationIgnored private let windows = WindowPresenter()
    /// Creates the global mouse monitors; injectable so tests can count starts/stops.
    @ObservationIgnored private let startMonitor: (DragMonitor) -> Void
    @ObservationIgnored private let stopMonitor: (DragMonitor) -> Void

    init(settings: ConverterSettings = .shared,
         startMonitor: @escaping (DragMonitor) -> Void = { $0.start() },
         stopMonitor: @escaping (DragMonitor) -> Void = { $0.stop() }) {
        self.settings = settings
        self.startMonitor = startMonitor
        self.stopMonitor = stopMonitor
        super.init()
        monitor.onChoose = { [weak self] kind, id, urls, point in self?.perform(kind, id, urls, point) }
        monitor.onMore = { [weak self] kind, items, urls, point in self?.showList(kind, items, urls, point) }
    }

    private(set) var isRunning = false

    /// Starts or stops watching drags to match the master switch.
    func apply(showOnboarding: Bool = true) {
        if settings.isEnabled, !isRunning {
            startMonitor(monitor)
            isRunning = true
            if showOnboarding, !settings.hasOnboarded { showOnboardingWindow() }
        } else if !settings.isEnabled, isRunning {
            stopMonitor(monitor)
            isRunning = false
        }
    }

    func setEnabled(_ enabled: Bool) {
        settings.isEnabled = enabled
        apply()
    }

    // MARK: Menu (right-click on the status item)

    /// Items for tully's menu; empty while the converter is off.
    func menuItems() -> [NSMenuItem] {
        guard settings.isEnabled else { return [] }
        let header = NSMenuItem(title: "File Converter", action: nil, keyEquivalent: "")
        header.isEnabled = false
        let recents = NSMenuItem(title: "Recent Conversions", action: nil, keyEquivalent: "")
        recents.image = NSImage(systemSymbolName: "clock", accessibilityDescription: nil)
        recents.submenu = recentsMenu()
        return [
            header,
            item("Convert Files…", #selector(chooseConvert), "o", symbol: "arrow.triangle.2.circlepath"),
            item("File Tools…", #selector(chooseTools), "t", symbol: "wrench.and.screwdriver"),
            item("File Actions…", #selector(chooseActions), "", symbol: "square.and.arrow.up"),
            recents,
            item("How File Converter Works", #selector(showOnboarding), "", symbol: "questionmark.circle"),
        ]
    }

    private func recentsMenu() -> NSMenu {
        let sub = NSMenu()
        let existing = settings.recents.filter { FileManager.default.fileExists(atPath: $0) }
        if existing.isEmpty {
            let none = NSMenuItem(title: "No recent files", action: nil, keyEquivalent: "")
            none.isEnabled = false
            sub.addItem(none)
        }
        for path in existing {
            let entry = item((path as NSString).lastPathComponent, #selector(revealRecent(_:)), "")
            entry.representedObject = path
            entry.image = IconCache.icon(forFile: path)
            entry.image?.size = NSSize(width: 16, height: 16)
            sub.addItem(entry)
        }
        if !existing.isEmpty {
            sub.addItem(.separator())
            sub.addItem(item("Clear Recents", #selector(clearRecents), ""))
        }
        return sub
    }

    private func item(_ title: String, _ action: Selector, _ key: String, symbol: String? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        item.image = symbol.flatMap { NSImage(systemSymbolName: $0, accessibilityDescription: nil) }
        return item
    }

    @objc private func revealRecent(_ sender: NSMenuItem) {
        guard let path = sender.representedObject as? String else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    @objc private func clearRecents() { settings.clearRecents() }

    // Menu entry points: same wheels' options without a drag (keyboard / accessibility path).
    @objc func chooseConvert() { pickFiles(.convert) }
    @objc func chooseTools() { pickFiles(.tools) }
    @objc func chooseActions() { pickFiles(.actions) }

    private func pickFiles(_ kind: WheelKind) {
        NSApp.activate()
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = kind != .convert
        panel.message = "Choose files to \(kind == .convert ? "convert" : kind == .tools ? "process" : "act on")"
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }
        offer(kind, for: panel.urls, at: NSEvent.mouseLocation)
    }

    /// Shows every option of a wheel for some files as a menu (also used by the popover drop zone).
    func offer(_ kind: WheelKind, for urls: [URL], at point: NSPoint) {
        showList(kind, DragMonitor.items(for: kind, urls: urls), urls, point)
    }

    @objc func showOnboarding() { showOnboardingWindow() }

    private func showOnboardingWindow() {
        windows.present("File Converter", size: NSSize(width: 460, height: 420)) { [settings] close in
            OnboardingView { settings.hasOnboarded = true; close() }
        }
    }

    // MARK: Full option list (More… / Enter / menu)

    @ObservationIgnored private var listContext: (WheelKind, [URL], NSPoint)?

    private func showList(_ kind: WheelKind, _ items: [WheelItem], _ urls: [URL], _ point: NSPoint) {
        let menu = NSMenu(title: kind.title)
        if items.isEmpty {
            let none = NSMenuItem(title: "Nothing available for \(urls.count == 1 ? urls[0].lastPathComponent : "these files")", action: nil, keyEquivalent: "")
            none.isEnabled = false
            menu.addItem(none)
        }
        for wheelItem in items where wheelItem.id != "__more" {
            let entry = NSMenuItem(title: wheelItem.label, action: #selector(listChosen(_:)), keyEquivalent: "")
            entry.target = self
            entry.representedObject = wheelItem.id
            entry.image = NSImage(systemSymbolName: wheelItem.symbol, accessibilityDescription: nil)
            menu.addItem(entry)
        }
        listContext = (kind, urls, point)
        NSApp.activate()
        menu.popUp(positioning: nil, at: point, in: nil)
    }

    @objc private func listChosen(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String, let (kind, urls, point) = listContext else { return }
        perform(kind, id, urls, point)
    }

    // MARK: Dispatch

    private func perform(_ kind: WheelKind, _ id: String, _ urls: [URL], _ point: NSPoint) {
        switch kind {
        case .convert: jobs.convert(urls, to: id, near: point)
        case .tools:
            if let tool = Tools.tool(id) {
                open(tool, urls, point)
            } else if let action = FileAction(rawValue: id) {
                run(action, urls, point) // "open in" entries on the Tools wheel
            }
        case .actions: if let action = FileAction(rawValue: id) { run(action, urls, point) }
        }
    }

    private func open(_ tool: Tool, _ urls: [URL], _ point: NSPoint) {
        switch tool.editor {
        case .photo(let mode):
            windows.present(tool.name, size: NSSize(width: 760, height: 640)) { [jobs] close in
                PhotoEditorView(url: urls[0], mode: mode, onSave: { edit in
                    close()
                    let json = String(decoding: (try? JSONEncoder().encode(edit)) ?? Data("{}".utf8), as: UTF8.self)
                    jobs.runTool(tool, urls: urls, params: ["edit": json], near: point)
                }, onCancel: close)
            }
        case .pdfPages:
            windows.present("\(tool.name) — \(urls[0].lastPathComponent)", size: NSSize(width: 520, height: 560)) { [jobs] close in
                PDFPagesView(url: urls[0], onSave: { order in
                    close()
                    jobs.runTool(tool, urls: [urls[0]], params: ["order": order], near: point)
                }, onCancel: close)
            }
        case nil where tool.parameters(for: urls).isEmpty:
            jobs.runTool(tool, urls: urls, params: [:], near: point)
        case nil:
            // Header + buttons, plus one grouped-form row per parameter.
            let height = 170 + 56 * CGFloat(tool.parameters(for: urls).count)
            windows.present(tool.name, size: NSSize(width: 440, height: height)) { [jobs] close in
                ToolForm(tool: tool, urls: urls, onRun: { params in
                    close()
                    jobs.runTool(tool, urls: urls, params: params, near: point)
                }, onCancel: close)
            }
        }
    }

    private func run(_ action: FileAction, _ urls: [URL], _ point: NSPoint) {
        switch action {
        case .airDrop:
            NSApp.activate()
            guard let service = NSSharingService(named: .sendViaAirDrop), service.canPerform(withItems: urls) else {
                return alert("AirDrop isn't available", "Turn on Wi-Fi and Bluetooth, then try again.")
            }
            service.perform(withItems: urls)
        case .float: FloatPanel.show(urls, near: point)
        case .copy: FileActions.copyFiles(urls)
        case .copyPath: FileActions.copyPaths(urls)
        case .terminal:
            do { try FileActions.openTerminal(at: urls[0]) } catch { alert("Couldn't open Terminal", error.localizedDescription) }
        case .move: showMoveMenu(urls, point)
        case .iTerm, .vsCode:
            do { try FileActions.open(urls, for: action) } catch { alert("Couldn't open \(action == .iTerm ? "iTerm2" : "VS Code")", error.localizedDescription) }
        }
    }

    // MARK: Move: a folder menu at the drop point (menus take input without activating this menu bar app)

    @ObservationIgnored private var pendingMove: [URL] = []

    private func showMoveMenu(_ urls: [URL], _ point: NSPoint) {
        pendingMove = urls
        let menu = NSMenu(title: "Move To")
        let standard: [FileManager.SearchPathDirectory] = [.desktopDirectory, .documentDirectory, .downloadsDirectory]
        let folders = settings.moveFolders + standard.map { FileManager.default.urls(for: $0, in: .userDomainMask)[0].path }
        var seen = Set<String>()
        let sources = Set(urls.map { $0.deletingLastPathComponent().path })
        for path in folders where FileManager.default.fileExists(atPath: path) && !sources.contains(path) && seen.insert(path).inserted {
            let entry = NSMenuItem(title: (path as NSString).lastPathComponent, action: #selector(moveChosen(_:)), keyEquivalent: "")
            entry.target = self
            entry.representedObject = path
            entry.toolTip = path
            entry.image = IconCache.icon(forFile: path)
            entry.image?.size = NSSize(width: 16, height: 16)
            menu.addItem(entry)
        }
        menu.addItem(.separator())
        menu.addItem(item("Other…", #selector(moveToOther), ""))
        NSApp.activate()
        menu.popUp(positioning: nil, at: point, in: nil)
    }

    @objc private func moveChosen(_ sender: NSMenuItem) {
        guard let path = sender.representedObject as? String else { return }
        move(pendingMove, to: URL(fileURLWithPath: path))
    }

    @objc private func moveToOther() {
        NSApp.activate()
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Move Here"
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        move(pendingMove, to: folder)
    }

    private func move(_ urls: [URL], to folder: URL) {
        do {
            settings.addRecents(try FileActions.move(urls, to: folder))
            settings.addMoveFolder(folder)
        } catch { alert("Couldn't move files", error.localizedDescription) }
    }

    private func alert(_ title: String, _ message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        NSApp.activate()
        alert.runModal()
    }
}
