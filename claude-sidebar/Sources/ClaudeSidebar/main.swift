import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let usage = UsageStore()
    private let watcher = EventWatcher()
    private var sidebar: SidebarController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        sidebar = SidebarController(usage: usage)
        sidebar.show()
        usage.start()
        watcher.onEvent = { [weak self] event in self?.sidebar.present(event) }
        watcher.start()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory) // no Dock icon
app.run()
