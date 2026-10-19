import AppKit
import CoreImage
@testable import KumquatCore

/// Generates one sample file per readable format, using system tools where possible
/// (sips, textutil, ffmpeg, cwebp, tar, zip) so readers are tested against independent writers.
enum Fixtures {
    static let marker = "Kumquat"
    nonisolated(unsafe) private static var cached: URL?

    static var dir: URL {
        if let cached { return cached }
        let url = try! TempDir.make()
        try! build(in: url)
        cached = url
        return url
    }

    static func url(_ ext: String) -> URL? {
        let file = dir.appendingPathComponent("sample.\(ext)")
        return FileManager.default.fileExists(atPath: file.path) ? file : nil
    }

    /// Fresh copy in its own folder so outputs don't collide between tests.
    static func copy(_ ext: String) throws -> URL {
        guard let source = url(ext) else { throw ConversionError("no fixture for \(ext)") }
        let target = try TempDir.make().appendingPathComponent(source.lastPathComponent)
        try FileManager.default.copyItem(at: source, to: target)
        return target
    }

    static func sh(_ exe: String, _ args: [String], cwd: URL? = nil) throws { try Shell.run(exe, args, cwd: cwd) }

    static func build(in dir: URL) throws {
        func f(_ ext: String) -> String { dir.appendingPathComponent("sample.\(ext)").path }

        // Images: PNG from CoreGraphics, the rest from sips / cwebp / ImageIO.
        try ImageEngine.write(testImage(), to: URL(fileURLWithPath: f("png")), ext: "png")
        for (ext, format) in [("jpg", "jpeg"), ("heic", "heic"), ("tiff", "tiff"), ("bmp", "bmp"), ("gif", "gif")] {
            try sh("/usr/bin/sips", ["-s", "format", format, f("png"), "--out", f(ext)])
        }
        if let cwebp = Shell.which("cwebp") { try sh(cwebp, ["-quiet", f("png"), "-o", f("webp")]) }
        try ImageEngine.write(testImage(), to: URL(fileURLWithPath: f("avif")), ext: "avif")
        try """
        <svg xmlns="http://www.w3.org/2000/svg" width="120" height="80"><rect width="120" height="80" fill="orange"/><circle cx="60" cy="40" r="30" fill="green"/></svg>
        """.write(toFile: f("svg"), atomically: true, encoding: .utf8)

        // Video + audio via ffmpeg lavfi sources.
        let src = ["-f", "lavfi", "-i", "testsrc=size=320x240:rate=15:duration=2", "-f", "lavfi", "-i", "sine=frequency=440:duration=2"]
        try Shell.ffmpeg(src + ["-c:v", "libx264", "-pix_fmt", "yuv420p", "-c:a", "aac", "-shortest", f("mp4")])
        try Shell.ffmpeg(["-i", f("mp4"), "-c", "copy", f("mov")])
        try Shell.ffmpeg(["-i", f("mp4"), "-c", "copy", f("mkv")])
        try Shell.ffmpeg(["-i", f("mp4"), "-c:v", "libvpx-vp9", "-b:v", "200k", "-c:a", "libopus", f("webm")])
        try Shell.ffmpeg(["-i", f("mp4"), "-c:v", "mpeg4", "-c:a", "libmp3lame", f("avi")])
        try Shell.ffmpeg(["-i", f("mp4"), "-c:v", "wmv2", "-c:a", "wmav2", f("wmv")])
        let tone = ["-f", "lavfi", "-i", "sine=frequency=440:duration=2", "-ac", "2"]
        for (ext, codec) in [("mp3", "libmp3lame"), ("m4a", "aac"), ("wav", "pcm_s16le"), ("flac", "flac"), ("opus", "libopus"),
                             ("aiff", "pcm_s16be"), ("wma", "wmav2"), ("aac", "aac")] {
            try Shell.ffmpeg(tone + ["-c:a", codec, f(ext)])
        }
        try Shell.ffmpeg(tone + ["-c:a", "libopus", f("ogg")])

        // Documents via textutil from HTML.
        let html = "<html><body><h1>\(marker) Title</h1><p>Hello <b>bold</b> and <i>italic</i> text.</p><ul><li>One</li><li>Two</li></ul></body></html>"
        try html.write(toFile: f("html"), atomically: true, encoding: .utf8)
        for ext in ["docx", "doc", "rtf", "odt", "rtfd"] { try sh("/usr/bin/textutil", ["-convert", ext, "-output", f(ext), f("html")]) }
        try "\(marker) plain text\nSecond line\n".write(toFile: f("txt"), atomically: true, encoding: .utf8)
        try "# \(marker) Heading\n\nSome **bold** and *italic* text.\n\n- one\n- two\n".write(toFile: f("md"), atomically: true, encoding: .utf8)
        let clipping = try PropertyListSerialization.data(fromPropertyList: ["UTI-Data": ["public.utf8-plain-text": "\(marker) clipping"]],
                                                          format: .binary, options: 0)
        try clipping.write(to: URL(fileURLWithPath: f("textclipping")))

        // PDF (2 pages) from CoreText, with a QR code on page 1 as an image fixture too.
        let long = NSMutableAttributedString(string: "\(marker) PDF page one\tcol2\n", attributes: [.font: NSFont.systemFont(ofSize: 14)])
        long.append(NSAttributedString(string: String(repeating: "Filler line for pagination.\n", count: 60), attributes: [.font: NSFont.systemFont(ofSize: 14)]))
        try RichText.writePDF(long, to: URL(fileURLWithPath: f("pdf")))

        // EPUB written by hand (independent of our writer).
        try epubFixture(to: URL(fileURLWithPath: f("epub")))

        // Office: PPTX with text + picture, XLSX/ODS from our writers, CSV/TSV by hand.
        try OOXML.writePPTX([PPTXSlide(texts: ["\(marker) Slide", "Bullet"], image: nil),
                             PPTXSlide(texts: [], image: try PDFEngine.pngData(testImage()))],
                            size: CGSize(width: 960, height: 540), to: URL(fileURLWithPath: f("pptx")))
        let sheet = Sheet(name: "Data", rows: [["Name", "Qty"], [marker, "3"], ["Pear, green", "4.5"]])
        try OOXML.writeXLSX([sheet], to: URL(fileURLWithPath: f("xlsx")))
        try Spreadsheet.writeODS([sheet], to: URL(fileURLWithPath: f("ods")))
        try "Name,Qty\n\(marker),3\n\"Pear, green\",4.5\n".write(toFile: f("csv"), atomically: true, encoding: .utf8)
        try "Name\tQty\n\(marker)\t3\n".write(toFile: f("tsv"), atomically: true, encoding: .utf8)

        // Subtitles.
        try "1\n00:00:01,000 --> 00:00:02,500\n\(marker) line\n\n2\n00:00:03,000 --> 00:00:04,000\nSecond\n".write(toFile: f("srt"), atomically: true, encoding: .utf8)
        try "WEBVTT\n\n00:01.000 --> 00:02.500\n\(marker) line\n\n00:03.000 --> 00:04.000 align:start\nSecond\n".write(toFile: f("vtt"), atomically: true, encoding: .utf8)

        // Archives of a small folder.
        let content = dir.appendingPathComponent("stuff")
        try FileManager.default.createDirectory(at: content, withIntermediateDirectories: true)
        try "\(marker) inside".write(to: content.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        try sh("/usr/bin/zip", ["-rq", f("zip"), "stuff"], cwd: dir)
        try sh("/usr/bin/tar", ["-cf", f("tar"), "stuff"], cwd: dir)
        try sh("/usr/bin/tar", ["-czf", f("tar.gz"), "stuff"], cwd: dir)
        try sh("/bin/sh", ["-c", "/usr/bin/gzip -c stuff/a.txt > sample.gz"], cwd: dir)
        // RAR can't be created with stock tools: libarchive's test_read_format_rar.rar (test.txt, testdir/, a symlink).
        try Data(base64Encoded: rarSample)!.write(to: URL(fileURLWithPath: f("rar")))
    }

    static let rarSample = "UmFyIRoHAM+QcwAADQAAAAAAAACEUnQgkDIAFAAAABQAAAADQqLIvrd22j4UMAgApIEAAHRlc3QudHh0gAi3dto+t3baPnRlc3QgdGV4dCBkb2N1bWVudA0KnS90IJAyAAgAAAAIAAAAA3tEybbRTNg+FDAIAP+hAAB0ZXN0bGlua8AI0UzYPlBf2j50ZXN0LnR4dM3gdCCQOgAUAAAAFAAAAANCosi+Y3faPhQwEACkgQAAdGVzdGRpclx0ZXN0LnR4dMDMY3faPmN32j50ZXN0IHRleHQgZG9jdW1lbnQNCqHIdOCQMQAAAAAAAAAAAAMAAAAAY3faPhQwBwDtQQAAdGVzdGRpcsDMY3faPmR32j7m53TgkDYAAAAAAAAAAAADAAAAAJ2r1T4UMAwA7UEAAHRlc3RlbXB0eWRpcoDMnavVPsVd2j7EPXsAQAcA"

    /// 400x300 image with transparency, color blocks and a QR code.
    static func testImage() throws -> CGImage {
        let ctx = ImageEngine.context(width: 400, height: 300)!
        ctx.setFillColor(CGColor(red: 1, green: 0.55, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 200, height: 300))
        ctx.setFillColor(CGColor(red: 0.1, green: 0.5, blue: 0.9, alpha: 0.8))
        ctx.fill(CGRect(x: 200, y: 150, width: 200, height: 150))
        let qr = CIFilter(name: "CIQRCodeGenerator", parameters: ["inputMessage": Data("https://example.com/\(marker)".utf8)])!.outputImage!
            .transformed(by: CGAffineTransform(scaleX: 5, y: 5))
        let qrImage = CIContext().createCGImage(qr, from: qr.extent)!
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        ctx.fill(CGRect(x: 220, y: 10, width: 150, height: 150))
        ctx.draw(qrImage, in: CGRect(x: 230, y: 20, width: qr.extent.width, height: qr.extent.height))
        return ctx.makeImage()!
    }

    static func epubFixture(to url: URL) throws {
        try Zip.write([
            ("mimetype", "application/epub+zip".data(using: .utf8)!),
            ("META-INF/container.xml", """
            <?xml version="1.0"?><container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">\
            <rootfiles><rootfile full-path="book/pkg.opf" media-type="application/oebps-package+xml"/></rootfiles></container>
            """.data(using: .utf8)!),
            ("book/pkg.opf", """
            <?xml version="1.0"?><package xmlns="http://www.idpf.org/2007/opf" version="3.0"><metadata/>\
            <manifest><item id="a" href="one.xhtml" media-type="application/xhtml+xml"/><item id="b" href="two.xhtml" media-type="application/xhtml+xml"/></manifest>\
            <spine><itemref idref="a"/><itemref idref="b"/></spine></package>
            """.data(using: .utf8)!),
            ("book/one.xhtml", "<html xmlns=\"http://www.w3.org/1999/xhtml\"><body><h1>\(marker) Chapter</h1><p>First.</p></body></html>".data(using: .utf8)!),
            ("book/two.xhtml", "<html xmlns=\"http://www.w3.org/1999/xhtml\"><body><h1>Two</h1><p>Second.</p></body></html>".data(using: .utf8)!),
        ], to: url, storedFirst: ["mimetype"])
    }
}
