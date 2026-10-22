import Foundation
import IOKit

/// Pemakaian GPU dari statistik driver IOAccelerator (tanpa sudo).
public final class GPUReader {
    private let service: io_registry_entry_t

    public init?() {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iterator) == kIOReturnSuccess else {
            return nil
        }
        defer { IOObjectRelease(iterator) }

        var found: io_registry_entry_t = 0
        while case let entry = IOIteratorNext(iterator), entry != 0 {
            if GPUReader.statistics(of: entry)?["Device Utilization %"] != nil {
                found = entry
                break
            }
            IOObjectRelease(entry)
        }
        guard found != 0 else { return nil }
        service = found
    }

    deinit {
        IOObjectRelease(service)
    }

    /// Persentase pemakaian GPU, 0–100.
    public func utilization() -> Double? {
        guard let value = GPUReader.statistics(of: service)?["Device Utilization %"] as? NSNumber else { return nil }
        return value.doubleValue
    }

    private static func statistics(of entry: io_registry_entry_t) -> [String: Any]? {
        IORegistryEntryCreateCFProperty(entry, "PerformanceStatistics" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? [String: Any]
    }
}
