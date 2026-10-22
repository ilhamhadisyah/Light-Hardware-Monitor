import Foundation
import Sensors

let arguments = CommandLine.arguments

// Mode `--smc`: cetak semua key suhu SMC (awalan "T") sebagai "KEY<tab>nilai".
if arguments.contains("--smc") {
    guard let smc = SMCReader() else {
        print("Gagal membuka AppleSMC")
        exit(1)
    }
    for key in smc.allKeys() where key.hasPrefix("T") {
        guard let value = smc.readDouble(key), value > 0, value < 150 else { continue }
        print("\(key)\t\(String(format: "%.1f", value))")
    }
    exit(0)
}

// Mode `--hid`: cetak semua sensor suhu IOHID.
if arguments.contains("--hid") {
    guard let reader = TemperatureReader() else {
        print("Gagal membuat IOHIDEventSystemClient")
        exit(1)
    }
    // Pembacaan pertama kadang belum berisi nilai, jadi ambil dua kali.
    _ = reader.readAll()
    Thread.sleep(forTimeInterval: 0.5)
    for sensor in reader.readAll().sorted(by: { $0.name < $1.name }) {
        let name = sensor.name.padding(toLength: 32, withPad: " ", startingAt: 0)
        print("\(name) \(String(format: "%6.1f", sensor.celsius)) °C")
    }
    exit(0)
}

// Mode `--watch DETIK`: baca semua key CPU/GPU tiap 0,25 detik dan laporkan nilai yang mencurigakan.
if let index = arguments.firstIndex(of: "--watch") {
    let duration = index + 1 < arguments.count ? Double(arguments[index + 1]) ?? 60 : 60
    guard let smc = SMCReader() else {
        print("Gagal membuka AppleSMC")
        exit(1)
    }
    let keys = smc.allKeys().filter { $0.hasPrefix("Tp") || $0.hasPrefix("Te") || $0.hasPrefix("Tg") }
    var lowest: [String: Double] = [:]
    var highest: [String: Double] = [:]
    var samples = 0
    let end = Date().addingTimeInterval(duration)
    let timeFormat = DateFormatter()
    timeFormat.dateFormat = "HH:mm:ss.SSS"
    while Date() < end {
        for key in keys {
            guard let (type, bytes) = smc.readRaw(key) else {
                print("\(timeFormat.string(from: Date())) \(key) gagal dibaca")
                continue
            }
            let value = smc.readDouble(key) ?? .nan
            lowest[key] = min(lowest[key] ?? value, value)
            highest[key] = max(highest[key] ?? value, value)
            if !(value >= 20 && value < 150) {
                let hex = bytes.map { String(format: "%02x", $0) }.joined(separator: " ")
                print("\(timeFormat.string(from: Date())) \(key) = \(String(format: "%.2f", value)) [\(type) \(hex)]")
            }
        }
        samples += 1
        Thread.sleep(forTimeInterval: 0.25)
    }
    print("\n\(samples) putaran. Rentang per key (min–maks):")
    for key in keys {
        print("\(key) \(String(format: "%.1f–%.1f", lowest[key] ?? .nan, highest[key] ?? .nan))")
    }
    exit(0)
}

// Mode `--bench`: 100 kali pembacaan suhu, bandingkan waktu nyata dengan waktu CPU proses.
if arguments.contains("--bench") {
    func cpuSeconds() -> Double {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        let user = Double(usage.ru_utime.tv_sec) + Double(usage.ru_utime.tv_usec) / 1e6
        let system = Double(usage.ru_stime.tv_sec) + Double(usage.ru_stime.tv_usec) / 1e6
        return user + system
    }
    let thermal = ThermalReader()
    let wallStart = Date()
    let cpuStart = cpuSeconds()
    for _ in 0..<100 { _ = thermal.read() }
    let wall = Date().timeIntervalSince(wallStart) * 10
    let cpu = (cpuSeconds() - cpuStart) * 10
    print(String(format: "Per pembacaan suhu: waktu nyata %.2f ms, waktu CPU %.2f ms", wall, cpu))
    exit(0)
}

// Default: ringkasan dari semua pembaca yang dipakai aplikasi menu bar.
func format(_ reading: TemperatureReading?) -> String {
    guard let reading else { return "-" }
    return String(format: "rata-rata %.1f °C, maks %.1f °C", reading.average, reading.max)
}

func gigabytes(_ bytes: UInt64) -> String {
    String(format: "%.2f GB", Double(bytes) / 1_073_741_824)
}

let start = Date()
let thermal = ThermalReader()
let memory = MemoryReader()
let gpu = GPUReader()
print(String(format: "Inisialisasi: %.0f ms", Date().timeIntervalSince(start) * 1000))
print("Sensor CPU: \(thermal.cpuSensorCount)\(thermal.usesHIDFallback ? " (fallback IOHID)" : ""), sensor GPU: \(thermal.gpuSensorCount)\n")

func measure<T>(_ label: String, _ body: () -> T) -> T {
    let start = Date()
    let value = body()
    print("\(label.padding(toLength: 11, withPad: " ", startingAt: 0)): \(String(format: "%.2f ms", Date().timeIntervalSince(start) * 1000))")
    return value
}

print("Waktu satu kali pembacaan:")
let snapshot = measure("suhu") { thermal.read() }
let mem = measure("memori") { memory.read() }
let gpuUsage = measure("pakai GPU") { gpu?.utilization() }
print()

print("Suhu CPU   : \(format(snapshot.cpu))")
print("Suhu GPU   : \(format(snapshot.gpu))")
print("Pakai GPU  : \(gpuUsage.map { String(format: "%.0f%%", $0) } ?? "-")")
if let mem {
    print("Memori     : \(gigabytes(mem.used)) / \(gigabytes(mem.total)) (\(String(format: "%.0f%%", mem.usedFraction * 100)))")
    print("  app \(gigabytes(mem.app)), wired \(gigabytes(mem.wired)), terkompresi \(gigabytes(mem.compressed)), cache \(gigabytes(mem.cached))")
    print("  swap \(gigabytes(mem.swapUsed)), tekanan \(mem.pressure)")
} else {
    print("Memori     : -")
}
