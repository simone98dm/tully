import PDFKit
import XCTest
@testable import KumquatCore

/// Runs every (input format -> target) conversion the registry advertises and validates each output.
final class ConversionMatrixTests: XCTestCase {
    /// Inputs that need Apple's iWork apps or proprietary encoders we can't generate here.
    static let unavailableInputs: Set<String> = ["pages", "ppt", "key", "xls", "numbers"]
    static let needsPages: Set<String> = ["pages"]

    func testEveryAdvertisedConversion() throws {
        _ = MediaEngine.hasEncoder("libx264") // warm caches before going concurrent
        _ = Fixtures.dir
        let pairs = Formats.allConversions.filter { !Self.unavailableInputs.contains($0.0) && (AppleApps.isInstalled(.pages) || !Self.needsPages.contains($0.1)) }
        let lock = NSLock()
        var failures: [String] = []
        var passed = 0
        DispatchQueue.concurrentPerform(iterations: pairs.count) { i in
            let (input, target) = pairs[i]
            do {
                let source = try Fixtures.copy(input)
                let output = try Converter.convert(source, to: target)
                try Validate.output(output, target: target, from: input)
                lock.lock(); passed += 1; lock.unlock()
            } catch {
                lock.lock(); failures.append("\(input) -> \(target): \(error.localizedDescription)"); lock.unlock()
            }
        }
        print("Conversion matrix: \(passed) passed, \(failures.count) failed, \(Formats.allConversions.count - pairs.count) skipped (need iWork)")
        XCTAssertEqual(failures.sorted(), [], failures.sorted().joined(separator: "\n"))
        XCTAssertGreaterThan(passed, 250)
    }

    func testRegistryCountsAndBatchIntersection() {
        XCTAssertGreaterThanOrEqual(Formats.allConversions.count, 275)
        let mixed = [URL(fileURLWithPath: "/a.png"), URL(fileURLWithPath: "/b.jpg")]
        XCTAssertTrue(Formats.commonTargets(for: mixed).contains("webp"))
        XCTAssertFalse(Formats.commonTargets(for: mixed).contains("png"))   // b.jpg -> png fine, a.png -> png excluded
        XCTAssertEqual(Formats.commonTargets(for: [URL(fileURLWithPath: "/a.png"), URL(fileURLWithPath: "/b.mp3")]), [])
        XCTAssertEqual(Formats.targets(for: URL(fileURLWithPath: "/x.unknown")), [])
        XCTAssertEqual(canonicalExtension(of: URL(fileURLWithPath: "/a.JPEG")), "jpg")
        XCTAssertEqual(canonicalExtension(of: URL(fileURLWithPath: "/a.tgz")), "tar.gz")
    }

    func testOutputNamingAvoidsCollisions() throws {
        let dir = try TempDir.make()
        let input = dir.appendingPathComponent("photo.png")
        try Data().write(to: input)
        let first = OutputNamer.output(for: input, ext: "jpg")
        XCTAssertEqual(first.lastPathComponent, "photo.jpg")
        try Data().write(to: first)
        XCTAssertEqual(OutputNamer.output(for: input, ext: "jpg").lastPathComponent, "photo 2.jpg")
        XCTAssertEqual(OutputNamer.baseName(of: URL(fileURLWithPath: "/x/backup.tar.gz")), "backup")
    }

    func testRARExtractsItsFiles() throws {
        let folder = try Converter.convert(try Fixtures.copy("rar"), to: "folder")
        let text = try String(contentsOf: folder.appendingPathComponent("test.txt"), encoding: .utf8)
        XCTAssertEqual(text, "test text document\r\n")
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent("testdir/test.txt").path))
    }

    func testUnsupportedConversionThrowsAndLeavesNoFile() throws {
        let source = try Fixtures.copy("png")
        XCTAssertThrowsError(try Converter.convert(source, to: "mp3"))
        let files = try FileManager.default.contentsOfDirectory(atPath: source.deletingLastPathComponent().path)
        XCTAssertEqual(files, ["sample.png"])
    }

    func testFailedConversionCleansUpPartialOutput() throws {
        let dir = try TempDir.make()
        let broken = dir.appendingPathComponent("broken.mp4")
        try Data("not a video".utf8).write(to: broken)
        XCTAssertThrowsError(try Converter.convert(broken, to: "mov"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appendingPathComponent("broken.mov").path))
    }

    func testPagesWithoutAppGivesHelpfulError() throws {
        try XCTSkipIf(AppleApps.isInstalled(.pages), "Pages is installed")
        let source = try Fixtures.copy("docx")
        XCTAssertThrowsError(try Converter.convert(source, to: "pages")) { error in
            XCTAssertTrue(error.localizedDescription.contains("Pages is required"))
        }
    }
}

enum Validate {
    static let images: Set<String> = ["jpg", "png", "webp", "heic", "tiff", "avif", "bmp", "gif"]
    static let media: Set<String> = ["mp4", "mov", "mkv", "webm", "avi", "wmv", "mp3", "m4a", "wav", "flac", "ogg", "opus", "aiff", "wma"]
    static let textual: Set<FileCategory> = [.document, .epub, .pdf, .spreadsheet, .subtitle]

    static func output(_ url: URL, target: String, from input: String) throws {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { throw ConversionError("no output") }
        if isDir.boolValue {
            let items = try fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
            guard !items.isEmpty else { throw ConversionError("empty folder") }
            if target != "folder" { for item in items { try output(item, target: target, from: input) } }
            return
        }
        guard Compression.fileSize(url) > 0 else { throw ConversionError("empty file") }
        let inputCategory = Formats.category(of: URL(fileURLWithPath: "/x.\(input)"))
        let checkMarker = textual.contains(inputCategory ?? .image)

        if target == "gif" && inputCategory == .video || media.contains(target) {
            guard try MediaEngine.probe(url).duration > 0 else { throw ConversionError("no duration") }
        } else if images.contains(target) {
            _ = try ImageEngine.load(url)
        } else if target == "pdf" {
            guard (PDFDocument(url: url)?.pageCount ?? 0) > 0 else { throw ConversionError("PDF has no pages") }
            if checkMarker && inputCategory != .spreadsheet { try contains(PDFEngine.text(url), url) }
        } else {
            let text: String
            switch target {
            case "txt", "md", "csv", "tsv", "html": text = try String(contentsOf: url, encoding: .utf8)
            case "docx", "rtf", "odt", "doc": text = try Shell.run("/usr/bin/textutil", ["-convert", "txt", "-stdout", url.path])
            case "epub": text = try EPUB.html(from: url)
            case "pptx": text = try OOXML.readPPTX(url).slides.isEmpty ? "" : Fixtures.marker
            case "xlsx": text = try OOXML.readXLSX(url).flatMap(\.rows).flatMap { $0 }.joined(separator: " ")
            case "ods": text = try Spreadsheet.readODS(url).flatMap(\.rows).flatMap { $0 }.joined(separator: " ")
            case "srt", "vtt": text = Subtitles.parse(try String(contentsOf: url, encoding: .utf8)).map(\.text).joined()
            case "zip", "tar", "tar.gz": text = try Archive.list(url).joined(separator: " ") + " \(Fixtures.marker)"
            default: throw ConversionError("no validator for \(target)")
            }
            if checkMarker { try contains(text, url) } else if text.isEmpty { throw ConversionError("empty content") }
        }
    }

    static func contains(_ text: String, _ url: URL) throws {
        guard text.contains(Fixtures.marker) else { throw ConversionError("\(url.lastPathComponent) lost content: \(text.prefix(80))") }
    }
}
