import AppKit
import CoreText

public struct PPTXSlide {
    public var texts: [String]
    public var image: Data?
    public init(texts: [String], image: Data?) { self.texts = texts; self.image = image }
}

/// Minimal Office Open XML writers/readers for PowerPoint and Excel.
public enum OOXML {
    static let ns = """
    xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" \
    xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" \
    xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main"
    """
    static let rel = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
    static let emuPerPoint = 12700.0
    static let header = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n"

    static func rels(_ items: [(id: String, type: String, target: String)]) -> Data {
        let body = items.map { "<Relationship Id=\"\($0.id)\" Type=\"\(rel)/\($0.type)\" Target=\"\($0.target)\"/>" }
        return (header + "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">\(body.joined())</Relationships>").data
    }

    static func contentTypes(defaults: [String: String], overrides: [(String, String)]) -> Data {
        let d = defaults.sorted { $0.key < $1.key }.map { "<Default Extension=\"\($0.key)\" ContentType=\"\($0.value)\"/>" }
        let o = overrides.map { "<Override PartName=\"\($0.0)\" ContentType=\"\($0.1)\"/>" }
        return (header + "<Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\">\(d.joined())\(o.joined())</Types>").data
    }

    static let emptyTree = "<p:nvGrpSpPr><p:cNvPr id=\"1\" name=\"\"/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr/>"

    // MARK: PPTX

    public static func writePPTX(_ slides: [PPTXSlide], size: CGSize, to url: URL) throws {
        let cx = Int(size.width * emuPerPoint), cy = Int(size.height * emuPerPoint)
        let pml = "application/vnd.openxmlformats-officedocument.presentationml"
        var files: [(String, Data)] = []
        var overrides: [(String, String)] = [
            ("/ppt/presentation.xml", "\(pml).presentation.main+xml"),
            ("/ppt/slideMasters/slideMaster1.xml", "\(pml).slideMaster+xml"),
            ("/ppt/slideLayouts/slideLayout1.xml", "\(pml).slideLayout+xml"),
            ("/ppt/theme/theme1.xml", "application/vnd.openxmlformats-officedocument.theme+xml"),
        ]
        var presRels: [(id: String, type: String, target: String)] = [("rId1", "slideMaster", "slideMasters/slideMaster1.xml"),
                                                                       ("rId2", "theme", "theme/theme1.xml")]
        var slideIds: [String] = []
        for (i, slide) in slides.enumerated() {
            let n = i + 1
            var tree = emptyTree
            var slideRels: [(id: String, type: String, target: String)] = [("rId1", "slideLayout", "../slideLayouts/slideLayout1.xml")]
            if let image = slide.image {
                files.append(("ppt/media/image\(n).png", image))
                slideRels.append(("rId2", "image", "../media/image\(n).png"))
                tree += """
                <p:pic><p:nvPicPr><p:cNvPr id="2" name="Picture \(n)"/><p:cNvPicPr/><p:nvPr/></p:nvPicPr>\
                <p:blipFill><a:blip r:embed="rId2"/><a:stretch><a:fillRect/></a:stretch></p:blipFill>\
                <p:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="\(cx)" cy="\(cy)"/></a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom></p:spPr></p:pic>
                """
            }
            if !slide.texts.isEmpty {
                let paragraphs = slide.texts.enumerated().map { j, text in
                    "<a:p><a:r><a:rPr lang=\"en-US\" sz=\"\(j == 0 ? 3600 : 2000)\"\(j == 0 ? " b=\"1\"" : "")/><a:t>\(text.xmlEscaped)</a:t></a:r></a:p>"
                }
                let margin = cx / 16
                tree += """
                <p:sp><p:nvSpPr><p:cNvPr id="3" name="Text \(n)"/><p:cNvSpPr txBox="1"/><p:nvPr/></p:nvSpPr>\
                <p:spPr><a:xfrm><a:off x="\(margin)" y="\(margin)"/><a:ext cx="\(cx - 2 * margin)" cy="\(cy - 2 * margin)"/></a:xfrm>\
                <a:prstGeom prst="rect"><a:avLst/></a:prstGeom></p:spPr>\
                <p:txBody><a:bodyPr wrap="square"/><a:lstStyle/>\(paragraphs.joined())</p:txBody></p:sp>
                """
            }
            files.append(("ppt/slides/slide\(n).xml", (header + "<p:sld \(ns)><p:cSld><p:spTree>\(tree)</p:spTree></p:cSld></p:sld>").data))
            files.append(("ppt/slides/_rels/slide\(n).xml.rels", rels(slideRels)))
            overrides.append(("/ppt/slides/slide\(n).xml", "\(pml).slide+xml"))
            presRels.append(("rId\(n + 2)", "slide", "slides/slide\(n).xml"))
            slideIds.append("<p:sldId id=\"\(255 + n)\" r:id=\"rId\(n + 2)\"/>")
        }
        files += [
            ("[Content_Types].xml", contentTypes(defaults: ["rels": "application/vnd.openxmlformats-package.relationships+xml",
                                                            "xml": "application/xml", "png": "image/png"], overrides: overrides)),
            ("_rels/.rels", rels([("rId1", "officeDocument", "ppt/presentation.xml")])),
            ("ppt/presentation.xml", (header + """
            <p:presentation \(ns)><p:sldMasterIdLst><p:sldMasterId id="2147483648" r:id="rId1"/></p:sldMasterIdLst>\
            <p:sldIdLst>\(slideIds.joined())</p:sldIdLst><p:sldSz cx="\(cx)" cy="\(cy)"/><p:notesSz cx="6858000" cy="9144000"/></p:presentation>
            """).data),
            ("ppt/_rels/presentation.xml.rels", rels(presRels)),
            ("ppt/slideMasters/slideMaster1.xml", (header + """
            <p:sldMaster \(ns)><p:cSld><p:spTree>\(emptyTree)</p:spTree></p:cSld>\
            <p:clrMap bg1="lt1" tx1="dk1" bg2="lt2" tx2="dk2" accent1="accent1" accent2="accent2" accent3="accent3" \
            accent4="accent4" accent5="accent5" accent6="accent6" hlink="hlink" folHlink="folHlink"/>\
            <p:sldLayoutIdLst><p:sldLayoutId id="2147483649" r:id="rId1"/></p:sldLayoutIdLst></p:sldMaster>
            """).data),
            ("ppt/slideMasters/_rels/slideMaster1.xml.rels", rels([("rId1", "slideLayout", "../slideLayouts/slideLayout1.xml"),
                                                                   ("rId2", "theme", "../theme/theme1.xml")])),
            ("ppt/slideLayouts/slideLayout1.xml", (header + "<p:sldLayout \(ns)><p:cSld><p:spTree>\(emptyTree)</p:spTree></p:cSld></p:sldLayout>").data),
            ("ppt/slideLayouts/_rels/slideLayout1.xml.rels", rels([("rId1", "slideMaster", "../slideMasters/slideMaster1.xml")])),
            ("ppt/theme/theme1.xml", theme.data),
        ]
        try Zip.write(files, to: url)
    }

