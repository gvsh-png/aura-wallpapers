import AppKit
import UserNotifications

/// System notifications for agent permission requests, with Allow / Allow All / Deny right on the banner.
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = Notifier()
    private static let category = "AURA_PERMISSION"

    private var center: UNUserNotificationCenter { .current() }

    func setUp() {
        center.delegate = self
        center.setNotificationCategories([
            UNNotificationCategory(identifier: Self.category, actions: [
                UNNotificationAction(identifier: "ALLOW", title: "Allow"),
                UNNotificationAction(identifier: "ALLOW_ALL", title: "Allow All"),
                UNNotificationAction(identifier: "DENY", title: "Deny", options: .destructive),
            ], intentIdentifiers: []),
        ])
    }

    /// Only when Aura isn't in front; the in-app card covers the rest.
    @MainActor
    func permissionNeeded(_ request: ACPSession.PermissionRequest, agent: String) {
        guard !NSApp.isActive else { return }
        center.requestAuthorization(options: [.alert, .sound]) { [center] granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = "\(agent) needs your permission"
            content.body = String(request.title.prefix(220))
            content.sound = .default
            content.categoryIdentifier = Self.category
            content.interruptionLevel = .timeSensitive
            center.add(UNNotificationRequest(identifier: request.id.uuidString, content: content, trigger: nil))
        }
    }

    func clear(_ id: UUID) {
        center.removeDeliveredNotifications(withIdentifiers: [id.uuidString])
        center.removePendingNotificationRequests(withIdentifiers: [id.uuidString])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completion: @escaping (UNNotificationPresentationOptions) -> Void) {
        completion([.banner, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completion: @escaping () -> Void) {
        let id = UUID(uuidString: response.notification.request.identifier)
        let action = response.actionIdentifier
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                let session = AgentStudio.shared.acp
                guard let id, let request = session.permissions.first(where: { $0.id == id }) else { return }
                switch action {
                case "ALLOW": session.allow(request)
                case "ALLOW_ALL": session.approveAll(request)
                case "DENY": session.deny(request)
                default: // clicked the banner itself
                    AgentStudio.shared.showRequested = .now
                    WindowOpener.show()
                }
            }
        }
        completion()
    }
}
