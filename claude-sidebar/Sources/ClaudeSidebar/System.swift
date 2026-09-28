import Foundation
import ServiceManagement
import UserNotifications

enum Notifier {
    /// UserNotifications only works from inside a .app bundle.
    static var isBundled: Bool { Bundle.main.bundleURL.pathExtension == "app" }

    static func requestAuthorization() {
        guard isBundled else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func post(_ event: AgentEvent) {
        guard isBundled else { return }
        let content = UNMutableNotificationContent()
        content.title = "\(event.title) · \(event.project)"
        content.body = event.detail
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: event.id.uuidString, content: content, trigger: nil))
    }
}

enum LoginItem {
    static var enabled: Bool { SMAppService.mainApp.status == .enabled }

    static func set(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("Claude Sidebar: login item change failed: \(error)")
        }
    }
}