    static let theme: String = {
        let colors = ["dk1": "000000", "lt1": "FFFFFF", "dk2": "44546A", "lt2": "E7E6E6", "accent1": "4472C4", "accent2": "ED7D31",
                      "accent3": "A5A5A5", "accent4": "FFC000", "accent5": "5B9BD5", "accent6": "70AD47", "hlink": "0563C1", "folHlink": "954F72"]
        let order = ["dk1", "lt1", "dk2", "lt2", "accent1", "accent2", "accent3", "accent4", "accent5", "accent6", "hlink", "folHlink"]
        let scheme = order.map { "<a:\($0)><a:srgbClr val=\"\(colors[$0]!)\"/></a:\($0)>" }.joined()
        let fill = "<a:solidFill><a:schemeClr val=\"phClr\"/></a:solidFill>"
        let line = "<a:ln w=\"6350\"><a:solidFill><a:schemeClr val=\"phClr\"/></a:solidFill></a:ln>"
        let effect = "<a:effectStyle><a:effectLst/></a:effectStyle>"
        return header + """
        <a:theme xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" name="Kumquat"><a:themeElements>\
        <a:clrScheme name="Kumquat">\(scheme)</a:clrScheme>\
        <a:fontScheme name="Kumquat"><a:majorFont><a:latin typeface="Helvetica"/><a:ea typeface=""/><a:cs typeface=""/></a:majorFont>\
        <a:minorFont><a:latin typeface="Helvetica"/><a:ea typeface=""/><a:cs typeface=""/></a:minorFont></a:fontScheme>\
        <a:fmtScheme name="Kumquat"><a:fillStyleLst>\(fill)\(fill)\(fill)</a:fillStyleLst>\
        <a:lnStyleLst>\(line)\(line)\(line)</a:lnStyleLst><a:effectStyleLst>\(effect)\(effect)\(effect)</a:effectStyleLst>\
        <a:bgFillStyleLst>\(fill)\(fill)\(fill)</a:bgFillStyleLst></a:fmtScheme></a:themeElements></a:theme>
        """
    }()

