import Foundation

/// Hooks for automated tests (`@testable import MotiSig`). Not used in production apps.
enum MotiSigTestBootstrap {
    /// When `true`, `MotiSig.initialize` skips push permission / remote registration **and** skips installing the `UNUserNotificationCenter` delegate proxy and UIKit APNs swizzling (for SPM / headless XCTest hosts).
    nonisolated(unsafe) static var skipPushPermissionAndRegistration = false
}
