import Testing
@testable import tully

@MainActor
struct AppSettingsTests {
    @Test func defaultsOffPersistAndReset() {
        let defaults = makeDefaults()
        let settings = AppSettings(defaults: defaults)
        #expect(!settings.showCPU && !settings.showRAM && !settings.showNet && !settings.showDisk)
        #expect(settings.statusStyle == .iconValue && settings.tintsHighUsage)
        settings.showCPU = true
        settings.showNet = true
        let reloaded = AppSettings(defaults: defaults)
        #expect(reloaded.showCPU && reloaded.showNet && !reloaded.showRAM)
        reloaded.resetAll()
        #expect(!AppSettings(defaults: defaults).showCPU)
    }
}