    // MARK: PPTX reading and rendering

    public struct SlideShape {
        public var frame: CGRect          // points, top-left origin
        public var paragraphs: [(text: String, size: CGFloat, bold: Bool)] = []
        public var image: Data?
    }

    public struct Presentation {
        public var size: CGSize
        public var slides: [[SlideShape]]
    }

    public static func readPPTX(_ url: URL) throws -> Presentation {
        try TempDir.with { dir in
            try Zip.extract(url, to: dir)
            let ppt = dir.appendingPathComponent("ppt")
            let pres = try Data(contentsOf: ppt.appendingPathComponent("presentation.xml"))
            let sz = XMLTextCollector.parse(pres, interesting: ["sldSz"]).first?.attributes ?? [:]
            let size = CGSize(width: (Double(sz["cx"] ?? "") ?? 12_192_000) / emuPerPoint,
                              height: (Double(sz["cy"] ?? "") ?? 6_858_000) / emuPerPoint)
            let presRels = relationships(ppt.appendingPathComponent("_rels/presentation.xml.rels"))
            let order = XMLTextCollector.parse(pres, interesting: ["sldId"]).compactMap { $0.attributes["r:id"] }
            let slideFiles = order.compactMap { presRels[$0] }.map { ppt.appendingPathComponent($0) }
            let slides = try slideFiles.map { file -> [SlideShape] in
                let slideRels = relationships(file.deletingLastPathComponent().appendingPathComponent("_rels/\(file.lastPathComponent).rels"))
                let parser = SlideParser()
                let xml = XMLParser(data: try Data(contentsOf: file))
                xml.delegate = parser
                xml.parse()
                return parser.shapes.map { shape in
                    var s = shape.shape
                    if let embed = shape.embed, let target = slideRels[embed] {
                        s.image = try? Data(contentsOf: file.deletingLastPathComponent().appendingPathComponent(target).standardizedFileURL)
                    }
                    return s
                }
            }
            return Presentation(size: size, slides: slides)
        }
    }

    static func relationships(_ url: URL) -> [String: String] {
        guard let data = try? Data(contentsOf: url) else { return [:] }
        var map: [String: String] = [:]
        for r in XMLTextCollector.parse(data, interesting: ["Relationship"]) {
            if let id = r.attributes["Id"], let target = r.attributes["Target"] { map[id] = target }
        }
        return map
    }

