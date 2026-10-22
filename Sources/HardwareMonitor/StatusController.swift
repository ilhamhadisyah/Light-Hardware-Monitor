import AppKit
import Sensors
import ServiceManagement

/// Item menu bar: judul ringkas (suhu CPU, suhu GPU, RAM terpakai) dan menu berisi rincian.
@MainActor
final class StatusController: NSObject, NSMenuDelegate {
    private static let intervals: [TimeInterval] = [1, 2, 5]
    private static let intervalKey = "refreshInterval"
    private static let gigabyte = 1_073_741_824.0
    private static let wakeDelay: TimeInterval = 5

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let titleView = TitleView()
    private let thermal = ThermalReader()
    private let memory = MemoryReader()
    private let gpu = GPUReader()

    private var timer: Timer?
    private var lastTitleKey = ""
    private var menuIsOpen = false

    private let cpuItem = NSMenuItem()
    private let gpuItem = NSMenuItem()
    private let memoryItem = NSMenuItem()
    private let memoryDetailItem = NSMenuItem()
    private let memoryExtraItem = NSMenuItem()
    private var intervalItems: [NSMenuItem] = []
    private let loginItem = NSMenuItem()

    private var interval: TimeInterval {
        let stored = UserDefaults.standard.double(forKey: Self.intervalKey)
        return Self.intervals.contains(stored) ? stored : 2
    }

    override init() {
        super.init()
        // Posisi hasil ⌘-drag di menu bar diingat lewat autosaveName.
        statusItem.autosaveName = "HardwareMonitor"
        statusItem.button?.toolTip = "Hardware Monitor"
        statusItem.menu = buildMenu()
        setUpTitleView()
        observeScreenSleep()
        refresh()
        startTimer()
        releaseFreeMemory()
    }

    /// Pasang TitleView dan kunci lebar item ke lebar judul terpanjang,
    /// supaya item tidak bergeser-geser saat angka berubah.
    private func setUpTitleView() {
        guard let button = statusItem.button else { return }
        titleView.frame = button.bounds
        titleView.autoresizingMask = [.width, .height]
        button.addSubview(titleView)

        let memoryTemplate = ProcessInfo.processInfo.physicalMemory >= 10 * UInt64(Self.gigabyte) ? "00.0G" : "0.0G"
        let template = makeTitle(
            cpu: "99°", gpu: "99°", memory: memoryTemplate,
            cpuColor: .labelColor, gpuColor: .labelColor, memoryColor: .labelColor
        )
        statusItem.length = ceil(titleView.measure(widest: template))
    }

    /// Kembalikan halaman memori yang sudah dibebaskan (sisa startup / menu) ke sistem.
    private func releaseFreeMemory() {
        malloc_zone_pressure_relief(nil, 0)
    }

    // MARK: - Timer

