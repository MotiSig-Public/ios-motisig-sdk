import MotiSig
import UserNotifications

class NotificationService: UNNotificationServiceExtension {
    override func didReceive(
        _ request: UNNotificationRequest,
        withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
    ) {
        MotiSigRichPushHandler.handle(request: request, contentHandler: contentHandler)
    }
}
