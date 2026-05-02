import Foundation

/// A push notification delivered to the app (foreground or background interaction).
public struct MotiSigNotification {
    public let messageId: String?
    public let title: String?
    public let body: String?
    /// Raw APNs payload. Prefer `messageId`, `title`, and `body` when possible.
    public let userInfo: [String: Any]
    /// `UNNotificationRequest.identifier` when the event originated from UserNotifications; otherwise `nil`.
    public let requestIdentifier: String?
    /// When the user opens the notification, `true` if the same notification was previously delivered in the foreground (Expo `wasForeground`).
    public let wasForeground: Bool

    public init(
        messageId: String?,
        title: String?,
        body: String?,
        userInfo: [AnyHashable: Any],
        requestIdentifier: String? = nil,
        wasForeground: Bool = false
    ) {
        self.messageId = messageId
        self.title = title
        self.body = body
        let rid = requestIdentifier.flatMap { $0.isEmpty ? nil : $0 }
        self.requestIdentifier = rid
        self.wasForeground = wasForeground
        var plain: [String: Any] = [:]
        for (k, v) in userInfo {
            if let ks = k as? String {
                plain[ks] = v
            }
        }
        self.userInfo = plain
    }
}