    private func startTimer() {
        timer?.invalidate()
        let timer = Timer(timeInterval: interval, target: self, selector: #selector(tick), userInfo: nil, repeats: true)
        // Toleransi memberi macOS ruang untuk menggabungkan wakeup dengan proses lain.
        timer.tolerance = interval * 0.2
        // Mode .common supaya tetap berjalan saat menu sedang terbuka.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    @objc private func tick() {
        refresh()
    }

    private func observeScreenSleep() {
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(self, selector: #selector(pause), name: NSWorkspace.screensDidSleepNotification, object: nil)
        center.addObserver(self, selector: #selector(pause), name: NSWorkspace.willSleepNotification, object: nil)
        center.addObserver(self, selector: #selector(scheduleResume), name: NSWorkspace.screensDidWakeNotification, object: nil)
        center.addObserver(self, selector: #selector(scheduleResume), name: NSWorkspace.didWakeNotification, object: nil)
    }

    @objc private func pause() {
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(resume), object: nil)
        timer?.invalidate()
        timer = nil
    }

    /// Sensor SMC bisa memberi nilai keliru sesaat setelah Mac bangun, jadi pembacaan ditunda dulu.
    @objc private func scheduleResume() {
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(resume), object: nil)
        perform(#selector(resume), with: nil, afterDelay: Self.wakeDelay)
    }

    @objc private func resume() {
        thermal.refreshAll()
        refresh()
        startTimer()
    }

    // MARK: - Pembaruan data

    private func refresh() {
        let temperatures = thermal.read()
        let memorySnapshot = memory.read()
        updateTitle(temperatures: temperatures, memory: memorySnapshot)
        // Rincian menu hanya dihitung saat menu terlihat.
        if menuIsOpen {
            updateMenu(temperatures: temperatures, memory: memorySnapshot, gpuUsage: gpu?.utilization())
        }
    }

    private func updateTitle(temperatures: ThermalSnapshot, memory: MemorySnapshot?) {
        let cpu = temperatures.cpu?.average
        let gpu = temperatures.gpu?.average
        let cpuText = cpu.map { "\(Int($0.rounded()))°" } ?? "–"
        let gpuText = gpu.map { "\(Int($0.rounded()))°" } ?? "–"
        let memoryText = memory.map { String(format: "%.1fG", Double($0.used) / Self.gigabyte) } ?? "–"
        let cpuColor = temperatureColor(cpu)
        let gpuColor = temperatureColor(gpu)
        let memoryColor = pressureColor(memory?.pressure)

        // Hindari membuat ulang judul jika tidak ada yang berubah.
        let key = [cpuText, gpuText, memoryText, cpuColor.description, gpuColor.description, memoryColor.description].joined(separator: "|")
        guard key != lastTitleKey else { return }
        lastTitleKey = key

        titleView.rows = makeTitle(
            cpu: cpuText, gpu: gpuText, memory: memoryText,
            cpuColor: cpuColor, gpuColor: gpuColor, memoryColor: memoryColor
        )
    }

    private func makeTitle(
        cpu: String, gpu: String, memory: String,
        cpuColor: NSColor, gpuColor: NSColor, memoryColor: NSColor
    ) -> [TitleView.Row] {
        [
            TitleView.Row(label: "CPU", value: cpu, color: cpuColor),
            TitleView.Row(label: "GPU", value: gpu, color: gpuColor),
            TitleView.Row(label: "RAM", value: memory, color: memoryColor),
        ]
    }

    private func temperatureColor(_ celsius: Double?) -> NSColor {
        guard let celsius else { return .labelColor }
        if celsius >= 95 { return .systemRed }
        if celsius >= 80 { return .systemOrange }
        return .labelColor
    }

    private func pressureColor(_ pressure: MemoryPressure?) -> NSColor {
        switch pressure {
        case .critical: return .systemRed
        case .warning: return .systemOrange
        default: return .labelColor
        }
    }

    // MARK: - Menu

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self

        for item in [cpuItem, gpuItem, memoryItem, memoryDetailItem, memoryExtraItem] {
            menu.addItem(item)
        }
        memoryDetailItem.indentationLevel = 1
        memoryExtraItem.indentationLevel = 1
        menu.addItem(.separator())

        let intervalMenu = NSMenu()
        for seconds in Self.intervals {
            let item = NSMenuItem(title: "\(Int(seconds)) detik", action: #selector(selectInterval(_:)), keyEquivalent: "")
            item.target = self
            item.tag = Int(seconds)
            intervalMenu.addItem(item)
            intervalItems.append(item)
        }
        let intervalItem = NSMenuItem(title: "Interval refresh", action: nil, keyEquivalent: "")
        intervalItem.submenu = intervalMenu
        menu.addItem(intervalItem)
        updateIntervalChecks()

        loginItem.title = "Buka saat login"
        loginItem.action = #selector(toggleLaunchAtLogin)
        loginItem.target = self
        menu.addItem(loginItem)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Keluar", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        return menu
    }

    private func updateMenu(temperatures: ThermalSnapshot, memory: MemorySnapshot?, gpuUsage: Double?) {
        cpuItem.title = "Suhu CPU: \(describe(temperatures.cpu))"
        let usageText = gpuUsage.map { " · pemakaian \(Int($0.rounded()))%" } ?? ""
        gpuItem.title = "Suhu GPU: \(describe(temperatures.gpu))\(usageText)"

        guard let memory else {
            memoryItem.title = "Memori: –"
            memoryDetailItem.title = ""
            memoryExtraItem.title = ""
            return
        }
        memoryItem.title = "Memori: \(gigabytes(memory.used)) dari \(gigabytes(memory.total)) (\(Int((memory.usedFraction * 100).rounded()))%)"
        memoryDetailItem.title = "Aplikasi \(gigabytes(memory.app)) · Wired \(gigabytes(memory.wired)) · Terkompresi \(gigabytes(memory.compressed))"
        memoryExtraItem.title = "Tekanan \(describe(memory.pressure)) · Swap \(gigabytes(memory.swapUsed))"
    }

    private func describe(_ reading: TemperatureReading?) -> String {
        guard let reading else { return "tidak tersedia" }
        return String(format: "%.1f °C (maks %.1f °C)", locale: .current, reading.average, reading.max)
    }

    private func describe(_ pressure: MemoryPressure) -> String {
        switch pressure {
        case .normal: return "normal"
        case .warning: return "tinggi"
        case .critical: return "kritis"
        }
    }

    private func gigabytes(_ bytes: UInt64) -> String {
        String(format: "%.1f GB", locale: .current, Double(bytes) / Self.gigabyte)
    }

    @objc private func selectInterval(_ sender: NSMenuItem) {
        UserDefaults.standard.set(Double(sender.tag), forKey: Self.intervalKey)
        updateIntervalChecks()
        startTimer()
    }

    private func updateIntervalChecks() {
        for item in intervalItems {
            item.state = Double(item.tag) == interval ? .on : .off
        }
    }

    @objc private func toggleLaunchAtLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
            }
        } catch {
            NSLog("Gagal mengubah status buka saat login: \(error)")
        }
        // Jika macOS meminta persetujuan (atau pendaftaran gagal), arahkan ke Pengaturan > Login Items.
        if service.status == .requiresApproval || service.status == .notFound {
            SMAppService.openSystemSettingsLoginItems()
        }
        updateLoginItemState()
    }

    private func updateLoginItemState() {
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    func menuWillOpen(_ menu: NSMenu) {
        menuIsOpen = true
        // Status bisa diubah pengguna lewat Pengaturan Sistem, jadi dibaca ulang setiap menu dibuka.
        updateLoginItemState()
        refresh()
    }

    func menuDidClose(_ menu: NSMenu) {
        menuIsOpen = false
        releaseFreeMemory()
    }
}
