import Foundation

/// Handle returned when registering a notification listener. Call ``remove()`` to unregister.
///
/// - ``remove()`` is idempotent and safe from any thread.
/// - Clearing all listeners (e.g. ``MotiSig/logout()`` or ``MotiSig/removeAllNotificationListeners()``) removes the subscription from the registry; further ``remove()`` calls are no-ops.
/// - Dropping this object without calling ``remove()`` does **not** unregister the listener; the SDK holds the listener weakly until you call ``remove()`` or clear all listeners.
public final class MotiSigNotificationSubscription {
    private weak var motiSig: MotiSig?
    private let subscriptionId: UUID
    private let lock = NSLock()
    private var removed = false

    init(motiSig: MotiSig, subscriptionId: UUID) {
        self.motiSig = motiSig
        self.subscriptionId = subscriptionId
    }

    /// Unregisters this listener. Safe to call multiple times.
    public func remove() {
        lock.lock()
        guard !removed else {
            lock.unlock()
            return
        }
        removed = true
        lock.unlock()
        motiSig?.removeNotificationSubscription(id: subscriptionId)
    }
}
