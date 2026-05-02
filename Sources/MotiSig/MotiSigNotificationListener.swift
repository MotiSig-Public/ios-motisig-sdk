import Foundation

/// Receives push notification events delivered by MotiSig (foreground presentation or user interaction).
///
/// Register with ``MotiSig/addNotificationListener(_:order:)``, which returns a ``MotiSigNotificationSubscription``.
/// Use the optional `order` parameter to control delivery order among multiple listeners:
/// - `nil` is treated like `0` for sorting; among listeners with the same effective order, registration order (FIFO) applies.
/// - Lower integer values are notified before higher values.
///
/// The SDK holds listeners **weakly**; retain your listener for as long as you want callbacks.
public protocol MotiSigNotificationListener: AnyObject {
    /// Called when a remote notification is received (foreground) or opened from background.
    func motiSig(didReceiveNotification notification: MotiSigNotification, inForeground: Bool)
}
