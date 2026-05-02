import Foundation

struct NotificationItem: Identifiable {
    let id = UUID()
    let messageId: String?
    let title: String?
    let body: String?
    let userInfo: [String: Any]
    let receivedInForeground: Bool
    /// `UNNotificationRequest.identifier` when known; used to dedupe with `MotiSig.shared.fetchDeliveredNotifications()`.
    let requestIdentifier: String?
    /// True when the row was filled from `fetchDeliveredNotifications` (e.g. opened app from the icon, not the banner).
    let sourcedFromDeliveredCenter: Bool
    let receivedAt: Date
}