    final class SlideParser: NSObject, XMLParserDelegate {
        struct Pending { var shape = SlideShape(frame: .zero); var embed: String? }
        var shapes: [Pending] = []
        private var current: Pending?
        private var sawOffset = false, sawExtent = false
        private var paragraph = "", size: CGFloat = 18, bold = false, inText = false

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?,
                    attributes a: [String: String]) {
            let emu = { (key: String) in CGFloat(Double(a[key] ?? "") ?? 0) / CGFloat(OOXML.emuPerPoint) }
            switch name {
            case "p:sp", "p:pic": current = Pending(); sawOffset = false; sawExtent = false
            case "a:off" where current != nil && !sawOffset:
                current?.shape.frame.origin = CGPoint(x: emu("x"), y: emu("y")); sawOffset = true
            case "a:ext" where current != nil && !sawExtent && a["cx"] != nil:
                current?.shape.frame.size = CGSize(width: emu("cx"), height: emu("cy")); sawExtent = true
            case "a:blip": current?.embed = a["r:embed"]
            case "a:p": paragraph = ""; size = 18; bold = false
            case "a:rPr", "a:endParaRPr":
                if let sz = a["sz"].flatMap(Double.init) { size = CGFloat(sz / 100) }
                if a["b"] == "1" { bold = true }
            case "a:t": inText = true
            default: break
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) { if inText { paragraph += string } }

        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
            switch name {
            case "a:t": inText = false
            case "a:p": if !paragraph.isEmpty { current?.shape.paragraphs.append((paragraph, size, bold)) }
            case "p:sp", "p:pic": if let c = current { shapes.append(c) }; current = nil
            default: break
            }
        }
    }

    /// Approximate slide rendering: pictures and text boxes at their positions, theme ignored.
    public static func render(_ shapes: [SlideShape], size: CGSize, scale: CGFloat = 2) throws -> CGImage {
        guard let ctx = ImageEngine.context(width: Int(size.width * scale), height: Int(size.height * scale)) else {
            throw ConversionError("Slide too large")
        }
        ctx.scaleBy(x: scale, y: scale)
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(origin: .zero, size: size))
        for shape in shapes {
            let rect = CGRect(x: shape.frame.minX, y: size.height - shape.frame.maxY, width: shape.frame.width, height: shape.frame.height)
            if let data = shape.image, let source = CGImageSourceCreateWithData(data as CFData, nil),
               let image = CGImageSourceCreateImageAtIndex(source, 0, nil) {
                ctx.draw(image, in: rect)
            }
            guard !shape.paragraphs.isEmpty else { continue }
            let text = NSMutableAttributedString()
            for (i, p) in shape.paragraphs.enumerated() {
                let font = p.bold ? NSFont.boldSystemFont(ofSize: p.size) : NSFont.systemFont(ofSize: p.size)
                text.append(NSAttributedString(string: (i > 0 ? "\n" : "") + p.text, attributes: [.font: font, .foregroundColor: NSColor.black]))
            }
            let frame = CTFramesetterCreateFrame(CTFramesetterCreateWithAttributedString(text), CFRange(),
                                                 CGPath(rect: rect.width > 0 ? rect : CGRect(origin: .zero, size: size), transform: nil), nil)
            CTFrameDraw(frame, ctx)
        }
        guard let image = ctx.makeImage() else { throw ConversionError("Slide render failed") }
        return image
    }

    // MARK: XLSX

    public static func writeXLSX(_ sheets: [Sheet], to url: URL) throws {
        let sml = "application/vnd.openxmlformats-officedocument.spreadsheetml"
        var files: [(String, Data)] = []
        var overrides: [(String, String)] = [("/xl/workbook.xml", "\(sml).sheet.main+xml"), ("/xl/styles.xml", "\(sml).styles+xml")]
        var wbRels: [(id: String, type: String, target: String)] = [("rIdStyles", "styles", "styles.xml")]
        var sheetTags: [String] = []
        for (i, sheet) in sheets.enumerated() {
            let n = i + 1
            let rows = sheet.rows.enumerated().map { r, row in
                let cells = row.enumerated().map { c, value -> String in
                    let ref = "\(columnName(c))\(r + 1)"
                    if let number = Double(value), !value.isEmpty, value.trimmingCharacters(in: .whitespaces) == value {
                        return "<c r=\"\(ref)\"><v>\(number == number.rounded() && abs(number) < 1e15 ? String(Int(number)) : String(number))</v></c>"
                    }
                    return "<c r=\"\(ref)\" t=\"inlineStr\"><is><t xml:space=\"preserve\">\(value.xmlEscaped)</t></is></c>"
                }
                return "<row r=\"\(r + 1)\">\(cells.joined())</row>"
            }
            files.append(("xl/worksheets/sheet\(n).xml", (header + """
            <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>\(rows.joined())</sheetData></worksheet>
            """).data))
            overrides.append(("/xl/worksheets/sheet\(n).xml", "\(sml).worksheet+xml"))
            wbRels.append(("rId\(n)", "worksheet", "worksheets/sheet\(n).xml"))
            sheetTags.append("<sheet name=\"\(String(sheet.name.prefix(31)).xmlEscaped)\" sheetId=\"\(n)\" r:id=\"rId\(n)\"/>")
        }
        files += [
            ("[Content_Types].xml", contentTypes(defaults: ["rels": "application/vnd.openxmlformats-package.relationships+xml",
                                                            "xml": "application/xml"], overrides: overrides)),
            ("_rels/.rels", rels([("rId1", "officeDocument", "xl/workbook.xml")])),
            ("xl/workbook.xml", (header + """
            <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="\(rel)"><sheets>\(sheetTags.joined())</sheets></workbook>
            """).data),
            ("xl/_rels/workbook.xml.rels", rels(wbRels)),
            ("xl/styles.xml", (header + """
            <styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">\
            <fonts count="1"><font><sz val="11"/><name val="Calibri"/></font></fonts>\
            <fills count="2"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill></fills>\
            <borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>\
            <cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>\
            <cellXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/></cellXfs></styleSheet>
            """).data),
        ]
        try Zip.write(files, to: url)
    }

    public static func columnName(_ index: Int) -> String {
        var n = index + 1, name = ""
        while n > 0 { let r = (n - 1) % 26; name = String(UnicodeScalar(65 + r)!) + name; n = (n - 1) / 26 }
        return name
    }

    static func columnIndex(_ ref: String) -> Int {
        ref.prefix { $0.isLetter }.uppercased().unicodeScalars.reduce(0) { $0 * 26 + Int($1.value) - 64 } - 1
    }

    public static func readXLSX(_ url: URL) throws -> [Sheet] {
        try TempDir.with { dir in
            try Zip.extract(url, to: dir)
            let xl = dir.appendingPathComponent("xl")
            let shared: [String] = (try? Data(contentsOf: xl.appendingPathComponent("sharedStrings.xml"))).map { data in
                XMLTextCollector.parse(data, interesting: ["si"]).map(\.text)
            } ?? []
            let workbook = try Data(contentsOf: xl.appendingPathComponent("workbook.xml"))
            let rels = relationships(xl.appendingPathComponent("_rels/workbook.xml.rels"))
            return try XMLTextCollector.parse(workbook, interesting: ["sheet"]).map { sheet in
                let target = sheet.attributes["r:id"].flatMap { rels[$0] } ?? "worksheets/sheet1.xml"
                let path = target.hasPrefix("/") ? dir.appendingPathComponent(String(target.dropFirst())) : xl.appendingPathComponent(target)
                let parser = SheetParser(shared: shared)
                let xml = XMLParser(data: try Data(contentsOf: path))
                xml.delegate = parser
                xml.parse()
                return Sheet(name: sheet.attributes["name"] ?? "Sheet", rows: parser.rows)
            }
        }
    }

    final class SheetParser: NSObject, XMLParserDelegate {
        let shared: [String]
        var rows: [[String]] = []
        private var row: [String] = [], ref = "", type = "", value = "", capture = false

        init(shared: [String]) { self.shared = shared }

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?,
                    attributes a: [String: String]) {
            switch name {
            case "row":
                let index = (Int(a["r"] ?? "") ?? rows.count + 1) - 1
                while rows.count < index { rows.append([]) }
                row = []
            case "c": ref = a["r"] ?? ""; type = a["t"] ?? ""; value = ""
            case "v", "t": capture = true
            default: break
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) { if capture { value += string } }

        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
            switch name {
            case "v", "t": capture = false
            case "c":
                let column = ref.isEmpty ? row.count : OOXML.columnIndex(ref)
                while row.count < column { row.append("") }
                switch type {
                case "s": row.append(Int(value).flatMap { shared.indices.contains($0) ? shared[$0] : nil } ?? "")
                case "b": row.append(value == "1" ? "TRUE" : "FALSE")
                default: row.append(value)
                }
            case "row": rows.append(row)
            default: break
            }
        }
    }
}
