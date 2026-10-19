import PDFKit
import XCTest
@testable import KumquatCore

final class ToolTests: XCTestCase {
    func run(_ id: String, _ urls: [URL], _ params: ToolParams = [:]) throws -> [URL] {
        let tool = try XCTUnwrap(Tools.tool(id), "missing tool \(id)")
        XCTAssertTrue(tool.applies(to: urls), "\(id) should apply to \(urls.map(\.lastPathComponent))")
        guard case .files(let files) = try tool.run(urls, params: params) else { XCTFail("expected files"); return [] }
        for file in files { XCTAssertTrue(FileManager.default.fileExists(atPath: file.path), file.path) }
        return files
    }

    func size(_ url: URL) -> Int { Compression.fileSize(url) }
    func dims(_ url: URL) throws -> (Int, Int) { let i = try ImageEngine.load(url); return (i.width, i.height) }
    func duration(_ url: URL) throws -> Double { try MediaEngine.probe(url).duration }
    func channels(_ url: URL) throws -> Int {
        Int(try Shell.ffprobe(["-select_streams", "a:0", "-show_entries", "stream=channels", "-of", "csv=p=0", url.path])
            .trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
    }
    func pixel(_ image: CGImage, _ x: Int, _ y: Int) -> (Int, Int, Int) {
        let ctx = ImageEngine.context(width: image.width, height: image.height)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let data = ctx.data!.assumingMemoryBound(to: UInt8.self)
        let o = y * ctx.bytesPerRow + x * 4   // bitmap memory is top-down: row 0 = top
        return (Int(data[o]), Int(data[o + 1]), Int(data[o + 2]))
    }

    // MARK: Compression

    func testCompressPercentHitsTargetForImages() throws {
        for ext in ["jpg", "png", "heic"] {
            let input = try Fixtures.copy(ext)
            let out = try run("compress", [input], ["percent": "40"])[0]
            XCTAssertLessThanOrEqual(size(out), size(input) * 40 / 100 + 1, ext)
        }
    }

    func testCompressToSizeDefaultWorksForSmallFiles() throws {
        let png = try Fixtures.copy("png")   // a few KB
        let out = try run("compress-size", [png])[0]
        XCTAssertLessThanOrEqual(size(out), size(png) / 2 + 1000)
    }

    func testCompressRefusesToGrowFile() throws {
        let dir = try TempDir.make()
        let tiny = dir.appendingPathComponent("tiny.png")
        let ctx = ImageEngine.context(width: 4, height: 4)!
        try ImageEngine.write(ctx.makeImage()!, to: tiny, ext: "png")
        XCTAssertThrowsError(try Tools.tool("compress")!.run([tiny], params: ["percent": "50"])) { error in
            XCTAssertTrue(error.localizedDescription.contains("can't be made any smaller"))
        }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: dir.path), ["tiny.png"])
    }

    func testCompressVideoAudioAndPDF() throws {
        let video = try Fixtures.copy("mp4")
        let v = try run("compress", [video], ["percent": "50"])[0]
        XCTAssertLessThan(size(v), size(video))
        XCTAssertGreaterThan(try duration(v), 1.5)

        let wav = try Fixtures.copy("wav")
        let a = try run("compress", [wav], ["percent": "20"])[0]
        XCTAssertEqual(a.pathExtension, "m4a")
        XCTAssertLessThanOrEqual(size(a), size(wav) / 5)

        // Image-heavy PDF: lossless PNG pages shrink a lot as JPEG.
        let png = try Fixtures.copy("png")
        let big = try ImageTools.resize(png, percent: 400)
        let pdf = try run("images-pdf", [big])[0]
        let small = try run("compress-size", [pdf], ["size": String(Double(size(pdf)) * 0.3 / 1_000_000)])[0]
        XCTAssertLessThanOrEqual(size(small), Int(Double(size(pdf)) * 0.3) + 1)
        XCTAssertEqual(PDFDocument(url: small)?.pageCount, 1)
    }

    // MARK: Image tools

    func testResizeRotateFlip() throws {
        let png = try Fixtures.copy("png")
        XCTAssertTrue(try dims(run("resize", [png], ["percent": "50"])[0]) == (200, 150))
        XCTAssertTrue(try dims(run("rotate", [png], ["angle": "90° Right"])[0]) == (300, 400))
        let flipped = try ImageEngine.load(run("flip", [png], ["axis": "Horizontal"])[0])
        let original = try ImageEngine.load(png)
        XCTAssertEqual(pixel(original, 10, 150).0, 255)        // orange on the left
        XCTAssertEqual(pixel(flipped, 389, 150).0, 255)        // now on the right
        XCTAssertLessThan(pixel(flipped, 10, 290).0, 100)     // bottom-left of flipped = bottom-right of original (dark/transparent)
    }

    func testPhotoEditorCropAdjustAnnotateRedact() throws {
        let png = try Fixtures.copy("png")
        func apply(_ id: String, _ edit: PhotoEdit) throws -> CGImage {
            let json = String(decoding: try JSONEncoder().encode(edit), as: UTF8.self)
            return try ImageEngine.load(run(id, [png], ["edit": json])[0])
        }
        var crop = PhotoEdit(); crop.crop = CGRect(x: 0, y: 0, width: 0.5, height: 0.5)
        let cropped = try apply("crop", crop)
        XCTAssertEqual(cropped.width, 200); XCTAssertEqual(cropped.height, 150)
        XCTAssertEqual(pixel(cropped, 100, 75).0, 255)   // top-left quadrant is orange

        var adjust = PhotoEdit(); adjust.saturation = 0
        let gray = pixel(try apply("adjust", adjust), 10, 150)
        XCTAssertLessThan(abs(gray.0 - gray.2), 10)

        var annotate = PhotoEdit()
        var box = PhotoEdit.Shape(kind: .rectangle, rect: CGRect(x: 0.1, y: 0.1, width: 0.3, height: 0.3), color: "#00FF00")
        box.lineWidth = 0.02
        annotate.shapes = [box]
        let annotated = try apply("annotate", annotate)
        XCTAssertGreaterThan(pixel(annotated, 40, 60).1, 200)   // on the left edge of the green stroke

        var redact = PhotoEdit()
        redact.shapes = [.init(kind: .blackout, rect: CGRect(x: 0, y: 0, width: 0.25, height: 0.25)),
                         .init(kind: .pixelate, rect: CGRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5))]
        XCTAssertTrue(pixel(try apply("redact", redact), 20, 20) == (0, 0, 0))
    }

    func testReadQRCode() throws {
        guard case .message(let text) = try Tools.tool("qr")!.run([try Fixtures.copy("png")]) else { return XCTFail() }
        XCTAssertEqual(text, "https://example.com/Kumquat")
    }

    func testImagesToPDFAndCollage() throws {
        let a = try Fixtures.copy("png"), b = try Fixtures.copy("jpg")
        XCTAssertEqual(PDFDocument(url: try run("images-pdf", [a, b])[0])?.pageCount, 2)
        let collage = try run("collage", [a, b], ["columns": "2"])[0]
        XCTAssertTrue(try dims(collage) == (2 * 800 + 3 * 16, 800 + 2 * 16))
    }

    // MARK: Metadata

    func testMetadataEditAndStrip() throws {
        let jpg = try Fixtures.copy("jpg")
        let edited = try run("metadata", [jpg], ["title": "Sunset", "artist": "Ada", "copyright": "CC0"])[0]
        XCTAssertEqual(try Metadata.read(edited)["artist"], "Ada")
        XCTAssertEqual(try Metadata.read(edited)["title"], "Sunset")
        XCTAssertNil(try Metadata.read(run("strip", [edited])[0])["artist"])

        let mp3 = try Fixtures.copy("mp3")
        let tagged = try run("metadata", [mp3], ["title": "Song", "artist": "Band"])[0]
        XCTAssertEqual(try Metadata.read(tagged)["title"], "Song")
        XCTAssertNil(try Metadata.read(run("strip", [tagged])[0])["title"])

        let pdf = try Fixtures.copy("pdf")
        let titled = try run("metadata", [pdf], ["title": "Report", "keywords": "a, b"])[0]
        XCTAssertEqual(try Metadata.read(titled)["title"], "Report")
        XCTAssertEqual(try Metadata.read(titled)["keywords"], "a, b")
        XCTAssertNil(try Metadata.read(run("strip", [titled])[0])["title"])

        // Parameter defaults are prefilled from the current values.
        let fields = Tools.tool("metadata")!.parameters(for: [titled])
        XCTAssertEqual(fields.first { $0.id == "title" }?.defaultValue, "Report")
    }

    // MARK: Media tools

    func testTrimSpeedSplitJoin() throws {
        let mp4 = try Fixtures.copy("mp4")
        XCTAssertEqual(try duration(run("trim", [mp4], ["start": "0.5", "end": "0:01.5"])[0]), 1.0, accuracy: 0.15)
        XCTAssertEqual(try duration(run("speed", [mp4], ["factor": "2x"])[0]), 1.0, accuracy: 0.15)
        let parts = try run("split", [mp4], ["mode": "Into equal parts", "value": "2"])
        XCTAssertEqual(parts.count, 2)
        XCTAssertEqual(try duration(parts[0]), 1.0, accuracy: 0.2)
        XCTAssertEqual(try duration(run("join", [mp4, try Fixtures.copy("mov")])[0]), 4.0, accuracy: 0.3)
        XCTAssertEqual(try duration(run("join", [try Fixtures.copy("mp3"), try Fixtures.copy("wav")])[0]), 4.0, accuracy: 0.3)
        XCTAssertEqual(try duration(run("speed", [try Fixtures.copy("m4a")], ["factor": "4x"])[0]), 0.5, accuracy: 0.1)
    }

    func testCropSnapshotMuteRotateFlipVideo() throws {
        let mp4 = try Fixtures.copy("mp4")
        let square = try MediaEngine.probe(run("crop-video", [mp4], ["aspect": "1:1"])[0])
        XCTAssertEqual(square.width, 240); XCTAssertEqual(square.height, 240)
        let custom = try MediaEngine.probe(run("crop-video", [mp4], ["aspect": "Custom", "custom": "100:80:10:10"])[0])
        XCTAssertEqual(custom.width, 100); XCTAssertEqual(custom.height, 80)
        XCTAssertTrue(try dims(run("snapshot", [mp4], ["time": "1", "format": "PNG"])[0]) == (320, 240))
        XCTAssertFalse(try MediaEngine.probe(run("mute", [mp4])[0]).hasAudio)
        let rotated = try MediaEngine.probe(run("rotate", [mp4], ["angle": "90° Left"])[0])
        XCTAssertEqual(rotated.width, 240); XCTAssertEqual(rotated.height, 320)
        XCTAssertEqual(try run("flip", [mp4], ["axis": "Vertical"]).count, 1)
    }

    func testNormalizeBleepChannels() throws {
        let wav = try Fixtures.copy("wav")
        XCTAssertTrue(try MediaEngine.probe(run("normalize", [wav])[0]).hasAudio)
        let bleeped = try run("bleep", [wav], ["ranges": "0.5-1.0"])[0]
        XCTAssertEqual(try duration(bleeped), 2.0, accuracy: 0.1)
        XCTAssertNotEqual(try Data(contentsOf: bleeped), try Data(contentsOf: wav))
        XCTAssertEqual(try run("bleep", [try Fixtures.copy("mp4")], ["ranges": "0:00.2-0:00.6"]).count, 1)
        XCTAssertEqual(try channels(run("channels", [wav], ["mode": "Mono"])[0]), 1)
        XCTAssertEqual(try channels(run("channels", [wav], ["mode": "Swap Left/Right"])[0]), 2)
    }

    func testInvalidParametersThrowReadableErrors() throws {
        let mp4 = try Fixtures.copy("mp4")
        XCTAssertThrowsError(try Tools.tool("trim")!.run([mp4], params: ["start": "2", "end": "1"]))
        XCTAssertThrowsError(try Tools.tool("trim")!.run([mp4], params: ["start": "abc"]))
        XCTAssertThrowsError(try Tools.tool("bleep")!.run([mp4], params: ["ranges": "5"]))
        XCTAssertThrowsError(try Tools.tool("split-pdf")!.run([try Fixtures.copy("pdf")], params: ["ranges": "1-9"])) { error in
            XCTAssertTrue(error.localizedDescription.contains("2 pages"))
        }
        XCTAssertThrowsError(try Tools.tool("compress-size")!.run([mp4], params: ["size": "0"]))
    }

    // MARK: PDF + zip

    func testPDFMergeSplitReorganizeRotate() throws {
        let pdf = try Fixtures.copy("pdf")
        XCTAssertEqual(PDFEngine.pageCount(pdf), 2)
        XCTAssertEqual(PDFEngine.pageCount(try run("merge-pdf", [pdf, try Fixtures.copy("pdf"), try Fixtures.copy("png")])[0]), 5)
        XCTAssertEqual(try run("split-pdf", [pdf]).count, 2)
        let ranged = try run("split-pdf", [pdf], ["ranges": "1-2"])
        XCTAssertEqual(ranged.count, 1); XCTAssertEqual(PDFEngine.pageCount(ranged[0]), 2)
        let reorganized = try XCTUnwrap(PDFDocument(url: try run("reorganize-pdf", [pdf], ["order": "2:90, 1"])[0]))
        XCTAssertEqual(reorganized.pageCount, 2)
        XCTAssertEqual(reorganized.page(at: 0)?.rotation, 90)
        XCTAssertTrue(reorganized.page(at: 1)?.string?.contains("Kumquat") == true)
        XCTAssertEqual(PDFDocument(url: try run("rotate", [pdf], ["angle": "180°"])[0])?.page(at: 0)?.rotation, 180)
    }

    func testZipOneAndMany() throws {
        let a = try Fixtures.copy("txt")
        let b = a.deletingLastPathComponent().appendingPathComponent("other.md")
        try FileManager.default.copyItem(at: try Fixtures.copy("md"), to: b)
        XCTAssertEqual(try Archive.list(run("zip", [a])[0]), ["sample.txt"])
        XCTAssertEqual(Set(try Archive.list(run("zip", [a, b])[0])), ["sample.txt", "other.md"])
    }

    // MARK: Applicability

    func testToolsWheelContentsPerFileType() {
        func ids(_ names: String...) -> Set<String> {
            Set(Tools.applicable(to: names.map { URL(fileURLWithPath: "/tmp/\($0)") }).map(\.id))
        }
        XCTAssertTrue(ids("a.png").isSuperset(of: ["compress", "crop", "annotate", "redact", "qr", "metadata", "zip"]))
        XCTAssertFalse(ids("a.png").contains("trim"))
        XCTAssertTrue(ids("a.mp4", "b.mov").contains("join"))
        XCTAssertFalse(ids("a.mp4").contains("join"))
        XCTAssertTrue(ids("a.pdf", "b.pdf").contains("merge-pdf"))
        XCTAssertEqual(ids("a.unknown"), ["zip"])
        XCTAssertGreaterThanOrEqual(Tools.all.count, 26)
    }
}

final class ArrowTests: XCTestCase {
    func testArrowDirectionFollowsSignedRect() throws {
        let ctx = ImageEngine.context(width: 100, height: 100)!
        ctx.setFillColor(CGColor(gray: 1, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
        var edit = PhotoEdit()
        // Head at top-right (0.9, 0.1), tail at bottom-left (0.1, 0.9).
        var arrow = PhotoEdit.Shape(kind: .arrow, rect: CGRect(x: 0.1, y: 0.9, width: 0.8, height: -0.8), color: "#000000")
        arrow.lineWidth = 0.03
        edit.shapes = [arrow]
        let out = try PhotoEditor.render(ctx.makeImage()!, edit: edit)
        let probe = ImageEngine.context(width: 100, height: 100)!
        probe.draw(out, in: CGRect(x: 0, y: 0, width: 100, height: 100))
        let px = probe.data!.assumingMemoryBound(to: UInt8.self)
        func dark(_ x: Int, _ yTop: Int) -> Bool { px[yTop * probe.bytesPerRow + x * 4] < 100 }
        XCTAssertTrue(dark(50, 50))     // shaft through the middle
        XCTAssertTrue(dark(88, 12))     // head end
        XCTAssertFalse(dark(88, 88))    // not the other diagonal
    }
}
