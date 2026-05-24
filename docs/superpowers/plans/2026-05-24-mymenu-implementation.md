# MyMenu Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a macOS menu bar app with System Monitor (CPU/RAM/disk/network/top processes/large folders) and Window Manager (user-configurable global keyboard shortcuts for 12 window zones).

**Architecture:** `AppDelegate` owns `NSStatusItem` + `NSPopover`. Two `@Observable` services (`SystemMonitorService`, `WindowManagerService`) drive SwiftUI views inside a `TabView`. A `nonisolated` `SystemSampler` struct handles Darwin API calls on a background `Task.detached`. `KeyboardShortcutHandler` runs a `CGEventTap` on a dedicated CFRunLoop thread.

**Tech Stack:** Swift 5.9+ / Xcode 26, SwiftUI + AppKit, Darwin (mach, proc, ifaddrs), CoreGraphics (CGEventTap), Accessibility API (AXUIElement). `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` is active — all types are `@MainActor` by default; background work uses `Task.detached` + `nonisolated`.

---

## File Map

| File | Action | Responsibility |
|---|---|---|
| `tully.xcodeproj/project.pbxproj` | Modify | Disable sandbox, add LSUIElement build key |
| `tully/tullyApp.swift` | Modify | `@main` entry, `NSApplicationDelegateAdaptor` |
| `tully/AppDelegate.swift` | Create | `NSStatusItem`, `NSPopover`, app lifecycle |
| `tully/ContentView.swift` | Modify | Root `TabView` |
| `tully/Shared/Models.swift` | Create | All shared types |
| `tully/Shared/PermissionView.swift` | Create | Accessibility denied UI |
| `tully/Modules/SystemMonitor/SystemSampler.swift` | Create | `nonisolated` struct, all Darwin sampling |
| `tully/Modules/SystemMonitor/SystemMonitorService.swift` | Create | `@Observable`, drives sampler |
| `tully/Modules/SystemMonitor/DiskScanService.swift` | Create | `@Observable`, `du` subprocess |
| `tully/Modules/SystemMonitor/SystemMonitorView.swift` | Create | SwiftUI System tab |
| `tully/Modules/WindowManager/WindowManagerService.swift` | Create | `@Observable`, AX window moving |
| `tully/Modules/WindowManager/KeyboardShortcutHandler.swift` | Create | `CGEventTap` on dedicated thread |
| `tully/Modules/WindowManager/WindowManagerView.swift` | Create | SwiftUI Windows tab, shortcut list |

---

### Task 1: Disable App Sandbox and add LSUIElement

**Files:**
- Modify: `tully.xcodeproj/project.pbxproj`

The project currently has `ENABLE_APP_SANDBOX = YES` which blocks `CGEventTap`, `proc_listallpids`, and `Process`. `LSUIElement` hides the app from Dock and App Switcher.

- [ ] **Step 1: Edit the two target XCBuildConfiguration blocks**

