import Foundation
import IOKit

nonisolated struct SensorReadings: Sendable {
    var gpuPercent: Double?
    var cpuTemperature: Double?  // °C
    var gpuTemperature: Double?  // °C
    var fanRPMs: [Double] = []
}

// MARK: - IOHIDEventSystem (private, stable since macOS 10.x; how every temp monitor reads Apple Silicon sensors)

@_silgen_name("IOHIDEventSystemClientCreate")
nonisolated private func IOHIDEventSystemClientCreate(_ allocator: CFAllocator?) -> Unmanaged<AnyObject>?
@_silgen_name("IOHIDEventSystemClientSetMatching")
nonisolated private func IOHIDEventSystemClientSetMatching(_ client: AnyObject, _ matching: CFDictionary) -> Int32
@_silgen_name("IOHIDEventSystemClientCopyServices")
nonisolated private func IOHIDEventSystemClientCopyServices(_ client: AnyObject) -> Unmanaged<CFArray>?
@_silgen_name("IOHIDServiceClientCopyProperty")
nonisolated private func IOHIDServiceClientCopyProperty(_ service: AnyObject, _ key: CFString) -> Unmanaged<AnyObject>?
@_silgen_name("IOHIDServiceClientCopyEvent")
nonisolated private func IOHIDServiceClientCopyEvent(_ service: AnyObject, _ type: Int64, _ options: Int32, _ timestamp: Int64) -> Unmanaged<AnyObject>?
@_silgen_name("IOHIDEventGetFloatValue")
nonisolated private func IOHIDEventGetFloatValue(_ event: AnyObject, _ field: Int32) -> Double

/// Reads GPU utilisation, temperatures and fan speeds without root.
nonisolated final class SensorReader {
    private static let temperatureEventType: Int64 = 15            // kIOHIDEventTypeTemperature
    private static let temperatureField: Int32 = 15 << 16          // IOHIDEventFieldBase(kIOHIDEventTypeTemperature)
    private static let plausibleTemperature = 1.0...130.0

    private let hidClient: AnyObject?
    private let smc = SMCConnection()

    init() {
        let client = IOHIDEventSystemClientCreate(kCFAllocatorDefault)?.takeRetainedValue()
        if let client {
            // Apple vendor page 0xff00, usage 5 = temperature sensors
            _ = IOHIDEventSystemClientSetMatching(client, ["PrimaryUsagePage": 0xff00, "PrimaryUsage": 5] as CFDictionary)
        }
        hidClient = client
    }

    func read() -> SensorReadings {
        let hid = hidTemperatures()
        let cpuSensors = hid.filter { $0.name.contains("tdie") || $0.name.contains("ACC") || $0.name.contains("CPU") }
        let gpuSensors = hid.filter { $0.name.localizedCaseInsensitiveContains("gpu") }
        return SensorReadings(
            gpuPercent: Self.gpuUtilization(),
            cpuTemperature: Self.average(cpuSensors.map(\.value)) ?? smc?.temperature(keys: ["TC0P", "TC0D", "TC0E"]),
            gpuTemperature: Self.average(gpuSensors.map(\.value)) ?? smc?.temperature(keys: ["TG0P", "TG0D"]),
            fanRPMs: smc?.fanSpeeds() ?? []
        )
    }

    private func hidTemperatures() -> [(name: String, value: Double)] {
        guard let hidClient,
              let services = IOHIDEventSystemClientCopyServices(hidClient)?.takeRetainedValue() as? [AnyObject]
        else { return [] }
        return services.compactMap { service in
            guard let name = IOHIDServiceClientCopyProperty(service, "Product" as CFString)?.takeRetainedValue() as? String,
                  let event = IOHIDServiceClientCopyEvent(service, Self.temperatureEventType, 0, 0)?.takeRetainedValue()
            else { return nil }
            let value = IOHIDEventGetFloatValue(event, Self.temperatureField)
            return Self.plausibleTemperature.contains(value) ? (name, value) : nil
        }
    }

    private static func gpuUtilization() -> Double? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iterator) == KERN_SUCCESS
        else { return nil }
        defer { IOObjectRelease(iterator) }
        var best: Double?
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            guard let stats = IORegistryEntryCreateCFProperty(service, "PerformanceStatistics" as CFString, kCFAllocatorDefault, 0)?
                    .takeRetainedValue() as? [String: Any],
                  let utilization = (stats["Device Utilization %"] ?? stats["GPU Activity(%)"]) as? NSNumber
            else { continue }
            best = max(best ?? 0, utilization.doubleValue)
        }
        return best
    }

    private static func average(_ values: [Double]) -> Double? {
        values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }
}

