import CPrivate
import Foundation

public struct TemperatureSensor {
    public let name: String
    public let celsius: Double
}

/// Membaca sensor suhu Apple Silicon lewat IOHIDEventSystem.
/// Client dan daftar service dibuat sekali lalu dipakai ulang di setiap pembacaan.
public final class TemperatureReader {
    private let client: IOHIDEventSystemClient
    private var services: [(name: String, service: IOHIDServiceClient)] = []

    public init?() {
        guard let client = IOHIDEventSystemClientCreate(kCFAllocatorDefault) else { return nil }
        // Usage page vendor Apple (0xff00), usage 5 = sensor suhu.
        let matching = ["PrimaryUsagePage": 0xff00, "PrimaryUsage": 5] as CFDictionary
        IOHIDEventSystemClientSetMatching(client, matching)
        self.client = client
        refreshServices()
    }

    public func refreshServices() {
        guard let list = IOHIDEventSystemClientCopyServices(client) as? [IOHIDServiceClient] else {
            services = []
            return
        }
        services = list.map { service in
            let name = IOHIDServiceClientCopyProperty(service, "Product" as CFString) as? String
            return (name ?? "Unknown", service)
        }
    }

    public func readAll() -> [TemperatureSensor] {
        services.compactMap { entry in
            guard let event = IOHIDServiceClientCopyEvent(entry.service, Int64(kIOHIDEventTypeTemperature), 0, 0) else {
                return nil
            }
            let value = IOHIDEventGetFloatValue(event, Int32(kIOHIDEventTypeTemperature << 16))
            // Abaikan nilai tidak masuk akal (sensor belum siap / tidak aktif).
            guard value > 0, value < 150 else { return nil }
            return TemperatureSensor(name: entry.name, celsius: value)
        }
    }
}
