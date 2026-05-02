import Foundation
import UserNotifications
#if canImport(UIKit) && !os(watchOS)
import UIKit
#endif

/// Installs itself as `UNUserNotificationCenter.current().delegate` and forwards to the previous delegate.
final class NotificationCenterProxy: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationCenterProxy()

    private weak var forwarding: UNUserNotificationCenterDelegate?

    private override init() {
        super.init()
    }

    func install() {
        let center = UNUserNotificationCenter.current()
        if center.delegate !== self {
            forwarding = center.delegate
            center.delegate = self
            Logger.shared.debug("MotiSig installed UNUserNotificationCenter delegate proxy.")
        }
    }

    /// Re-applies the proxy if another component replaced `delegate` after MotiSig initialized.
    func ensureInstalled() {
        let center = UNUserNotificationCenter.current()
        if center.delegate !== self {
            forwarding = center.delegate
            center.delegate = self
            Logger.shared.info("MotiSig re-installed UNUserNotificationCenter delegate proxy.")
        }
    }

    // MARK: - UNUserNotificationCenterDelegate

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        MotiSig.shared.deliverWillPresent(notification: notification)

        var didComplete = false
        forwarding?.userNotificationCenter?(
            center,
            willPresent: notification,
            withCompletionHandler: { options in
                didComplete = true
                completionHandler(options)
            }
        )
        if !didComplete {
            if #available(iOS 14.0, macOS 11.0, *) {
                completionHandler([.banner, .sound, .badge, .list])
            } else {
                completionHandler([.alert, .sound, .badge])
            }
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        MotiSig.shared.deliverDidOpen(response: response)

        var didComplete = false
        forwarding?.userNotificationCenter?(
            center,
            didReceive: response,
            withCompletionHandler: {
                didComplete = true
                completionHandler()
            }
        )
        if !didComplete {
            completionHandler()
        }
    }
}
