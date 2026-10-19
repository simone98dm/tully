import AppKit
import Testing
@testable import tully

@MainActor
struct StatusBarTests {
    func snapshot(cpu: Double = 12, ramUsed: UInt64 = 8 << 30, ramTotal: UInt64 = 16 << 30,
                  diskUsed: Int64 = 400, diskTotal: Int64 = 1000, netIn: Double = 3 * 1024) -> SystemSnapshot {
        var snap = SystemSnapshot()
        snap.cpuPercent = cpu
        snap.ramUsed = ramUsed
        snap.ramTotal = ramTotal
        snap.diskUsed = diskUsed
        snap.diskTotal = diskTotal
        snap.netIn = netIn
        return snap
    }

    @Test func formatsEveryMetric() {
        let segments = StatusBarFormatter.segments(for: snapshot(), metrics: StatusMetric.allCases)
        #expect(segments.map(\.value) == ["12%", "8.0GB", "40%", "3KB/s"])
        #expect(segments.allSatisfy { $0.level == .normal })
    }

    @Test func levelsFollowThresholds() {
        let snap = snapshot(cpu: 92, ramUsed: 11 << 30, diskUsed: 500)
        let levels = StatusBarFormatter.segments(for: snap, metrics: [.cpu, .ram, .disk]).map(\.level)
        #expect(levels == [.critical, .elevated, .normal])
    }

    @Test func clampsAndHandlesMissingTotals() {
        let snap = snapshot(cpu: 140, ramTotal: 0, diskTotal: 0, netIn: -1)
        let values = StatusBarFormatter.segments(for: snap, metrics: StatusMetric.allCases).map(\.value)
        #expect(values == ["100%", "8.0GB", "0%", "0B/s"])
    }

    @Test func accessibilityLabelReadsEveryValue() {
        let segments = StatusBarFormatter.segments(for: snapshot(), metrics: [.cpu, .net])
        #expect(StatusBarFormatter.accessibilityLabel(for: segments) == "tully: CPU 12 percent, download 3KB/s")
        #expect(StatusBarFormatter.accessibilityLabel(for: []) == "tully")
    }

    @Test(arguments: StatusStyle.allCases)
    func widthDoesNotJitter(style: StatusStyle) {
        let appearance = NSAppearance(named: .darkAqua)!
        func width(_ snap: SystemSnapshot) -> CGFloat {
            let segments = StatusBarFormatter.segments(for: snap, metrics: StatusMetric.allCases)
            return StatusBarRenderer.image(segments: segments, style: style, icon: nil, tinted: false, appearance: appearance).size.width
        }
        #expect(width(snapshot(cpu: 1, netIn: 10)) == width(snapshot(cpu: 100, netIn: 800 * 1024)))
    }

    @Test func tintOnlyWhenSomethingIsHigh() {
        let appearance = NSAppearance(named: .aqua)!
        let calm = StatusBarFormatter.segments(for: snapshot(), metrics: [.cpu])
        let busy = StatusBarFormatter.segments(for: snapshot(cpu: 95), metrics: [.cpu])
        #expect(StatusBarRenderer.image(segments: calm, style: .iconValue, icon: nil, tinted: true, appearance: appearance).isTemplate)
        #expect(!StatusBarRenderer.image(segments: busy, style: .iconValue, icon: nil, tinted: true, appearance: appearance).isTemplate)
        #expect(StatusBarRenderer.image(segments: busy, style: .iconValue, icon: nil, tinted: false, appearance: appearance).isTemplate)
    }

    @Test func settingsOrderAndVisibility() {
        let settings = AppSettings(defaults: makeDefaults())
        #expect(settings.statusOrder == StatusMetric.allCases)
        settings.showNet = true
        settings.showCPU = true
        #expect(settings.visibleMetrics == [.cpu, .net])
        settings.moveMetric(fromOffsets: IndexSet(integer: 3), toOffset: 0)
        #expect(settings.visibleMetrics == [.net, .cpu])
        #expect(AppSettings.completeOrder([.disk, .disk]) == [.disk, .cpu, .ram, .net])
    }

    /// Writes every style to the temp folder for a visual check (not an assertion).
    @Test func renderPreviews() throws {
        let segments = StatusBarFormatter.segments(for: snapshot(cpu: 91), metrics: StatusMetric.allCases)
        for style in StatusStyle.allCases {
            for (name, appearance) in [("light", NSAppearance(named: .aqua)!), ("dark", NSAppearance(named: .darkAqua)!)] {
                let image = StatusBarRenderer.image(segments: segments, style: style, icon: NSImage(named: "MenuIcon"),
                                                    tinted: true, appearance: appearance)
                let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
                let url = FileManager.default.temporaryDirectory.appendingPathComponent("tully-status-\(style.rawValue)-\(name).png")
                try rep.representation(using: .png, properties: [:])!.write(to: url)
            }
        }
    }
}
