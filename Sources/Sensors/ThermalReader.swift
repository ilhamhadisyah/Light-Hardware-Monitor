import Foundation
import os

public struct TemperatureReading {
    public let average: Double
    public let max: Double

    init?(_ values: [Double]) {
        guard let max = values.max() else { return nil }
        self.average = values.reduce(0, +) / Double(values.count)
        self.max = max
    }
}

public struct ThermalSnapshot {
    public let cpu: TemperatureReading?
    public let gpu: TemperatureReading?
}

/// Suhu CPU dan GPU dari SMC, dikelompokkan berdasarkan awalan key:
/// `Tp`/`Te` untuk CPU (P-core/E-core), `Tg` untuk GPU.
/// Jika chip tidak punya key CPU yang dikenal, CPU diambil dari sensor die IOHID (`PMU tdie`).
///
/// Setiap panggilan SMC cukup mahal, jadi tiap `read()` hanya membaca sebagian key secara bergiliran
/// (semua key terbaca sekali tiap `rounds` panggilan). Nilai key lain diambil dari pembacaan sebelumnya.
///
/// Pembacaan yang tidak masuk akal (mis. sesaat setelah bangun dari sleep) dibuang dan dicatat ke log;
/// key tersebut tetap memakai nilai valid terakhirnya.
public final class ThermalReader {
    private static let rounds = 4
    /// SoC yang menyala tidak mungkin lebih dingin dari suhu ruangan.
    private static let validRange = 10.0..<130.0
    /// Sensor yang jauh di bawah median kelompoknya hampir pasti salah baca.
    private static let maxBelowMedian = 25.0

    private let logger = Logger(subsystem: "local.HardwareMonitor", category: "sensors")
    private let smc: SMCReader?
    private let hid: TemperatureReader?
    /// Key CPU diikuti key GPU; `values` sejajar dengan `keys` (0 = belum ada nilai valid).
    private let keys: [String]
    private let cpuKeyCount: Int
    private var values: [Double]
    private var cursor = 0

    public var cpuSensorCount: Int { cpuKeyCount }
    public var gpuSensorCount: Int { keys.count - cpuKeyCount }
    public var usesHIDFallback: Bool { hid != nil }

    public init() {
        let smc = SMCReader()
        // Enumerasi key cukup sekali saat start; setelah itu hanya key terpilih yang dibaca.
        // Key tetap dipakai walau nilainya belum valid (mis. aplikasi dibuka tepat saat login).
        var cpu: [(String, Double)] = []
        var gpu: [(String, Double)] = []
        for key in smc?.allKeys() ?? [] {
            let isCPU = key.hasPrefix("Tp") || key.hasPrefix("Te")
            guard isCPU || key.hasPrefix("Tg"), let value = smc?.readDouble(key) else { continue }
            let initial = ThermalReader.validRange.contains(value) ? value : 0
            if isCPU {
                cpu.append((key, initial))
            } else {
                gpu.append((key, initial))
            }
        }
        self.smc = smc
        keys = (cpu + gpu).map(\.0)
        values = (cpu + gpu).map(\.1)
        cpuKeyCount = cpu.count
        hid = cpu.isEmpty ? TemperatureReader() : nil
    }

    public func read() -> ThermalSnapshot {
        let batch = (keys.count + ThermalReader.rounds - 1) / ThermalReader.rounds
        readKeys(from: cursor, count: batch)
        if !keys.isEmpty {
            cursor = (cursor + batch) % keys.count
        }
        return snapshot()
    }

    /// Baca ulang semua key sekaligus, mis. setelah Mac bangun dari sleep.
    public func refreshAll() {
        readKeys(from: 0, count: keys.count)
    }

    private func snapshot() -> ThermalSnapshot {
        let cpu: TemperatureReading?
        if let hid {
            let dies = hid.readAll().filter { $0.name.contains("tdie") }.map(\.celsius)
            cpu = ThermalReader.reading(dies[...])
        } else {
            cpu = ThermalReader.reading(values[..<cpuKeyCount])
        }
        return ThermalSnapshot(cpu: cpu, gpu: ThermalReader.reading(values[cpuKeyCount...]))
    }

    private func readKeys(from start: Int, count: Int) {
        guard let smc, !keys.isEmpty else { return }
        for offset in 0..<count {
            let index = (start + offset) % keys.count
            let value = smc.readDouble(keys[index])
            if let value, ThermalReader.validRange.contains(value) {
                values[index] = value
            } else {
                let text = value.map { String(format: "%.2f", $0) } ?? "gagal dibaca"
                logger.error("Nilai \(self.keys[index], privacy: .public) dibuang: \(text, privacy: .public)")
            }
        }
    }

    private static func reading(_ values: ArraySlice<Double>) -> TemperatureReading? {
        let valid = values.filter { validRange.contains($0) }.sorted()
        guard !valid.isEmpty else { return nil }
        let median = valid[valid.count / 2]
        return TemperatureReading(valid.filter { $0 >= median - maxBelowMedian })
    }
}