In `project.pbxproj`, find the block with key `BF2ED3162FC369E100F2ABD0 /* Debug */` (target Debug config, not project Debug config — it's the one with `ASSETCATALOG_COMPILER_APPICON_NAME`). Replace:

```
				ENABLE_APP_SANDBOX = YES;
				ENABLE_HARDENED_RUNTIME = YES;
				ENABLE_PREVIEWS = YES;
				ENABLE_USER_SELECTED_FILES = readonly;
				GENERATE_INFOPLIST_FILE = YES;
				INFOPLIST_KEY_NSHumanReadableCopyright = "";
```

With:

```
				ENABLE_APP_SANDBOX = NO;
				ENABLE_HARDENED_RUNTIME = NO;
				ENABLE_PREVIEWS = YES;
				GENERATE_INFOPLIST_FILE = YES;
				INFOPLIST_KEY_LSUIElement = YES;
				INFOPLIST_KEY_NSHumanReadableCopyright = "";
```

Then find `BF2ED3172FC369E100F2ABD0 /* Release */` and apply the same replacement.

Also remove `REGISTER_APP_GROUPS = YES;` from both blocks.

- [ ] **Step 2: Build in Xcode**

Open `tully.xcodeproj` in Xcode, press `⌘B`.
Expected: Build Succeeded with no errors.

- [ ] **Step 3: Verify app hides from Dock**

Run the app (`⌘R`). The app should NOT appear in the Dock or App Switcher. Quit via Xcode stop button.

- [ ] **Step 4: Commit**

```bash
git add tully.xcodeproj/project.pbxproj
git commit -m "chore: disable sandbox and add LSUIElement for menu bar app"
```

---

### Task 2: App Shell — Entry Point + AppDelegate + empty ContentView

**Files:**
- Modify: `tully/tullyApp.swift`
- Create: `tully/AppDelegate.swift`
- Modify: `tully/ContentView.swift`

- [ ] **Step 1: Replace tullyApp.swift**

```swift
// tully/tullyApp.swift
import SwiftUI

@main
struct MyMenuApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        Settings { }
    }
}
```

- [ ] **Step 2: Create AppDelegate.swift**

```swift
// tully/AppDelegate.swift
import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "menubar.rectangle", accessibilityDescription: "MyMenu")
            button.action = #selector(togglePopover)
            button.target = self
        }

        popover = NSPopover()
        popover.contentSize = NSSize(width: 340, height: 480)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: ContentView())
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}
```

- [ ] **Step 3: Replace ContentView.swift with placeholder**

```swift
// tully/ContentView.swift
import SwiftUI

struct ContentView: View {
    var body: some View {
        Text("MyMenu")
            .frame(width: 340, height: 480)
    }
}
```

- [ ] **Step 4: Build and run**

Press `⌘R`. Click the menu bar icon. A popover showing "MyMenu" should appear. Click outside to dismiss.

- [ ] **Step 5: Commit**

```bash
git add tully/tullyApp.swift tully/AppDelegate.swift tully/ContentView.swift
git commit -m "feat: add app shell with NSStatusItem and NSPopover"
```

---

### Task 3: Shared Models

**Files:**
- Create: `tully/Shared/Models.swift`

- [ ] **Step 1: Create Models.swift**

```swift
// tully/Shared/Models.swift
import CoreGraphics

// MARK: - System Monitor

struct SystemSnapshot: Sendable {
    var cpuPercent: Double = 0
    var ramUsed: UInt64 = 0
    var ramTotal: UInt64 = 0
    var diskUsed: Int64 = 0
    var diskTotal: Int64 = 0
    var netIn: Double = 0   // bytes/s
    var netOut: Double = 0  // bytes/s
    var topCPU: [ProcessInfo] = []
    var topRAM: [ProcessInfo] = []
}

struct ProcessInfo: Identifiable, Sendable {
    let id = UUID()
    var pid: Int32
    var name: String
    var cpuPercent: Double
    var ramBytes: UInt64
}

struct FolderInfo: Identifiable, Sendable {
    let id = UUID()
    var url: URL
    var bytes: Int64

    var name: String { url.lastPathComponent }
}

// MARK: - Window Manager

enum WindowZone: String, CaseIterable, Codable, Sendable {
    case leftHalf, rightHalf
    case leftThird, centerThird, rightThird
    case leftTwoThirds, rightTwoThirds
    case fullscreen
    case topLeft, topRight, bottomLeft, bottomRight

    var displayName: String {
        switch self {
        case .leftHalf:       return "Left Half"
        case .rightHalf:      return "Right Half"
        case .leftThird:      return "Left ⅓"
        case .centerThird:    return "Center ⅓"
        case .rightThird:     return "Right ⅓"
        case .leftTwoThirds:  return "Left ⅔"
        case .rightTwoThirds: return "Right ⅔"
        case .fullscreen:     return "Fullscreen"
        case .topLeft:        return "Top-Left"
        case .topRight:       return "Top-Right"
        case .bottomLeft:     return "Bottom-Left"
        case .bottomRight:    return "Bottom-Right"
        }
    }
}

struct ShortcutBinding: Codable, Hashable, Sendable {
    var keyCode: UInt16
    var modifiers: UInt64 // CGEventFlags.rawValue

    var displayString: String {
        var parts: [String] = []
        let flags = CGEventFlags(rawValue: modifiers)
        if flags.contains(.maskControl)  { parts.append("⌃") }
        if flags.contains(.maskAlternate) { parts.append("⌥") }
        if flags.contains(.maskShift)    { parts.append("⇧") }
        if flags.contains(.maskCommand)  { parts.append("⌘") }
        parts.append(keyCodeToString(keyCode))
        return parts.joined()
    }

    private func keyCodeToString(_ code: UInt16) -> String {
        let map: [UInt16: String] = [
            0:"A",1:"S",2:"D",3:"F",4:"H",5:"G",6:"Z",7:"X",8:"C",9:"V",
            11:"B",12:"Q",13:"W",14:"E",15:"R",16:"Y",17:"T",32:"U",34:"I",
            31:"O",35:"P",37:"L",38:"J",40:"K",45:"N",46:"M",
            123:"←",124:"→",125:"↓",126:"↑",
            36:"↩",48:"⇥",49:"Space",51:"⌫",53:"⎋",
        ]
        return map[code] ?? "(\(code))"
    }
}
```

- [ ] **Step 2: Build**

`⌘B`. Expected: Build Succeeded.

- [ ] **Step 3: Commit**

```bash
git add tully/Shared/Models.swift
git commit -m "feat: add shared model types"
```

---

### Task 4: SystemSampler — Darwin API sampling

**Files:**
- Create: `tully/Modules/SystemMonitor/SystemSampler.swift`

This is a plain `nonisolated` struct that does all heavy lifting with Darwin APIs. No actor isolation — called from `Task.detached`.

- [ ] **Step 1: Create SystemSampler.swift**

```swift
// tully/Modules/SystemMonitor/SystemSampler.swift
import Darwin
import Foundation

struct SystemSampler {
    private var prevCPU: host_cpu_load_info_data_t?
    private var prevNetIn: UInt64 = 0
    private var prevNetOut: UInt64 = 0
    private var prevProcTicks: [Int32: UInt64] = [:]
    private let sampleInterval: Double = 2.0

    // Called every 2s on background thread. Returns updated snapshot.
    mutating func sample() -> SystemSnapshot {
        let cpu   = sampleCPU()
        let ram   = sampleRAM()
        let disk  = sampleDisk()
        let net   = sampleNetwork()
        let procs = topProcesses()
        return SystemSnapshot(
            cpuPercent: cpu,
            ramUsed:    ram.used,
            ramTotal:   ram.total,
            diskUsed:   disk.used,
            diskTotal:  disk.total,
            netIn:      net.inBytes,
            netOut:     net.outBytes,
            topCPU:     procs.cpu,
            topRAM:     procs.ram
        )
    }

    // MARK: CPU

    private mutating func sampleCPU() -> Double {
        var count = mach_msg_type_number_t(
            MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size
        )
        var info = host_cpu_load_info_data_t()
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        defer { prevCPU = info }

        let user   = Double(info.cpu_ticks.0)
        let system = Double(info.cpu_ticks.1)
        let idle   = Double(info.cpu_ticks.2)
        let nice   = Double(info.cpu_ticks.3)

        guard let prev = prevCPU else { return 0 }
        let pUser   = Double(prev.cpu_ticks.0)
        let pSystem = Double(prev.cpu_ticks.1)
        let pIdle   = Double(prev.cpu_ticks.2)
        let pNice   = Double(prev.cpu_ticks.3)

        let totalDelta = (user + system + idle + nice) - (pUser + pSystem + pIdle + pNice)
        let usedDelta  = (user + system + nice) - (pUser + pSystem + pNice)
        guard totalDelta > 0 else { return 0 }
        return min(100.0, (usedDelta / totalDelta) * 100.0)
    }

    // MARK: RAM

    private func sampleRAM() -> (used: UInt64, total: UInt64) {
        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size
        )
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return (0, 0) }
        let page = UInt64(vm_kernel_page_size)
        let used = UInt64(stats.active_count + stats.wire_count + stats.compressor_page_count) * page
        let total = UInt64(ProcessInfo.processInfo.physicalMemory)
        return (used, total)
    }

    // MARK: Disk

    private func sampleDisk() -> (used: Int64, total: Int64) {
        guard let attrs = try? FileManager.default.attributesOfFileSystem(forPath: "/"),
              let total = attrs[.systemSize] as? Int64,
              let free  = attrs[.systemFreeSize] as? Int64
        else { return (0, 0) }
        return (total - free, total)
    }

    // MARK: Network

    private mutating func sampleNetwork() -> (inBytes: Double, outBytes: Double) {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return (0, 0) }
        defer { freeifaddrs(first) }

        var totalIn: UInt64 = 0
        var totalOut: UInt64 = 0
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let cur = cursor {
            let flags = Int32(cur.pointee.ifa_flags)
            let isLoopback = (flags & IFF_LOOPBACK) != 0
            let isUp       = (flags & IFF_UP) != 0
            let isLink     = cur.pointee.ifa_addr?.pointee.sa_family == UInt8(AF_LINK)
            if !isLoopback && isUp && isLink,
               let data = cur.pointee.ifa_data?.assumingMemoryBound(to: if_data.self) {
                totalIn  += UInt64(data.pointee.ifi_ibytes)
                totalOut += UInt64(data.pointee.ifi_obytes)
            }
            cursor = cur.pointee.ifa_next
        }

        let inDelta  = totalIn  >= prevNetIn  ? Double(totalIn  - prevNetIn)  : 0
        let outDelta = totalOut >= prevNetOut ? Double(totalOut - prevNetOut) : 0
        prevNetIn  = totalIn
        prevNetOut = totalOut
        return (inDelta / sampleInterval, outDelta / sampleInterval)
    }

    // MARK: Top Processes

    private mutating func topProcesses() -> (cpu: [ProcessInfo], ram: [ProcessInfo]) {
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return ([], []) }

        var pids = [Int32](repeating: 0, count: Int(count) + 32)
        let actual = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<Int32>.size))
        guard actual > 0 else { return ([], []) }

        var results: [ProcessInfo] = []

        for i in 0..<Int(actual) {
            let pid = pids[i]
            guard pid > 0 else { continue }

            var taskInfo = proc_taskinfo()
            let infoSize = Int32(MemoryLayout<proc_taskinfo>.size)
            guard proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &taskInfo, infoSize) == infoSize else { continue }

            var nameBuf = [CChar](repeating: 0, count: Int(MAXCOMLEN) + 1)
            proc_name(pid, &nameBuf, UInt32(nameBuf.count))
            let name = String(cString: nameBuf)

            let currentTicks = taskInfo.pti_total_user + taskInfo.pti_total_system
            let prevTicks    = prevProcTicks[pid] ?? currentTicks
            prevProcTicks[pid] = currentTicks

            let tickDeltaNs = currentTicks > prevTicks ? Double(currentTicks - prevTicks) : 0
            let cpuPercent  = (tickDeltaNs / (sampleInterval * 1_000_000_000.0)) * 100.0

            results.append(ProcessInfo(
                pid: pid,
                name: name.isEmpty ? "pid:\(pid)" : name,
                cpuPercent: cpuPercent,
                ramBytes: taskInfo.pti_resident_size
            ))
        }

        let topCPU = Array(results.sorted { $0.cpuPercent > $1.cpuPercent }.prefix(5))
        let topRAM = Array(results.sorted { $0.ramBytes   > $1.ramBytes   }.prefix(5))
        return (topCPU, topRAM)
    }
}
```

- [ ] **Step 2: Build**

`⌘B`. Expected: Build Succeeded.

If `proc_taskinfo` is not found: add `import Darwin` — it is part of the Darwin umbrella module which includes `<sys/proc_info.h>`. If `PROC_PIDTASKINFO` is missing, use the literal `4` (its value is always 4 in libproc.h).

- [ ] **Step 3: Commit**

```bash
git add tully/Modules/SystemMonitor/SystemSampler.swift
git commit -m "feat: add SystemSampler with CPU/RAM/disk/network/process sampling"
```

---

### Task 5: SystemMonitorService

**Files:**
- Create: `tully/Modules/SystemMonitor/SystemMonitorService.swift`

- [ ] **Step 1: Create SystemMonitorService.swift**

```swift
// tully/Modules/SystemMonitor/SystemMonitorService.swift
import Foundation

@Observable
final class SystemMonitorService {
    var snapshot = SystemSnapshot()
    private var samplerTask: Task<Void, Never>?

    func start() {
        samplerTask = Task.detached(priority: .utility) { [weak self] in
            var sampler = SystemSampler()
            while !Task.isCancelled {
                let snap = sampler.sample()
                await MainActor.run { self?.snapshot = snap }
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    func stop() {
        samplerTask?.cancel()
        samplerTask = nil
    }
}
```

- [ ] **Step 2: Build**

`⌘B`. Expected: Build Succeeded.

- [ ] **Step 3: Commit**

```bash
git add tully/Modules/SystemMonitor/SystemMonitorService.swift
git commit -m "feat: add SystemMonitorService driving background sampler"
```

---

### Task 6: DiskScanService

**Files:**
- Create: `tully/Modules/SystemMonitor/DiskScanService.swift`

- [ ] **Step 1: Create DiskScanService.swift**

```swift
// tully/Modules/SystemMonitor/DiskScanService.swift
import Foundation

@Observable
final class DiskScanService {
    var topFolders: [FolderInfo] = []
    var isScanning = false
    var lastScanDate: Date?

    func scan() {
        guard !isScanning else { return }
        isScanning = true
        Task.detached(priority: .utility) {
            let folders = await DiskScanService.runScan()
            await MainActor.run { [weak self] in
                self?.topFolders = folders
                self?.isScanning = false
                self?.lastScanDate = Date()
            }
        }
    }

    private static func runScan() async -> [FolderInfo] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        // du -sk: summarize, 1KB blocks. Shell expands glob.
        process.arguments = ["-c", "du -sk \"\(home)\"/* 2>/dev/null"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do { try process.run() } catch { return [] }
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return [] }

        var results: [FolderInfo] = []
        for line in output.components(separatedBy: "\n") {
            let parts = line.components(separatedBy: "\t")
            guard parts.count == 2,
                  let kbSize = Int64(parts[0].trimmingCharacters(in: .whitespaces))
            else { continue }
            let path = parts[1].trimmingCharacters(in: .whitespaces)
            guard !path.isEmpty else { continue }
            let url = URL(fileURLWithPath: path)
            results.append(FolderInfo(url: url, bytes: kbSize * 1024))
        }

        return results.sorted { $0.bytes > $1.bytes }
    }
}
```

- [ ] **Step 2: Build**

`⌘B`. Expected: Build Succeeded.

- [ ] **Step 3: Commit**

```bash
git add tully/Modules/SystemMonitor/DiskScanService.swift
git commit -m "feat: add DiskScanService with du-based large folder detection"
```

---

### Task 7: SystemMonitorView

**Files:**
- Create: `tully/Modules/SystemMonitor/SystemMonitorView.swift`

- [ ] **Step 1: Create SystemMonitorView.swift**

```swift
// tully/Modules/SystemMonitor/SystemMonitorView.swift
import SwiftUI

struct SystemMonitorView: View {
    @State private var monitor = SystemMonitorService()
    @State private var diskScanner = DiskScanService()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                cpuRamSection
                diskSection
                networkSection
                processSection
            }
            .padding(16)
        }
        .onAppear {
            monitor.start()
            diskScanner.scan()
        }
        .onDisappear {
            monitor.stop()
        }
    }

    // MARK: CPU + RAM

    private var cpuRamSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("CPU & Memory", systemImage: "cpu")
                .font(.headline)

            StatRow(label: "CPU", value: String(format: "%.1f%%", monitor.snapshot.cpuPercent)) {
                ProgressView(value: monitor.snapshot.cpuPercent / 100.0)
                    .tint(monitor.snapshot.cpuPercent > 80 ? .red : .blue)
            }

            StatRow(
                label: "RAM",
                value: "\(formatBytes(monitor.snapshot.ramUsed)) / \(formatBytes(monitor.snapshot.ramTotal))"
            ) {
                ProgressView(value: monitor.snapshot.ramTotal > 0
                    ? Double(monitor.snapshot.ramUsed) / Double(monitor.snapshot.ramTotal)
                    : 0)
            }
        }
    }

    // MARK: Disk

    private var diskSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Disk", systemImage: "internaldrive")
                .font(.headline)

            StatRow(
                label: "Storage",
                value: "\(formatBytes(monitor.snapshot.diskUsed)) / \(formatBytes(monitor.snapshot.diskTotal))"
            ) {
                ProgressView(value: monitor.snapshot.diskTotal > 0
                    ? Double(monitor.snapshot.diskUsed) / Double(monitor.snapshot.diskTotal)
                    : 0)
            }

            Divider()

            HStack {
                Text("Large Folders")
                    .font(.subheadline).bold()
                Spacer()
                if diskScanner.isScanning {
                    ProgressView().controlSize(.small)
                } else {
                    if let date = diskScanner.lastScanDate {
                        Text(date, style: .time)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Button("Rescan") { diskScanner.scan() }
                        .buttonStyle(.borderless)
                        .font(.caption)
                }
            }

            ForEach(diskScanner.topFolders.prefix(10)) { folder in
                HStack {
                    Text(folder.name)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Text(formatBytes(folder.bytes))
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    NSWorkspace.shared.open(folder.url)
                }
            }

            if diskScanner.topFolders.isEmpty && !diskScanner.isScanning {
                Text("No data").foregroundStyle(.secondary).font(.caption)
            }
        }
    }

    // MARK: Network

    private var networkSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Network", systemImage: "network")
                .font(.headline)
            HStack {
                Label("↓ \(formatBytes(Int64(max(0, monitor.snapshot.netIn))))/s", systemImage: "arrow.down")
                Spacer()
                Label("↑ \(formatBytes(Int64(max(0, monitor.snapshot.netOut))))/s", systemImage: "arrow.up")
            }
            .font(.subheadline)
        }
    }

    // MARK: Processes

    private var processSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Top Processes", systemImage: "list.bullet")
                .font(.headline)

            Text("By CPU").font(.caption).foregroundStyle(.secondary)
            ForEach(monitor.snapshot.topCPU) { proc in
                ProcessRow(info: proc, metric: String(format: "%.1f%%", proc.cpuPercent))
            }

            Divider()

            Text("By RAM").font(.caption).foregroundStyle(.secondary)
            ForEach(monitor.snapshot.topRAM) { proc in
                ProcessRow(info: proc, metric: formatBytes(proc.ramBytes))
            }
        }
    }
}

// MARK: - Subviews

private struct StatRow<Progress: View>: View {
    let label: String
    let value: String
    @ViewBuilder let progress: () -> Progress

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text(value).font(.caption.monospacedDigit())
            }
            progress()
        }
    }
}

private struct ProcessRow: View {
    let info: ProcessInfo
    let metric: String

    var body: some View {
        HStack {
            Text(info.name).lineLimit(1).font(.caption)
            Spacer()
            Text(metric).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Formatters

private func formatBytes<T: BinaryInteger>(_ bytes: T) -> String {
    let b = Double(bytes)
    if b >= 1_073_741_824 { return String(format: "%.1f GB", b / 1_073_741_824) }
    if b >= 1_048_576     { return String(format: "%.1f MB", b / 1_048_576) }
    if b >= 1_024         { return String(format: "%.1f KB", b / 1_024) }
    return "\(bytes) B"
}
```

- [ ] **Step 2: Wire into ContentView temporarily**

Replace `tully/ContentView.swift` body to verify:

```swift
struct ContentView: View {
    var body: some View {
        SystemMonitorView()
            .frame(width: 340, height: 480)
    }
}
```

- [ ] **Step 3: Build and run**

`⌘R`. Click menu bar icon. CPU%, RAM, disk, network, and process list should appear and update every 2s. Large folders appear after a few seconds.

- [ ] **Step 4: Commit**

```bash
git add tully/Modules/SystemMonitor/SystemMonitorView.swift tully/ContentView.swift
git commit -m "feat: add SystemMonitorView with all system metrics"
```

---

### Task 8: PermissionView

**Files:**
- Create: `tully/Shared/PermissionView.swift`

- [ ] **Step 1: Create PermissionView.swift**

```swift
// tully/Shared/PermissionView.swift
import SwiftUI

struct PermissionView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.shield")
                .font(.system(size: 48))
                .foregroundStyle(.orange)

            Text("Accessibility Required")
                .font(.headline)

            Text("MyMenu needs Accessibility access to move and resize windows.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("Open System Settings") {
                let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
                NSWorkspace.shared.open(url)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(24)
    }
}
```

- [ ] **Step 2: Build**

`⌘B`. Expected: Build Succeeded.

- [ ] **Step 3: Commit**

```bash
git add tully/Shared/PermissionView.swift
git commit -m "feat: add PermissionView for accessibility denied state"
```

---

### Task 9: WindowManagerService

**Files:**
- Create: `tully/Modules/WindowManager/WindowManagerService.swift`

- [ ] **Step 1: Create WindowManagerService.swift**

```swift
// tully/Modules/WindowManager/WindowManagerService.swift
import AppKit
import ApplicationServices

@Observable
final class WindowManagerService {
    var isPermissionGranted: Bool = false
    // key: WindowZone.rawValue → ShortcutBinding JSON
    var shortcuts: [String: ShortcutBinding] = [:]

    private let defaultsKey = "com.mymenu.shortcuts"

    func setup() {
        isPermissionGranted = AXIsProcessTrusted()
        loadShortcuts()
    }

    func moveActiveWindow(to zone: WindowZone) {
        guard isPermissionGranted else { return }

        let systemElement = AXUIElementCreateSystemWide()
        var focusedApp: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            systemElement, kAXFocusedApplicationAttribute as CFString, &focusedApp
        ) == .success, let app = focusedApp else { return }

        var focusedWindow: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            (app as! AXUIElement), kAXFocusedWindowAttribute as CFString, &focusedWindow
        ) == .success, let window = focusedWindow else { return }

        let windowElement = window as! AXUIElement
        let screen = screenForWindow(windowElement)
        let targetFrame = frame(for: zone, on: screen)
        applyFrame(targetFrame, to: windowElement, screen: screen)
    }

    func setShortcut(_ binding: ShortcutBinding?, for zone: WindowZone) {
        if let binding {
            shortcuts[zone.rawValue] = binding
        } else {
            shortcuts.removeValue(forKey: zone.rawValue)
        }
        saveShortcuts()
    }

    func conflictingZone(for binding: ShortcutBinding, excluding zone: WindowZone) -> WindowZone? {
        shortcuts.first(where: { $0.key != zone.rawValue && $0.value == binding })
            .flatMap { WindowZone(rawValue: $0.key) }
    }

    // MARK: - Private

    private func screenForWindow(_ window: AXUIElement) -> NSScreen {
        var positionValue: CFTypeRef?
        AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &positionValue)
        var position = CGPoint.zero
        if let pv = positionValue { AXValueGetValue(pv as! AXValue, .cgPoint, &position) }
        return NSScreen.screens.first { $0.frame.contains(position) } ?? NSScreen.main ?? NSScreen.screens[0]
    }

    private func frame(for zone: WindowZone, on screen: NSScreen) -> CGRect {
        let f = zone == .fullscreen ? screen.frame : screen.visibleFrame
        switch zone {
        case .leftHalf:       return CGRect(x: f.minX,          y: f.minY,          width: f.width / 2,     height: f.height)
        case .rightHalf:      return CGRect(x: f.midX,          y: f.minY,          width: f.width / 2,     height: f.height)
        case .leftThird:      return CGRect(x: f.minX,          y: f.minY,          width: f.width / 3,     height: f.height)
        case .centerThird:    return CGRect(x: f.minX + f.width / 3, y: f.minY,     width: f.width / 3,     height: f.height)
        case .rightThird:     return CGRect(x: f.minX + 2 * f.width / 3, y: f.minY, width: f.width / 3,    height: f.height)
        case .leftTwoThirds:  return CGRect(x: f.minX,          y: f.minY,          width: 2 * f.width / 3, height: f.height)
        case .rightTwoThirds: return CGRect(x: f.minX + f.width / 3, y: f.minY,    width: 2 * f.width / 3, height: f.height)
        case .fullscreen:     return f
        case .topLeft:        return CGRect(x: f.minX,          y: f.midY,          width: f.width / 2,     height: f.height / 2)
        case .topRight:       return CGRect(x: f.midX,          y: f.midY,          width: f.width / 2,     height: f.height / 2)
        case .bottomLeft:     return CGRect(x: f.minX,          y: f.minY,          width: f.width / 2,     height: f.height / 2)
        case .bottomRight:    return CGRect(x: f.midX,          y: f.minY,          width: f.width / 2,     height: f.height / 2)
        }
    }

    private func applyFrame(_ nsFrame: CGRect, to window: AXUIElement, screen: NSScreen) {
        // AX uses top-left origin; NSScreen uses bottom-left origin.
        // Primary screen height anchors the coordinate flip.
        let primaryHeight = NSScreen.screens.first?.frame.height ?? screen.frame.height
        let axY = primaryHeight - nsFrame.maxY

        var axOrigin = CGPoint(x: nsFrame.minX, y: axY)
        var axSize   = CGSize(width: nsFrame.width, height: nsFrame.height)

        if let posVal = AXValueCreate(.cgPoint, &axOrigin) {
            AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, posVal)
        }
        if let sizeVal = AXValueCreate(.cgSize, &axSize) {
            AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeVal)
        }
    }

    private func loadShortcuts() {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode([String: ShortcutBinding].self, from: data)
        else { return }
        shortcuts = decoded
    }

    private func saveShortcuts() {
        guard let encoded = try? JSONEncoder().encode(shortcuts) else { return }
        UserDefaults.standard.set(encoded, forKey: defaultsKey)
    }
}
```

- [ ] **Step 2: Build**

`⌘B`. Expected: Build Succeeded.

If `kAXFocusedApplicationAttribute` is not found: it is part of `ApplicationServices`. Add `import ApplicationServices` at top. It is already available via AppKit but explicit import removes ambiguity.

- [ ] **Step 3: Commit**

```bash
git add tully/Modules/WindowManager/WindowManagerService.swift
git commit -m "feat: add WindowManagerService with AX window moving and zone calculation"
```

---

### Task 10: KeyboardShortcutHandler

**Files:**
- Create: `tully/Modules/WindowManager/KeyboardShortcutHandler.swift`

- [ ] **Step 1: Create KeyboardShortcutHandler.swift**

```swift
// tully/Modules/WindowManager/KeyboardShortcutHandler.swift
import CoreGraphics
import Foundation

// @unchecked Sendable: thread safety managed manually via NSLock
final class KeyboardShortcutHandler: @unchecked Sendable {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var tapThread: Thread?
    private var tapRunLoop: CFRunLoop?

    private let lock = NSLock()
    private var _bindings: [ShortcutBinding: WindowZone] = [:]

    var onZoneTriggered: ((WindowZone) -> Void)?

    var bindings: [ShortcutBinding: WindowZone] {
        get { lock.withLock { _bindings } }
        set { lock.withLock { _bindings = newValue } }
    }

    func start() {
        guard eventTap == nil else { return } // prevent double-start
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        let selfPtr = Unmanaged.passRetained(self).toOpaque()

        guard let tap = CGEventTapCreate(
            .cgSessionEventTap,
            .headInsertEventTap,
            .defaultTap,
            mask,
            { proxy, type, event, userInfo -> Unmanaged<CGEvent>? in
                guard let userInfo else { return Unmanaged.passRetained(event) }
                let handler = Unmanaged<KeyboardShortcutHandler>.fromOpaque(userInfo).takeUnretainedValue()
                return handler.handleEvent(proxy: proxy, type: type, event: event)
            },
            selfPtr
        ) else {
            Unmanaged<KeyboardShortcutHandler>.fromOpaque(selfPtr).release()
            return
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)

        tapThread = Thread {
            self.tapRunLoop = CFRunLoopGetCurrent()
            if let source = self.runLoopSource {
                CFRunLoopAddSource(self.tapRunLoop, source, .commonModes)
            }
            CGEvent.tapEnable(tap: tap, enable: true)
            CFRunLoopRun()
        }
        tapThread?.name = "com.mymenu.eventtap"
        tapThread?.start()
    }

    func stop() {
        if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let rl = tapRunLoop { CFRunLoopStop(rl) }
        eventTap = nil
        runLoopSource = nil
        tapThread = nil
    }

    // Called from CGEventTap thread — must NOT touch MainActor state directly
    private func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        guard type == .keyDown else { return Unmanaged.passRetained(event) }
        let keyCode  = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let mods     = event.flags.rawValue & ~CGEventFlags.maskNonCoalesced.rawValue
        let binding  = ShortcutBinding(keyCode: keyCode, modifiers: mods)
        let bindings = self.bindings

        if let zone = bindings[binding] {
            let callback = onZoneTriggered
            DispatchQueue.main.async { callback?(zone) }
            return nil // consume event
        }
        return Unmanaged.passRetained(event)
    }
}
```

- [ ] **Step 2: Build**

`⌘B`. Expected: Build Succeeded.

- [ ] **Step 3: Commit**

```bash
git add tully/Modules/WindowManager/KeyboardShortcutHandler.swift
git commit -m "feat: add KeyboardShortcutHandler with CGEventTap on dedicated thread"
```

---

### Task 11: Wire WindowManagerService ↔ KeyboardShortcutHandler

**Files:**
- Modify: `tully/Modules/WindowManager/WindowManagerService.swift`

The `KeyboardShortcutHandler` needs to be owned and started by `WindowManagerService`. Add this to `WindowManagerService.swift`:

- [ ] **Step 1: Add handler property and wiring to WindowManagerService**

Add at the top of the class body (after `var shortcuts`):

```swift
    private let handler = KeyboardShortcutHandler()
```

Modify `setup()`:

```swift
    func setup() {
        isPermissionGranted = AXIsProcessTrusted()
        loadShortcuts()
        guard isPermissionGranted else { return }
        rebuildHandlerBindings()
        handler.onZoneTriggered = { [weak self] zone in
            self?.moveActiveWindow(to: zone)
        }
        handler.start()
    }
```

Add `rebuildHandlerBindings()` method:

```swift
    func rebuildHandlerBindings() {
        var map: [ShortcutBinding: WindowZone] = [:]
        for zone in WindowZone.allCases {
            if let binding = shortcuts[zone.rawValue] {
                map[binding] = zone
            }
        }
        handler.bindings = map
    }
```

Modify `setShortcut(_:for:)` to also rebuild:

```swift
    func setShortcut(_ binding: ShortcutBinding?, for zone: WindowZone) {
        if let binding {
            shortcuts[zone.rawValue] = binding
        } else {
            shortcuts.removeValue(forKey: zone.rawValue)
        }
        saveShortcuts()
        rebuildHandlerBindings()
    }
```

Add `teardown()`:

```swift
    func teardown() {
        handler.stop()
    }
```

- [ ] **Step 2: Build**

`⌘B`. Expected: Build Succeeded.

- [ ] **Step 3: Commit**

```bash
git add tully/Modules/WindowManager/WindowManagerService.swift
git commit -m "feat: wire KeyboardShortcutHandler into WindowManagerService"
```

---

### Task 12: WindowManagerView

**Files:**
- Create: `tully/Modules/WindowManager/WindowManagerView.swift`

- [ ] **Step 1: Create WindowManagerView.swift**

```swift
// tully/Modules/WindowManager/WindowManagerView.swift
import SwiftUI
import AppKit

struct WindowManagerView: View {
    @State private var service = WindowManagerService()
    @State private var recordingZone: WindowZone? = nil
    @State private var localMonitor: Any? = nil

    var body: some View {
        Group {
            if service.isPermissionGranted {
                shortcutList
            } else {
                PermissionView()
            }
        }
        .onAppear { service.setup() }
        .onDisappear {
            service.teardown()
            stopRecording()
        }
    }

    // MARK: - Shortcut List

    private var shortcutList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Window Zones")
                    .font(.headline)
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 8)

                ForEach(WindowZone.allCases, id: \.rawValue) { zone in
                    ShortcutRow(
                        zone: zone,
                        binding: service.shortcuts[zone.rawValue],
                        isRecording: recordingZone == zone,
                        hasConflict: conflictFor(zone) != nil
                    ) {
                        toggleRecording(for: zone)
                    } onClear: {
                        service.setShortcut(nil, for: zone)
                    }
                    Divider().padding(.leading, 16)
                }
            }
        }
    }

    // MARK: - Recording

    private func toggleRecording(for zone: WindowZone) {
        if recordingZone == zone {
            stopRecording()
        } else {
            stopRecording()
            recordingZone = zone
            localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                let binding = ShortcutBinding(
                    keyCode: event.keyCode,
                    modifiers: CGEventFlags(rawValue: UInt64(event.modifierFlags.rawValue)).rawValue
                        & ~CGEventFlags.maskNonCoalesced.rawValue
                )
                self.service.setShortcut(binding, for: zone)
                self.stopRecording()
                return nil // consume
            }
        }
    }

    private func stopRecording() {
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
        recordingZone = nil
    }

    private func conflictFor(_ zone: WindowZone) -> WindowZone? {
        guard let binding = service.shortcuts[zone.rawValue] else { return nil }
        return service.conflictingZone(for: binding, excluding: zone)
    }
}

// MARK: - ShortcutRow

private struct ShortcutRow: View {
    let zone: WindowZone
    let binding: ShortcutBinding?
    let isRecording: Bool
    let hasConflict: Bool
    let onTap: () -> Void
    let onClear: () -> Void

    var body: some View {
        HStack {
            Text(zone.displayName)
                .font(.body)
            Spacer()
            if isRecording {
                Text("Recording…")
                    .font(.caption)
                    .foregroundStyle(.blue)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.blue.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            } else if let b = binding {
                HStack(spacing: 4) {
                    Text(b.displayString)
                        .font(.caption.monospaced())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(hasConflict ? Color.red.opacity(0.15) : Color.secondary.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .foregroundStyle(hasConflict ? .red : .primary)
                        .help(hasConflict ? "Conflict with another zone" : "")
                    Button(action: onClear) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                }
            } else {
                Text("—")
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 8)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
    }
}
```

- [ ] **Step 2: Build**

`⌘B`. Expected: Build Succeeded.

- [ ] **Step 3: Commit**

```bash
git add tully/Modules/WindowManager/WindowManagerView.swift
git commit -m "feat: add WindowManagerView with shortcut recording and conflict detection"
```

---

### Task 13: Final ContentView — wire TabView

**Files:**
- Modify: `tully/ContentView.swift`

- [ ] **Step 1: Replace ContentView.swift**

```swift
// tully/ContentView.swift
import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            Tab("System", systemImage: "cpu") {
                SystemMonitorView()
            }
            Tab("Windows", systemImage: "rectangle.3.group") {
                WindowManagerView()
            }
        }
        .frame(width: 340, height: 480)
    }
}
```

- [ ] **Step 2: Build and run**

`⌘R`. Click menu bar icon. Two tabs appear: System (CPU/RAM/disk/processes/network) and Windows (zone list or PermissionView if Accessibility not granted).

- [ ] **Step 3: Verify System tab**

Switch to System tab. Confirm:
- CPU % updates every 2s
- RAM shows used/total
- Disk shows used/total + large folder list after scan
- Network shows ↓/↑ bytes/s
- Top 5 processes by CPU and RAM

- [ ] **Step 4: Verify Windows tab without permission**

If Accessibility is not granted: PermissionView shown. Click "Open System Settings" → goes to Privacy & Security → Accessibility. Quit app, grant permission, reopen.

- [ ] **Step 5: Verify Windows tab with permission**

With Accessibility granted: zone list appears. Click a row → "Recording…" label appears. Press a key combo (e.g., `⌃⌥←`) → shortcut assigned. Open any app window (e.g., Notes), press the shortcut → window snaps to Left Half.

- [ ] **Step 6: Commit**

```bash
git add tully/ContentView.swift
git commit -m "feat: wire final TabView with System and Windows tabs"
```

---

## Manual Test Plan

| Scenario | Expected |
|---|---|
| Launch app | Menu bar icon appears, no Dock icon |
| Click icon | Popover opens below icon |
| Click outside | Popover closes |
| System tab | CPU/RAM/disk/network updates every 2s |
| Large folder scan | Top-10 folders after ~3s, Rescan button re-triggers |
| Folder tap | Opens in Finder |
| No Accessibility | Windows tab shows PermissionView |
| Grant Accessibility, relaunch | Zone list appears |
| Record shortcut | Click zone row → Recording… → press combo → shortcut assigned |
| Duplicate shortcut | Both zone rows show shortcut in red |
| Press assigned shortcut | Frontmost window snaps to zone |
| Multi-monitor | Window snaps using its own screen, not NSScreen.main |
| Relaunch | Shortcuts persist (UserDefaults) |
