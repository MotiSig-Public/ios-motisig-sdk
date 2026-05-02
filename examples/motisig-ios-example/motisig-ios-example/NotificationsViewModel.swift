import Foundation
import MotiSig
import Observation

@Observable
final class NotificationsViewModel: MotiSigNotificationListener {
    var notifications: [NotificationItem] = []
    var selectedNotificationID: UUID?

    private var subscription: MotiSigNotificationSubscription?

    func start() {
        subscription = MotiSig.shared.addNotificationListener(self)
    }

    func stop() {
        subscription?.remove()
        subscription = nil
    }

    /// Merges notifications still listed in the system Notification Center (e.g. received while backgrounded, app opened from icon).
    @MainActor
    func mergeDeliveredNotificationsFromSystem() async {
        let delivered = await MotiSig.shared.fetchDeliveredNotifications()
        var knownIds = Set(notifications.compactMap(\.requestIdentifier).filter { !$0.isEmpty })
        for entry in delivered {
            let rid = entry.requestIdentifier
            guard !rid.isEmpty, !knownIds.contains(rid) else { continue }
            let n = entry.notification
            let item = NotificationItem(
                messageId: n.messageId,
                title: n.title,
                body: n.body,
                userInfo: n.userInfo,
                receivedInForeground: false,
                requestIdentifier: rid,
                sourcedFromDeliveredCenter: true,
                receivedAt: entry.date
            )
            knownIds.insert(rid)
            notifications.insert(item, at: 0)
            Self.logIngestedPush(
                source: "delivered",
                inForeground: nil,
                messageId: item.messageId,
                title: item.title,
                userInfo: item.userInfo
            )
        }
        notifications = notifications.sorted {
            ($0.receivedAt, $0.id.uuidString) > ($1.receivedAt, $1.id.uuidString)
        }
    }

    nonisolated func motiSig(didReceiveNotification notification: MotiSigNotification, inForeground: Bool) {
        let messageId = notification.messageId
        let title = notification.title
        let body = notification.body
        let userInfo = notification.userInfo
        let requestIdentifier = notification.requestIdentifier
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if let rid = requestIdentifier, !rid.isEmpty,
               self.notifications.contains(where: { $0.requestIdentifier == rid }) {
                return
            }
            let item = NotificationItem(
                messageId: messageId,
                title: title,
                body: body,
                userInfo: userInfo,
                receivedInForeground: inForeground,
                requestIdentifier: requestIdentifier,
                sourcedFromDeliveredCenter: false,
                receivedAt: Date()
            )
            self.notifications.insert(item, at: 0)
            self.notifications = self.notifications.sorted {
                ($0.receivedAt, $0.id.uuidString) > ($1.receivedAt, $1.id.uuidString)
            }
            Self.logIngestedPush(
                source: "listener",
                inForeground: inForeground,
                messageId: item.messageId,
                title: item.title,
                userInfo: item.userInfo
            )
            if !inForeground {
                self.selectedNotificationID = item.id
            }
        }
    }

    /// Compact debug line for push payloads; `resolvedImageUrl` matches [NotificationDetailView] image section.
    private static func logIngestedPush(
        source: String,
        inForeground: Bool?,
        messageId: String?,
        title: String?,
        userInfo: [String: Any]
    ) {
        let resolved = NotificationDetailView.pushImageURL(from: userInfo)?.absoluteString ?? "nil"
        let fg: String
        if let inForeground {
            fg = String(inForeground)
        } else {
            fg = "n/a"
        }
        let titleShort = (title ?? "").prefix(80)
        let sample = imageKeysSample(from: userInfo)
        print(
            "[MotiSigExample] push ingest source=\(source) inForeground=\(fg) messageId=\(messageId ?? "nil") title=\(String(titleShort)) resolvedImageUrl=\(resolved) imageKeysSample=\(sample)"
        )
        print("[MotiSigExample] push raw userInfo=\(Self.rawUserInfoDescription(userInfo))")
    }

    private static func rawUserInfoDescription(_ userInfo: [String: Any]) -> String {
        if JSONSerialization.isValidJSONObject(userInfo),
           let data = try? JSONSerialization.data(withJSONObject: userInfo, options: [.sortedKeys, .prettyPrinted]),
           let json = String(data: data, encoding: .utf8) {
            return json
        }
        return String(describing: userInfo)
    }

    private static func imageKeysSample(from userInfo: [String: Any]) -> String {
        var parts: [String] = []
        if let m = userInfo["_motisig"] as? [String: Any] {
            parts.append("_motisig.imageUrl=\(m["imageUrl"] ?? "nil")")
            parts.append("_motisig.image_url=\(m["image_url"] ?? "nil")")
            parts.append("_motisig.image=\(m["image"] ?? "nil")")
        } else if userInfo["_motisig"] != nil {
            parts.append("_motisig=\(userInfo["_motisig"] ?? "nil")")
        }
        if let rc = userInfo["_richContent"] as? [String: Any] {
            parts.append("_richContent.image=\(rc["image"] ?? "nil")")
        }
        if let fcm = userInfo["fcm_options"] as? [String: Any] {
            parts.append("fcm_options.image=\(fcm["image"] ?? "nil")")
        }
        for key in ["image", "imageUrl", "image_url", "fcm_notification_image_url", "gcm.notification.image"] {
            if let v = userInfo[key] {
                parts.append("\(key)=\(v)")
            }
        }
        for key in userInfo.keys.sorted() where key.hasPrefix("ios_attachment_") && key.hasSuffix("_url") {
            parts.append("\(key)=\(userInfo[key] ?? "nil")")
        }
        return parts.isEmpty ? "{}" : "{\(parts.joined(separator: ", "))}"
    }
}
