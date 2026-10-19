import AppKit
import KumquatCore
import Testing
@testable import tully

@MainActor
struct MiscCoverageTests {
    @Test func everyZoneAndMetricHasText() {
        for zone in WindowZone.allCases { #expect(!zone.displayName.isEmpty) }
        for metric in StatusMetric.allCases {
            #expect(!metric.title.isEmpty && !metric.shortLabel.isEmpty && !metric.widthTemplate.isEmpty)
            #expect(NSImage(systemSymbolName: metric.symbol, accessibilityDescription: nil) != nil)
        }
        for style in StatusStyle.allCases { #expect(!style.title.isEmpty) }
        for level in [UsageLevel.normal, .elevated, .critical] { _ = Theme.color(for: level) }
        #expect(UsageLevel(fraction: 0.7).label == "High" && UsageLevel(fraction: 0.9).symbol != nil)
    }

    @Test func temperatureFormatting() {
        #expect(formatTemperature(43.4).contains("43"))
    }

    @Test func launchFlagParsing() {
        #expect(AppEnvironment.value(for: "--definitely-not-passed") == nil)
    }

    @Test func settingsSectionsSearch() {
        #expect(SettingsSection.windowRing.matches("mouse"))
        #expect(SettingsSection.fileConverter.matches("FFMPEG"))
        #expect(!SettingsSection.about.matches("ffmpeg"))
        #expect(SettingsSection.general.matches("  "))
        for section in SettingsSection.allCases {
            #expect(!section.title.isEmpty)
            #expect(NSImage(systemSymbolName: section.symbol, accessibilityDescription: nil) != nil, "\(section.symbol)")
        }
        let state = SettingsState()
        state.search = "sleep"
        #expect(state.visibleSections == [.power])
    }

    @Test func popoverTabsAndAdjacency() {
        let state = PopoverState()
        state.selectAdjacent(-1)
        #expect(state.selectedTab == AppTab.allCases.last)
        state.selectAdjacent(1)
        #expect(state.selectedTab == .system)
        state.select(.disk)
        #expect(state.visitedTabs.contains(.disk))
        for tab in AppTab.allCases {
            #expect(NSImage(systemSymbolName: tab.icon, accessibilityDescription: nil) != nil, "\(tab.icon)")
        }
    }

    @Test func ringSignalsWithoutPermissionAreHarmless() {
        let defaults = makeDefaults()
        let manager = WindowManagerService(defaults: defaults)
        let ring = WindowRingService(defaults: defaults, eventTap: nil, windowManager: manager)
        ring.handle(.triggerUp(apply: true))
        ring.handle(.cancel)
        #expect(!ring.isRingVisible)
        _ = WindowRingService.screenUnderCursor()
        for size in WindowRingService.RingSize.allCases { #expect(size.diameter > 0 && !size.title.isEmpty) }
    }

    @Test func jobOutputsCanMoveToAFolder() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("tully-job-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("out.txt")
        try Data("x".utf8).write(to: file)
        let target = dir.appendingPathComponent("results")
        let moved = try JobRunner.relocate([file], to: target)
        #expect(moved.first?.deletingLastPathComponent().lastPathComponent == "results")
        #expect(FileManager.default.fileExists(atPath: moved[0].path))
    }

    @Test func toastsShowAndClear() async throws {
        let toasts = ToastCenter()
        toasts.show("Saved")
        #expect(toasts.current?.message == "Saved")
        #expect(toasts.current?.symbol == "checkmark.circle.fill")
        toasts.dismiss()
        #expect(toasts.current == nil)
    }

    @Test func permissionMonitoringStarts() {
        let center = PermissionCenter(checker: .init(accessibility: { true }, screenRecording: { false }))
        center.startMonitoring()
        #expect(center.isAccessibilityGranted && !center.isScreenRecordingGranted)
    }
}
