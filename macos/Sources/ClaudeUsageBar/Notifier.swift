import Foundation
import UserNotifications
import UsageCore

@MainActor
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    var onClick: (() -> Void)?
    private var center: UNUserNotificationCenter { .current() }

    func setup() { center.delegate = self }

    func post(_ e: AlertEvent) async {
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            let ok = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
            AppLog.write("[notify] authorization \(ok ? "granted" : "denied")")
            if !ok { return }
        } else if settings.authorizationStatus == .denied {
            AppLog.write("[notify] denied in System Settings; skipped: \(e.title)")
            return
        }
        let c = UNMutableNotificationContent()
        c.title = e.title
        c.body = e.body
        if e.isDanger { c.sound = .default }
        do {
            try await center.add(UNNotificationRequest(identifier: UUID().uuidString, content: c, trigger: nil))
            AppLog.write("[notify] \(e.title)")
        } catch {
            AppLog.write("[notify] failed: \(error.localizedDescription)")
        }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification)
        async -> UNNotificationPresentationOptions { [.banner, .sound] }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        await MainActor.run { onClick?() }
    }
}
