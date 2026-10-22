import Darwin
import Foundation

public enum MemoryPressure {
    case normal, warning, critical
}

public struct MemorySnapshot {
    public let total: UInt64
    /// Sama dengan "Memory Used" di Activity Monitor: app + wired + compressed.
    public let used: UInt64
    public let app: UInt64
    public let wired: UInt64
    public let compressed: UInt64
    public let cached: UInt64
    public let swapUsed: UInt64
    public let pressure: MemoryPressure

    public var usedFraction: Double { Double(used) / Double(total) }
}

public final class MemoryReader {
    private let host = mach_host_self()
    private let pageSize = UInt64(vm_kernel_page_size)
    private let total = ProcessInfo.processInfo.physicalMemory

    public init() {}

    public func read() -> MemorySnapshot? {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(host, HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }

        let app = UInt64(stats.internal_page_count - stats.purgeable_count) * pageSize
        let wired = UInt64(stats.wire_count) * pageSize
        let compressed = UInt64(stats.compressor_page_count) * pageSize
        let cached = UInt64(stats.external_page_count + stats.purgeable_count) * pageSize

        return MemorySnapshot(
            total: total,
            used: app + wired + compressed,
            app: app,
            wired: wired,
            compressed: compressed,
            cached: cached,
            swapUsed: swapUsed(),
            pressure: pressure()
        )
    }

    private func swapUsed() -> UInt64 {
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        guard sysctlbyname("vm.swapusage", &usage, &size, nil, 0) == 0 else { return 0 }
        return usage.xsu_used
    }

    private func pressure() -> MemoryPressure {
        var level: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0) == 0 else { return .normal }
        switch level {
        case 4: return .critical
        case 2: return .warning
        default: return .normal
        }
    }
}
