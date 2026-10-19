import AppKit
import KumquatCore

/// Runs conversions/tools off the main thread and reports through the HUD.
final class JobRunner {
    private let hud = HUD()
    private let queue = DispatchQueue(label: "tully.converter.jobs", qos: .userInitiated, attributes: .concurrent)
    private let settings = ConverterSettings.shared

    func convert(_ urls: [URL], to target: String, near point: NSPoint) {
        run("Converting to \(Formats.label(for: target))…", near: point) {
            .files(try urls.map { try Converter.convert($0, to: target) })
        }
    }

    func runTool(_ tool: Tool, urls: [URL], params: ToolParams, near point: NSPoint) {
        run("\(tool.name)…", near: point) { try tool.run(urls, params: params) }
    }

    func run(_ title: String, near point: NSPoint, _ work: @escaping () throws -> ToolResult) {
        hud.show(.working(title), near: point)
        let outputFolder = settings.outputFolder // read on the main actor, before going to the job queue
        queue.async {
            let outcome = Result { try work() }.flatMap { result -> Result<ToolResult, Error> in
                guard case .files(let files) = result, let folder = outputFolder else { return .success(result) }
                return Result { .files(try Self.relocate(files, to: folder)) }
            }
            DispatchQueue.main.async { MainActor.assumeIsolated { self.finish(outcome, near: point) } }
        }
    }

    private func finish(_ outcome: Result<ToolResult, Error>, near point: NSPoint) {
        switch outcome {
        case .success(.files(let files)):
            settings.addRecents(files)
            hud.show(.done("Done", files), near: point)
            if settings.revealOutput { NSWorkspace.shared.activateFileViewerSelecting(files) }
        case .success(.message(let text)):
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            hud.show(.done("Copied to clipboard", []), near: point)
            let alert = NSAlert()
            alert.messageText = "Result"
            alert.informativeText = text
            NSApp.activate()
            alert.runModal()
        case .failure(let error):
            NSLog("File Converter job failed: \(error)")
            hud.show(.failed(error.localizedDescription), near: point)
        }
    }

    /// "Save to folder" setting: move outputs out of the source folder.
    static func relocate(_ files: [URL], to folder: URL) throws -> [URL] {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return try files.map { file in
            guard file.deletingLastPathComponent().standardizedFileURL != folder.standardizedFileURL else { return file }
            return try FileActions.move([file], to: folder)[0]
        }
    }
}
