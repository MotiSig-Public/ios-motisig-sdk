import Foundation
import UserNotifications

/// A notification still listed as delivered in the system Notification Center.
public struct MotiSigDeliveredNotification {
    public let requestIdentifier: String
    public let notification: MotiSigNotification
    public let date: Date

    init(notification: UNNotification) {
        self.requestIdentifier = notification.request.identifier
        self.date = notification.date
        self.notification = PushNotificationManager.motiSigNotification(from: notification)
    }
}
