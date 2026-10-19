// Draws tully's glyph directions with Core Graphics so one definition feeds every output:
// menu bar template images (PDF), app icon PNGs and the comparison sheet.
//   swiftc -O design/icon/IconKit.swift -o /tmp/iconkit && /tmp/iconkit sheet out.png
//   /tmp/iconkit export <direction> <assets dir>
import AppKit

enum Direction: String, CaseIterable {
    case ring, tiles, pulse

    var title: String {
        switch self {
        case .ring: "A · Ring gauge"
        case .tiles: "B · Tiles"
        case .pulse: "C · Pulse window"
        }
    }

    var gradient: [NSColor] {
        switch self {
        case .ring: [NSColor(srgbRed: 0.20, green: 0.52, blue: 1.00, alpha: 1), NSColor(srgbRed: 0.35, green: 0.24, blue: 0.92, alpha: 1)]
        case .tiles: [NSColor(srgbRed: 0.12, green: 0.78, blue: 0.62, alpha: 1), NSColor(srgbRed: 0.05, green: 0.45, blue: 0.70, alpha: 1)]
        case .pulse: [NSColor(srgbRed: 1.00, green: 0.55, blue: 0.20, alpha: 1), NSColor(srgbRed: 0.90, green: 0.22, blue: 0.40, alpha: 1)]
        }
    }

    /// Glyph in a unit square (0…1, y up), drawn with `color`.
    func drawGlyph(in rect: CGRect, color: NSColor, ctx: CGContext) {
        let s = rect.width
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * s, y: rect.minY + y * s) }
        ctx.saveGState()
        ctx.setStrokeColor(color.cgColor)
        ctx.setFillColor(color.cgColor)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        switch self {
        case .ring:
            // 3/4 usage arc around a small window
            ctx.setLineWidth(s * 0.13)
            ctx.addArc(center: p(0.5, 0.5), radius: s * 0.38, startAngle: .pi * 1.25, endAngle: -.pi * 0.25, clockwise: true)
            ctx.strokePath()
            let window = CGRect(x: rect.minX + s * 0.34, y: rect.minY + s * 0.36, width: s * 0.32, height: s * 0.28)
            ctx.addPath(CGPath(roundedRect: window, cornerWidth: s * 0.05, cornerHeight: s * 0.05, transform: nil))
            ctx.fillPath()
        case .tiles:
            // 2×2 window tiles; one filled (the snapped window), three outlined
            let gap = s * 0.1, tile = (s * 0.84 - gap) / 2, origin = s * 0.08
            ctx.setLineWidth(s * 0.085)
            for (i, (cx, cy)) in [(0, 1), (1, 1), (0, 0), (1, 0)].enumerated() {
                let r = CGRect(x: rect.minX + origin + CGFloat(cx) * (tile + gap), y: rect.minY + origin + CGFloat(cy) * (tile + gap),
                               width: tile, height: tile)
                let path = CGPath(roundedRect: r.insetBy(dx: s * 0.04, dy: s * 0.04), cornerWidth: s * 0.07, cornerHeight: s * 0.07, transform: nil)
                ctx.addPath(path)
                if i == 0 { ctx.fillPath() } else { ctx.strokePath() }
            }
        case .pulse:
            // window frame with an activity line through it
            ctx.setLineWidth(s * 0.09)
            let frame = CGRect(x: rect.minX + s * 0.08, y: rect.minY + s * 0.14, width: s * 0.84, height: s * 0.72)
            ctx.addPath(CGPath(roundedRect: frame, cornerWidth: s * 0.12, cornerHeight: s * 0.12, transform: nil))
            ctx.strokePath()
            ctx.setLineWidth(s * 0.095)
            ctx.move(to: p(0.2, 0.46))
            ctx.addLine(to: p(0.37, 0.46))
            ctx.addLine(to: p(0.46, 0.66))
            ctx.addLine(to: p(0.56, 0.3))
            ctx.addLine(to: p(0.64, 0.5))
            ctx.addLine(to: p(0.8, 0.5))
            ctx.strokePath()
        }
        ctx.restoreGState()
    }

    /// macOS-style app icon: rounded square with a gradient and the white glyph.
    func drawAppIcon(in rect: CGRect, ctx: CGContext) {
        let inset = rect.width * 0.1   // macOS icon grid: 100/1024 margin
        let body = rect.insetBy(dx: inset, dy: inset)
        let path = CGPath(roundedRect: body, cornerWidth: body.width * 0.225, cornerHeight: body.width * 0.225, transform: nil)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -rect.width * 0.01), blur: rect.width * 0.03,
                      color: NSColor.black.withAlphaComponent(0.3).cgColor)
        ctx.addPath(path)
        ctx.setFillColor(gradient[1].cgColor)
        ctx.fillPath()
        ctx.restoreGState()
        ctx.saveGState()
        ctx.addPath(path)
        ctx.clip()
        let colors = gradient.map(\.cgColor) as CFArray
        let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors, locations: [0, 1])!
        ctx.drawLinearGradient(g, start: CGPoint(x: body.minX, y: body.maxY), end: CGPoint(x: body.maxX, y: body.minY), options: [])
        // soft top highlight
        let shine = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                               colors: [NSColor.white.withAlphaComponent(0.22).cgColor, NSColor.white.withAlphaComponent(0).cgColor] as CFArray,
                               locations: [0, 1])!
        ctx.drawLinearGradient(shine, start: CGPoint(x: body.midX, y: body.maxY), end: CGPoint(x: body.midX, y: body.midY), options: [])
        ctx.restoreGState()
        drawGlyph(in: body.insetBy(dx: body.width * 0.2, dy: body.width * 0.2), color: .white, ctx: ctx)
    }
}