// MARK: - SMC

/// Minimal AppleSMC client: reads fan speeds and (Intel) temperatures.
private nonisolated final class SMCConnection {
    private struct Version { var major: UInt8 = 0, minor: UInt8 = 0, build: UInt8 = 0, reserved: UInt8 = 0, release: UInt16 = 0 }
    private struct PLimit { var version: UInt16 = 0, length: UInt16 = 0, cpu: UInt32 = 0, gpu: UInt32 = 0, mem: UInt32 = 0 }
    private struct KeyInfo {
        var dataSize: UInt32 = 0, dataType: UInt32 = 0, dataAttributes: UInt8 = 0
        var padding: (UInt8, UInt8, UInt8) = (0, 0, 0) // match the C struct's 12-byte size inside Param
    }
    private struct Param {
        var key: UInt32 = 0
        var version = Version()
        var pLimit = PLimit()
        var keyInfo = KeyInfo()
        var result: UInt8 = 0, status: UInt8 = 0, data8: UInt8 = 0
        var data32: UInt32 = 0
        var bytes: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8)
            = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
    }

    private static let handleEvent: UInt32 = 2     // kSMCHandleYPCEvent
    private static let readKey: UInt8 = 5          // kSMCReadKey
    private static let getKeyInfo: UInt8 = 9       // kSMCGetKeyInfo
    private static let paramSize = 80              // sizeof(SMCKeyData_t)

    private var connection: io_connect_t = 0

    init?() {
        guard MemoryLayout<Param>.size == Self.paramSize else { return nil } // layout must match the kernel's struct
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        guard IOServiceOpen(service, mach_task_self_, 0, &connection) == KERN_SUCCESS else { return nil }
    }

    deinit { IOServiceClose(connection) }

    func fanSpeeds() -> [Double] {
        guard let count = read("FNum").flatMap(Self.decode), count > 0 else { return [] }
        return (0..<Int(count)).compactMap { read("F\($0)Ac").flatMap(Self.decode) }
    }

    func temperature(keys: [String]) -> Double? {
        keys.lazy.compactMap { self.read($0).flatMap(Self.decode) }.first { (1...130).contains($0) }
    }

    // MARK: Private

    private func read(_ key: String) -> (type: String, bytes: [UInt8])? {
        var input = Param()
        input.key = Self.fourCC(key)
        input.data8 = Self.getKeyInfo
        guard let info = call(&input), info.keyInfo.dataSize > 0 else { return nil }

        input.keyInfo.dataSize = info.keyInfo.dataSize
        input.data8 = Self.readKey
        guard let output = call(&input) else { return nil }
        let bytes = withUnsafeBytes(of: output.bytes) { Array($0.prefix(Int(info.keyInfo.dataSize))) }
        return (Self.string(fromFourCC: info.keyInfo.dataType), bytes)
    }

    private func call(_ input: inout Param) -> Param? {
        var output = Param()
        var outputSize = MemoryLayout<Param>.stride
        let result = IOConnectCallStructMethod(connection, Self.handleEvent, &input, MemoryLayout<Param>.stride, &output, &outputSize)
        return result == KERN_SUCCESS && output.result == 0 ? output : nil
    }

    private static func decode(_ value: (type: String, bytes: [UInt8])) -> Double? {
        let b = value.bytes
        switch value.type {
        case "flt " where b.count >= 4:
            return Double(Float(bitPattern: UInt32(b[0]) | UInt32(b[1]) << 8 | UInt32(b[2]) << 16 | UInt32(b[3]) << 24))
        case "fpe2" where b.count >= 2:
            return Double(UInt16(b[0]) << 8 | UInt16(b[1])) / 4
        case "sp78" where b.count >= 2:
            return Double(Int16(bitPattern: UInt16(b[0]) << 8 | UInt16(b[1]))) / 256
        case "ui8 " where b.count >= 1:
            return Double(b[0])
        case "ui16" where b.count >= 2:
            return Double(UInt16(b[0]) << 8 | UInt16(b[1]))
        default:
            return nil
        }
    }

    private static func fourCC(_ key: String) -> UInt32 {
        key.utf8.prefix(4).reduce(0) { $0 << 8 | UInt32($1) }
    }

    private static func string(fromFourCC value: UInt32) -> String {
        String(bytes: [24, 16, 8, 0].map { UInt8((value >> $0) & 0xff) }, encoding: .ascii) ?? ""
    }
}
