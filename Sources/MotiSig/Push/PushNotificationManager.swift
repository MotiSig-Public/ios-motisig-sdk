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
        return MotiSigNotification(
            messageId: extractMessageId(from: userInfo),
            title: content.title.isEmpty ? nil : content.title,
            body: content.body.isEmpty ? nil : content.body,
            userInfo: userInfo,
            requestIdentifier: rid.isEmpty ? nil : rid,
            wasForeground: wasForeground
        )
    }
}