// MARK: - Output helpers

func bitmap(_ size: CGSize, scale: CGFloat = 1, _ draw: (CGContext) -> Void) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = context
    context.cgContext.scaleBy(x: scale, y: scale)
    draw(context.cgContext)
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func writePNG(_ rep: NSBitmapImageRep, _ path: String) {
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}

func label(_ text: String, at point: CGPoint, size: CGFloat, color: NSColor, weight: NSFont.Weight = .semibold) {
    (text as NSString).draw(at: point, withAttributes: [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color])
}

/// Comparison sheet: each direction in light and dark menu bars at real size and zoomed, plus app icons.
func sheet(_ path: String) {
    let rowHeight: CGFloat = 230, width: CGFloat = 1100
    let rep = bitmap(CGSize(width: width, height: rowHeight * CGFloat(Direction.allCases.count) + 20), scale: 2) { ctx in
        NSColor(white: 0.97, alpha: 1).setFill()
        CGRect(x: 0, y: 0, width: width, height: 10_000).fill()
        for (row, direction) in Direction.allCases.reversed().enumerated() {
            let y = 20 + CGFloat(row) * rowHeight
            label(direction.title, at: CGPoint(x: 24, y: y + rowHeight - 44), size: 18, color: .black)
            // menu bars: real size (16 pt glyph in a 24 pt bar) and 3× zoom
            for (i, dark) in [false, true].enumerated() {
                let bar = CGRect(x: 24, y: y + 110 - CGFloat(i) * 60, width: 300, height: 24)
                (dark ? NSColor(white: 0.12, alpha: 1) : NSColor(white: 0.9, alpha: 1)).setFill()
                bar.fill()
                let fg: NSColor = dark ? .white : .black
                label("CPU 12%  MEM 8.1GB", at: CGPoint(x: bar.minX + 120, y: bar.minY + 4), size: 12, color: fg, weight: .medium)
                direction.drawGlyph(in: CGRect(x: bar.maxX - 26, y: bar.minY + 4, width: 16, height: 16), color: fg, ctx: ctx)
                let zoom = CGRect(x: 340 + CGFloat(i) * 70, y: y + 70, width: 56, height: 56)
                (dark ? NSColor(white: 0.12, alpha: 1) : NSColor(white: 0.9, alpha: 1)).setFill()
                zoom.insetBy(dx: -6, dy: -6).fill()
                direction.drawGlyph(in: zoom, color: fg, ctx: ctx)
            }
            label("menu bar · real size and zoomed", at: CGPoint(x: 24, y: y + 20), size: 11, color: .gray, weight: .regular)
            // app icons at Dock-ish and Finder sizes
            direction.drawAppIcon(in: CGRect(x: 520, y: y + 10, width: 180, height: 180), ctx: ctx)
            direction.drawAppIcon(in: CGRect(x: 720, y: y + 60, width: 80, height: 80), ctx: ctx)
            direction.drawAppIcon(in: CGRect(x: 820, y: y + 84, width: 32, height: 32), ctx: ctx)
            direction.drawAppIcon(in: CGRect(x: 870, y: y + 92, width: 16, height: 16), ctx: ctx)
        }
    }
    writePNG(rep, path)
}

/// Writes the chosen direction: menu bar template PDFs (16/18 pt) and every app icon size.
func export(_ direction: Direction, to dir: String) {
    let fm = FileManager.default
    try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
    for points in [16, 18] {
        let url = URL(fileURLWithPath: "\(dir)/menuicon-\(points).pdf") as CFURL
        var box = CGRect(x: 0, y: 0, width: points, height: points)
        let pdf = CGContext(url, mediaBox: &box, nil)!
        pdf.beginPDFPage(nil)
        direction.drawGlyph(in: box.insetBy(dx: 1, dy: 1), color: .black, ctx: pdf)
        pdf.endPDFPage()
        pdf.closePDF()
    }
    for points in [16, 32, 128, 256, 512] {
        for scale in [1, 2] {
            let rep = bitmap(CGSize(width: points, height: points), scale: CGFloat(scale)) { ctx in
                direction.drawAppIcon(in: CGRect(x: 0, y: 0, width: points, height: points), ctx: ctx)
            }
            writePNG(rep, "\(dir)/icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png")
        }
    }
}

let args = CommandLine.arguments
switch args.dropFirst().first {
case "sheet": sheet(args[2])
case "export": export(Direction(rawValue: args[2])!, to: args[3])
default: print("usage: iconkit sheet <out.png> | export <ring|tiles|pulse> <dir>")
}
