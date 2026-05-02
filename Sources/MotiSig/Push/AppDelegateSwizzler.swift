import Foundation
import ObjectiveC
#if canImport(UIKit) && !os(watchOS)
import UIKit
#endif

#if canImport(UIKit) && !os(watchOS)

/// Swizzles `UIApplicationDelegate` APNs callbacks so the host app does not need to forward tokens.
enum AppDelegateSwizzler {
    private static let lock = NSLock()
    private static var installed = false

    static func install() {
        lock.lock()
        defer { lock.unlock() }
        guard !installed else { return }
        installed = true

        DispatchQueue.main.async {
            installOnMainThread()
        }
    }

    private static func installOnMainThread() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { installOnMainThread() }
            return
        }

        guard let delegate = UIApplication.shared.delegate else {
            DispatchQueue.main.async { installOnMainThread() }
            return
        }

        let cls: AnyClass = type(of: delegate)
        swizzle(
            cls: cls,
            selector: #selector(UIApplicationDelegate.application(_:didRegisterForRemoteNotificationsWithDeviceToken:)),
            swizzled: #selector(MotiSigSwizzleTarget.motiSig_application(_:didRegisterForRemoteNotificationsWithDeviceToken:))
        )
        swizzle(
            cls: cls,
            selector: #selector(UIApplicationDelegate.application(_:didFailToRegisterForRemoteNotificationsWithError:)),
            swizzled: #selector(MotiSigSwizzleTarget.motiSig_application(_:didFailToRegisterForRemoteNotificationsWithError:))
        )
    }

    private static func swizzle(cls: AnyClass, selector: Selector, swizzled: Selector) {
        guard let swizzledMethod = class_getInstanceMethod(MotiSigSwizzleTarget.self, swizzled) else {
            Logger.shared.error("MotiSig swizzle: missing swizzled method.")
            return
        }

        let typesForAdd = objcTypes(for: selector) ?? method_getTypeEncoding(swizzledMethod)

        if let originalMethod = class_getInstanceMethod(cls, selector) {
            let originalIMP = method_getImplementation(originalMethod)
            let block = makeForwardingBlock(
                originalIMP: originalIMP,
                selector: selector,
                installToken: selector == #selector(UIApplicationDelegate.application(_:didRegisterForRemoteNotificationsWithDeviceToken:))
            )
            method_setImplementation(originalMethod, imp_implementationWithBlock(block))
        } else {
            guard let typesForAdd else {
                Logger.shared.error("MotiSig swizzle: missing type encoding for \(NSStringFromSelector(selector)).")
                return
            }
            let block = makeInstallOnlyBlock(
                selector: selector,
                installToken: selector == #selector(UIApplicationDelegate.application(_:didRegisterForRemoteNotificationsWithDeviceToken:))
            )
            let didAdd = class_addMethod(cls, selector, imp_implementationWithBlock(block), typesForAdd)
            if !didAdd {
                Logger.shared.error("MotiSig swizzle: class_addMethod failed for \(NSStringFromSelector(selector)).")
            }
        }
    }

    private static func objcTypes(for selector: Selector) -> UnsafePointer<Int8>? {
        guard let proto = objc_getProtocol("UIApplicationDelegate") else { return nil }
        var desc = protocol_getMethodDescription(proto, selector, false, true)
        if desc.types == nil {
            desc = protocol_getMethodDescription(proto, selector, true, true)
        }
        return UnsafePointer(desc.types)
    }

    private static func makeForwardingBlock(originalIMP: IMP, selector: Selector, installToken: Bool) -> AnyObject {
        if installToken {
            let block: @convention(block) (AnyObject, UIApplication, Data) -> Void = { appDelegate, application, deviceToken in
                MotiSig.shared.ingestAPNsDeviceToken(deviceToken)
                typealias Fn = @convention(c) (AnyObject, Selector, UIApplication, Data) -> Void
                unsafeBitCast(originalIMP, to: Fn.self)(appDelegate, selector, application, deviceToken)
            }
            return block as AnyObject
        } else {
            let block: @convention(block) (AnyObject, UIApplication, Error) -> Void = { appDelegate, application, error in
                Logger.shared.error("APNs registration failed: \(error.localizedDescription)")
                typealias Fn = @convention(c) (AnyObject, Selector, UIApplication, Error) -> Void
                unsafeBitCast(originalIMP, to: Fn.self)(appDelegate, selector, application, error)
            }
            return block as AnyObject
        }
    }

    private static func makeInstallOnlyBlock(selector: Selector, installToken: Bool) -> AnyObject {
        if installToken {
            let block: @convention(block) (AnyObject, UIApplication, Data) -> Void = { _, _, deviceToken in
                MotiSig.shared.ingestAPNsDeviceToken(deviceToken)
            }
            return block as AnyObject
        } else {
            let block: @convention(block) (AnyObject, UIApplication, Error) -> Void = { _, _, error in
                Logger.shared.error("APNs registration failed: \(error.localizedDescription)")
            }
            return block as AnyObject
        }
    }
}

/// Hosts `@objc` method implementations whose IMPs are copied onto the app delegate class.
private final class MotiSigSwizzleTarget: NSObject {
    @objc func motiSig_application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {}

    @objc func motiSig_application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {}
}

#else

enum AppDelegateSwizzler {
    static func install() {}
}

#endif
