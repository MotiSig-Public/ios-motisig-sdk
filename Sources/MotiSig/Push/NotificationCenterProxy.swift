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

    /// Records the delegate the host app assigned so we can forward after intercepting `setDelegate:`.
    func captureForwarding(_ delegate: UNUserNotificationCenterDelegate?) {
        guard let delegate, delegate !== self else { return }
        forwarding = delegate
    }

    func install() {
        let center = UNUserNotificationCenter.current()
        if center.delegate !== self {
            let prior = center.delegate
            forwarding = prior
            center.delegate = self
            logInstalled(prior: prior, reinstalled: false)
        }
    }

    /// Re-applies the proxy if another component replaced `delegate` after MotiSig initialized.
    func ensureInstalled() {
        let center = UNUserNotificationCenter.current()
        if center.delegate !== self {
            let prior = center.delegate
            forwarding = prior
            center.delegate = self
            logInstalled(prior: prior, reinstalled: true)
        }
    }

    private func logInstalled(prior: UNUserNotificationCenterDelegate?, reinstalled: Bool) {
        if let prior, prior !== self {
            let priorType = String(reflecting: type(of: prior))
            if reinstalled {
                Logger.shared.info("MotiSig re-installed UNUserNotificationCenter delegate proxy; prior delegate was: \(priorType).")
            } else {
                Logger.shared.debug("MotiSig installed UNUserNotificationCenter delegate proxy; prior delegate was: \(priorType).")
            }
        } else if reinstalled {
            Logger.shared.info("MotiSig re-installed UNUserNotificationCenter delegate proxy.")
        } else {
            Logger.shared.debug("MotiSig installed UNUserNotificationCenter delegate proxy.")
        }
    }

    // MARK: - UNUserNotificationCenterDelegate

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        Logger.shared.debug("NotificationCenterProxy willPresent called.")
        DispatchQueue.main.async { [weak self] in
            Logger.shared.debug("NotificationCenterProxy willPresent processing deferred block.")
            MotiSig.shared.deliverWillPresent(notification: notification)

            var didComplete = false
            self?.forwarding?.userNotificationCenter?(
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
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        Logger.shared.debug("NotificationCenterProxy didReceive called.")
        DispatchQueue.main.async { [weak self] in
            Logger.shared.debug("NotificationCenterProxy didReceive processing deferred block.")
            MotiSig.shared.deliverDidOpen(response: response)

            var didComplete = false
            self?.forwarding?.userNotificationCenter?(
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
}
