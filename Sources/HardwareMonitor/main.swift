import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusController: StatusController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusController = StatusController()
    }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    // Tanpa ikon Dock, hanya di menu bar (sama dengan LSUIElement di Info.plist).
    app.setActivationPolicy(.accessory)
    app.run()
}
