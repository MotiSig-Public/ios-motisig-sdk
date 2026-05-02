import Foundation
#if canImport(UIKit) && !os(watchOS)
import UIKit

/// Schedules `ping()` on foreground/background transitions and on a configurable interval while active.
enum ForegroundPingMonitor {
    private static var pingTimer: Timer?
    private static var activeObserver: NSObjectProtocol?
    private static var backgroundObserver: NSObjectProtocol?

    static func installIfNeeded() {
        guard !MotiSigTestBootstrap.skipPushPermissionAndRegistration else { return }
        DispatchQueue.main.async {
            guard activeObserver == nil else { return }

            activeObserver = NotificationCenter.default.addObserver(
                forName: UIApplication.didBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { _ in
                MotiSig.shared.ping()
                restartHeartbeatTimer()
            }

            backgroundObserver = NotificationCenter.default.addObserver(
                forName: UIApplication.didEnterBackgroundNotification,
                object: nil,
                queue: .main
            ) { _ in
                invalidateHeartbeatTimer()
                MotiSig.shared.ping()
            }

            if UIApplication.shared.applicationState == .active {
                MotiSig.shared.ping()
                restartHeartbeatTimer()
            }
        }
    }

    /// Removes observers and timer (e.g. after ``MotiSig/reset()``).
    static func uninstall() {
        DispatchQueue.main.async {
            invalidateHeartbeatTimer()
            if let activeObserver {
                NotificationCenter.default.removeObserver(activeObserver)
                Self.activeObserver = nil
            }
            if let backgroundObserver {
                NotificationCenter.default.removeObserver(backgroundObserver)
                Self.backgroundObserver = nil
            }
        }
    }

    private static func invalidateHeartbeatTimer() {
        pingTimer?.invalidate()
        pingTimer = nil
    }

    private static func restartHeartbeatTimer() {
        invalidateHeartbeatTimer()
        let interval = TimeInterval(MotiSig.shared.pingHeartbeatIntervalSeconds)
        let timer = Timer(timeInterval: interval, repeats: true) { _ in
            MotiSig.shared.ping()
        }
        RunLoop.main.add(timer, forMode: .common)
        pingTimer = timer
    }
}

#endif
