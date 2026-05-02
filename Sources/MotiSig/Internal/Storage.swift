import Foundation

final class Storage {
    private let defaults: UserDefaults

    private enum Key {
        static let userId = "com.motisig.sdk.userId"
        static let apnsToken = "com.motisig.sdk.apnsToken"
        /// Customer preference: receive pushes for this device when `true` (default if unset).
        static let pushSubscriptionCustomerEnabled = "com.motisig.sdk.pushSubscriptionCustomerEnabled"
    }

    init() {
        self.defaults = UserDefaults(suiteName: "com.motisig.sdk") ?? .standard
    }

    var userId: String? {
        get { defaults.string(forKey: Key.userId) }
        set { defaults.set(newValue, forKey: Key.userId) }
    }

    var apnsToken: String? {
        get { defaults.string(forKey: Key.apnsToken) }
        set { defaults.set(newValue, forKey: Key.apnsToken) }
    }

    /// Persisted across `clear()` so the customer toggle survives logout on this device.
    var pushSubscriptionCustomerEnabled: Bool {
        get {
            if defaults.object(forKey: Key.pushSubscriptionCustomerEnabled) == nil {
                return true
            }
            return defaults.bool(forKey: Key.pushSubscriptionCustomerEnabled)
        }
        set {
            defaults.set(newValue, forKey: Key.pushSubscriptionCustomerEnabled)
        }
    }

    func clear() {
        defaults.removeObject(forKey: Key.userId)
        defaults.removeObject(forKey: Key.apnsToken)
    }
}
