import Foundation
import UserNotifications
#if canImport(UIKit) && !os(watchOS)
import UIKit
#endif

final class PushNotificationManager {
    /// Accessed lazily so ``MotiSig`` can load in XCTest hosts that do not support `UNUserNotificationCenter` until needed.
    private var center: UNUserNotificationCenter { UNUserNotificationCenter.current() }
    private var lastAuthorizationStatus: UNAuthorizationStatus?
    private var observer: NSObjectProtocol?

    deinit {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    /// Requests authorization (shows system prompt if needed) and always registers for remote notifications.
    func requestPermissionThenRegisterForRemote() async throws -> Bool {
        let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
        await registerForRemoteNotifications()
        return granted
    }

    /// Registers with APNs without showing the permission prompt (Expo `skipPermissionRequest` parity).
    func registerForRemoteNotificationsOnly() async {
        await registerForRemoteNotifications()
    }

    func currentAuthorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    /// Observes app foreground transitions to detect permission changes and re-assert the notification-center proxy.
    func startPermissionMonitoring(onAuthorizationStatusChange: @escaping (UNAuthorizationStatus) -> Void) {
        #if canImport(UIKit) && !os(watchOS)
        observer = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            NotificationCenterProxy.shared.ensureInstalled()
            guard let self else { return }
            Task {
                let status = await self.currentAuthorizationStatus()
                let prior = self.lastAuthorizationStatus
                self.lastAuthorizationStatus = status
                guard let prior else { return }
                guard prior != status else { return }
                onAuthorizationStatusChange(status)
            }
        }
        #endif
    }

    @MainActor
    private func registerForRemoteNotifications() {
        #if canImport(UIKit) && !os(watchOS)
        UIApplication.shared.registerForRemoteNotifications()
        #endif
    }

    static func tokenString(from deviceToken: Data) -> String {
        deviceToken.map { String(format: "%02x", $0) }.joined()
    }

    static func extractMessageId(from userInfo: [AnyHashable: Any]) -> String? {
        userInfo["messageId"] as? String
            ?? (userInfo["aps"] as? [String: Any])?["messageId"] as? String
            ?? userInfo["message_id"] as? String
            ?? (userInfo["_motisig"] as? [String: Any])?["messageId"] as? String
    }

    /// Stable key for deduplicating cold-start delivery (`launchOptions` + `didReceive` for the same tap).
    static func notificationCorrelationKey(from userInfo: [AnyHashable: Any]) -> String {
        if let messageId = extractMessageId(from: userInfo)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !messageId.isEmpty {
            return "m:\(messageId)"
        }
        var parts: [String] = []
        if let aps = userInfo["aps"] as? [String: Any] {
            if let alert = aps["alert"] as? [String: Any] {
                parts.append(alert["title"] as? String ?? "")
                parts.append(alert["body"] as? String ?? "")
            } else if let alert = aps["alert"] as? String {
                parts.append(alert)
            }
        }
        for key in userInfo.keys.compactMap({ $0 as? String }).sorted() where key != "aps" {
            parts.append("\(key)=\(String(describing: userInfo[key]!))")
        }
        return "h:\(parts.joined(separator: "\u{0000}").hashValue)"
    }

    /// Expo `data.suppressForeground === true`: skip foreground listener and foreground click tracking.
    static func shouldSuppressForeground(from userInfo: [AnyHashable: Any]) -> Bool {
        if let b = userInfo["suppressForeground"] as? Bool { return b }
        if let n = userInfo["suppressForeground"] as? NSNumber { return n.boolValue }
        if let s = userInfo["suppressForeground"] as? String {
            return s == "1" || s.caseInsensitiveCompare("true") == .orderedSame
        }
        return false
    }

    static func motiSigNotification(from notification: UNNotification, wasForeground: Bool = false) -> MotiSigNotification {
        let content = notification.request.content
        let userInfo = content.userInfo
        let rid = notification.request.identifier
        return motiSigNotification(
            from: userInfo,
            title: content.title.isEmpty ? nil : content.title,
            body: content.body.isEmpty ? nil : content.body,
            requestIdentifier: rid.isEmpty ? nil : rid,
            wasForeground: wasForeground
        )
    }

    /// Builds a notification from a raw APNs `userInfo` (e.g. cold-start `launchOptions[.remoteNotification]`).
    static func motiSigNotification(
        from userInfo: [AnyHashable: Any],
        wasForeground: Bool = false
    ) -> MotiSigNotification {
        var title: String?
        var body: String?
        if let aps = userInfo["aps"] as? [String: Any] {
            if let alert = aps["alert"] as? [String: Any] {
                title = alert["title"] as? String
                body = alert["body"] as? String
            } else if let alert = aps["alert"] as? String {
                body = alert
            }
        }
        return motiSigNotification(
            from: userInfo,
            title: title,
            body: body,
            requestIdentifier: nil,
            wasForeground: wasForeground
        )
    }

    private static func motiSigNotification(
        from userInfo: [AnyHashable: Any],
        title: String?,
        body: String?,
        requestIdentifier: String?,
        wasForeground: Bool
    ) -> MotiSigNotification {
        MotiSigNotification(
            messageId: extractMessageId(from: userInfo),
            title: title,
            body: body,
            userInfo: userInfo,
            requestIdentifier: requestIdentifier,
            wasForeground: wasForeground
        )
    }
}
