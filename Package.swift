// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "HardwareMonitor",
    platforms: [.macOS(.v14)],
    targets: [
        // Deklarasi C untuk API privat: HID (sensor suhu) dan AppleSMC.
        .target(
            name: "CPrivate",
            linkerSettings: [.linkedFramework("IOKit")]
        ),
        // Pembaca data sensor, dipakai bersama oleh probe dan aplikasi menu bar.
        .target(
            name: "Sensors",
            dependencies: ["CPrivate"]
        ),
        // Aplikasi menu bar.
        .executableTarget(
            name: "HardwareMonitor",
            dependencies: ["Sensors"]
        ),
        // CLI untuk menguji pembaca sensor (--smc, --hid, --bench).
        .executableTarget(
            name: "SensorProbe",
            dependencies: ["Sensors"]
        ),
    ]
)
