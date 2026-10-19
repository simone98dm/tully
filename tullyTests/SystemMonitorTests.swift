import Testing
@testable import tully

@MainActor
struct SystemMonitorTests {
    func process(_ pid: Int32, parent: Int32 = 1, name: String, path: String = "", system: Bool = false,
                 cpu: Double = 0, ram: UInt64 = 0) -> ProcessInfo {
        ProcessInfo(pid: pid, parentPID: parent, name: name, path: path, isSystem: system, cpuPercent: cpu, ramBytes: ram)
    }

    @Test func helpersAggregateIntoTheirApp() {
        let processes = [
            process(10, name: "Chrome", path: "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome", cpu: 5, ram: 100),
            process(11, parent: 10, name: "Chrome Helper", path: "/Applications/Google Chrome.app/Contents/Frameworks/Helper", cpu: 3, ram: 50),
            process(12, parent: 11, name: "Chrome Helper (GPU)", cpu: 2, ram: 25),
        ]
        let groups = ProcessGroup.build(from: processes)
        #expect(groups.count == 1)
        let chrome = groups[0]
        #expect(chrome.name == "Chrome")
        #expect(chrome.members.count == 3)
        #expect(chrome.cpuPercent == 10)
        #expect(chrome.ramBytes == 175)
        #expect(chrome.iconPath == "/Applications/Google Chrome.app")
    }

    @Test func systemGroupHidesIdleMembersButCountsThem() {
        let processes = [
            process(2, name: "launchd-ish", path: "/usr/libexec/a", system: true, cpu: 0, ram: 1),
            process(3, name: "WindowServer", path: "/System/Library/b", system: true, cpu: 12, ram: 500 << 20),
        ]
        let system = ProcessGroup.build(from: processes).first { $0.isSystem }
        #expect(system?.members.map(\.name) == ["WindowServer"])
        #expect(system?.ramBytes == (500 << 20) + 1)
    }

    @Test func parentCyclesDoNotHang() {
        let processes = [process(20, parent: 21, name: "A"), process(21, parent: 20, name: "B")]
        #expect(ProcessGroup.build(from: processes).count >= 1)
    }

    @Test func cpuPercentMath() {
        #expect(SystemSampler.cpuPercent(used: 150, idle: 150, previousUsed: 100, previousIdle: 100) == 50)
        #expect(SystemSampler.cpuPercent(used: 100, idle: 100, previousUsed: 100, previousIdle: 100) == 0)
        #expect(SystemSampler.cpuPercent(used: 300, idle: 100, previousUsed: 100, previousIdle: 100) == 100)
    }

    @Test func networkRateHandlesCounterReset() {
        #expect(SystemSampler.rate(current: 3000, previous: 1000, interval: 2) == 1000)
        #expect(SystemSampler.rate(current: 10, previous: 1000, interval: 2) == 0)
    }

    @Test func memoryCountsActiveWiredCompressed() {
        let usage = SystemSampler.memoryUsage(active: 10, wired: 5, compressed: 2, pageSize: 16384)
        #expect(usage.used == 17 * 16384)
        #expect(usage.wired == 5 * 16384)
        #expect(usage.compressed == 2 * 16384)
    }

    @Test func historyIsBoundedAndIntervalPersists() {
        let defaults = makeDefaults()
        let service = SystemMonitorService(defaults: defaults)
        #expect(service.interval == 2)
        for _ in 0..<(SystemMonitorService.historyLength + 10) {
            _ = service.apply(SystemSnapshot(), groups: [])
        }
        #expect(service.history.count == SystemMonitorService.historyLength)
        service.interval = 5
        #expect(SystemMonitorService(defaults: defaults).interval == 5)
    }

    @Test func topGroupsSortedByMemory() {
        let service = SystemMonitorService(defaults: makeDefaults())
        let groups = ProcessGroup.build(from: [process(30, name: "Small", ram: 1), process(31, name: "Big", ram: 9)])
        _ = service.apply(SystemSnapshot(), groups: groups)
        #expect(service.topGroupsByMemory(1).map(\.name) == ["Big"])
    }

    @Test func samplerProducesPlausibleSnapshot() {
        var sampler = SystemSampler()
        _ = sampler.sample()
        let snap = sampler.sample()
        #expect(snap.ramTotal > 0 && snap.ramUsed <= snap.ramTotal)
        #expect(snap.diskTotal > 0)
        #expect((0...100).contains(snap.cpuPercent))
        #expect(!snap.processes.isEmpty)
    }
}

@MainActor
struct SamplerTieringTests {
    @Test func cheapSampleSkipsProcessesAndSensors() {
        var sampler = SystemSampler()
        let snap = sampler.sample(includeProcesses: false)
        #expect(snap.processes.isEmpty)
        #expect(snap.sensors.fanRPMs.isEmpty && snap.sensors.cpuTemperature == nil)
        #expect(snap.ramTotal > 0) // totals still sampled for the menu bar
    }

    @Test func serviceKeepsLastProcessListWhileHidden() {
        let service = SystemMonitorService(defaults: makeDefaults())
        var detailed = SystemSnapshot()
        detailed.processes = [ProcessInfo(pid: 5, name: "A", cpuPercent: 1, ramBytes: 1)]
        _ = service.apply(detailed, groups: ProcessGroup.build(from: detailed.processes))
        var cheap = SystemSnapshot()
        cheap.cpuPercent = 42
        _ = service.apply(cheap, groups: [])
        #expect(service.snapshot.cpuPercent == 42)
        #expect(service.snapshot.processes.count == 1)
        #expect(service.groups.count == 1)
    }
}
