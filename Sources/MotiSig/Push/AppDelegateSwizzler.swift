import Foundation
import ObjectiveC
#if canImport(UIKit) && !os(watchOS)
import UIKit
#endif

#if canImport(UIKit) && !os(watchOS)

/// Swizzles `UIApplicationDelegate` launch and APNs callbacks so the host app does not need to forward tokens.
enum AppDelegateSwizzler {
    private static let lock = NSLock()
    private static var tokenSwizzlesInstalled = false
    private static var configurationForConnectingSwizzled = false
    private static var setDelegateSwizzled = false

    /// Installs APNs token swizzles (called from ``MotiSig`` during `initialize`).
    static func install() {
        lock.lock()
        let already = tokenSwizzlesInstalled
        if !already { tokenSwizzlesInstalled = true }
        lock.unlock()
        guard !already else { return }

        installOnMain {
            installTokenSwizzlesOnMainThread()
            installConfigurationForConnectingSwizzleOnMainThread()
            swizzleUNUserNotificationCenterSetDelegate()
        }
    }

    private static func installOnMain(_ work: @escaping () -> Void) {
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.sync(execute: work)
        }
    }

    private static func installConfigurationForConnectingSwizzleOnMainThread() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { installConfigurationForConnectingSwizzleOnMainThread() }
            return
        }

        lock.lock()
        let already = configurationForConnectingSwizzled
        lock.unlock()
        guard !already else { return }

        guard let delegate = UIApplication.shared.delegate else {
            DispatchQueue.main.async { installConfigurationForConnectingSwizzleOnMainThread() }
            return
        }

        swizzleConfigurationForConnecting(cls: type(of: delegate))

        lock.lock()
        configurationForConnectingSwizzled = true
        lock.unlock()
    }

    private static func installTokenSwizzlesOnMainThread() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { installTokenSwizzlesOnMainThread() }
            return
        }

        guard let delegate = UIApplication.shared.delegate else {
            DispatchQueue.main.async { installTokenSwizzlesOnMainThread() }
            return
        }

        let cls: AnyClass = type(of: delegate)
        swizzle(
            cls: cls,
            selector: #selector(UIApplicationDelegate.application(_:didRegisterForRemoteNotificationsWithDeviceToken:)),
            swizzled: #selector(MotiSigSwizzleTarget.motiSig_application(_:didRegisterForRemoteNotificationsWithDeviceToken:)),
            kind: .apnsToken
        )
        swizzle(
            cls: cls,
            selector: #selector(UIApplicationDelegate.application(_:didFailToRegisterForRemoteNotificationsWithError:)),
            swizzled: #selector(MotiSigSwizzleTarget.motiSig_application(_:didFailToRegisterForRemoteNotificationsWithError:)),
            kind: .apnsTokenFail
        )
    }

    private enum SwizzleKind {
        case apnsToken
        case apnsTokenFail
    }

    private static func swizzleConfigurationForConnecting(cls: AnyClass) {
        let selector = #selector(
            UIApplicationDelegate.application(_:configurationForConnecting:options:)
        )
        guard let swizzledMethod = class_getInstanceMethod(
            MotiSigSwizzleTarget.self,
            #selector(MotiSigSwizzleTarget.motiSig_application(_:configurationForConnecting:options:))
        ) else {
            Logger.shared.error("MotiSig swizzle: missing configurationForConnecting swizzled method.")
            return
        }

        let typesForAdd = objcTypes(for: selector) ?? method_getTypeEncoding(swizzledMethod)

        if let originalMethod = class_getInstanceMethod(cls, selector) {
            let originalIMP = method_getImplementation(originalMethod)
            let block = makeConfigurationForConnectingForwardingBlock(originalIMP: originalIMP, selector: selector)
            method_setImplementation(originalMethod, imp_implementationWithBlock(block))
        } else {
            guard let typesForAdd else {
                Logger.shared.error("MotiSig swizzle: missing type encoding for \(NSStringFromSelector(selector)).")
                return
            }
            let block = makeConfigurationForConnectingInstallOnlyBlock()
            let didAdd = class_addMethod(cls, selector, imp_implementationWithBlock(block), typesForAdd)
            if !didAdd {
                Logger.shared.error("MotiSig swizzle: class_addMethod failed for \(NSStringFromSelector(selector)).")
            }
        }
    }

    private static func swizzleUNUserNotificationCenterSetDelegate() {
        lock.lock()
        let already = setDelegateSwizzled
        lock.unlock()
        guard !already else { return }

        let cls: AnyClass = UNUserNotificationCenter.self
        let selector = #selector(setter: UNUserNotificationCenter.delegate)
        guard let originalMethod = class_getInstanceMethod(cls, selector) else {
            Logger.shared.error("MotiSig swizzle: missing UNUserNotificationCenter.setDelegate:.")
            return
        }

        let originalIMP = method_getImplementation(originalMethod)
        let block: @convention(block) (AnyObject, UNUserNotificationCenterDelegate?) -> Void = { centerObj, newDelegate in
            if newDelegate === NotificationCenterProxy.shared {
                typealias Fn = @convention(c) (AnyObject, Selector, UNUserNotificationCenterDelegate?) -> Void
                unsafeBitCast(originalIMP, to: Fn.self)(centerObj, selector, newDelegate)
                return
            }
            if let newDelegate {
                Logger.shared.debug(
                    "UNUserNotificationCenter.setDelegate intercepted; new=\(String(reflecting: type(of: newDelegate)))"
                )
                NotificationCenterProxy.shared.captureForwarding(newDelegate)
            }
            typealias Fn = @convention(c) (AnyObject, Selector, UNUserNotificationCenterDelegate?) -> Void
            unsafeBitCast(originalIMP, to: Fn.self)(centerObj, selector, NotificationCenterProxy.shared)
        }
        method_setImplementation(originalMethod, imp_implementationWithBlock(block))

        lock.lock()
        setDelegateSwizzled = true
        lock.unlock()
    }

    private static func captureSceneConnectionResponse(from options: UIScene.ConnectionOptions) {
        guard let response = options.notificationResponse else { return }
        let reqId = response.notification.request.identifier
        Logger.shared.debug("configurationForConnecting fired; notificationResponse=\(reqId)")
        MotiSig.shared.deliverSceneConnectionResponse(response)
    }

    private static func makeConfigurationForConnectingForwardingBlock(
        originalIMP: IMP,
        selector: Selector
    ) -> AnyObject {
        let block: @convention(block) (
            AnyObject,
            UIApplication,
            UISceneSession,
            UIScene.ConnectionOptions
        ) -> UISceneConfiguration = { appDelegate, application, session, options in
            captureSceneConnectionResponse(from: options)
            typealias Fn = @convention(c) (
                AnyObject,
                Selector,
                UIApplication,
                UISceneSession,
                UIScene.ConnectionOptions
            ) -> UISceneConfiguration
            return unsafeBitCast(originalIMP, to: Fn.self)(appDelegate, selector, application, session, options)
        }
        return block as AnyObject
    }

    private static func makeConfigurationForConnectingInstallOnlyBlock() -> AnyObject {
        let block: @convention(block) (
            AnyObject,
            UIApplication,
            UISceneSession,
            UIScene.ConnectionOptions
        ) -> UISceneConfiguration = { _, _, session, options in
            captureSceneConnectionResponse(from: options)
            return UISceneConfiguration(name: nil, sessionRole: session.role)
        }
        return block as AnyObject
    }

    private static func swizzle(cls: AnyClass, selector: Selector, swizzled: Selector, kind: SwizzleKind) {
        guard let swizzledMethod = class_getInstanceMethod(MotiSigSwizzleTarget.self, swizzled) else {
            Logger.shared.error("MotiSig swizzle: missing swizzled method.")
            return
        }

        let typesForAdd = objcTypes(for: selector) ?? method_getTypeEncoding(swizzledMethod)

        if let originalMethod = class_getInstanceMethod(cls, selector) {
            let originalIMP = method_getImplementation(originalMethod)
            let block = makeForwardingBlock(originalIMP: originalIMP, selector: selector, kind: kind)
            method_setImplementation(originalMethod, imp_implementationWithBlock(block))
        } else {
            guard let typesForAdd else {
                Logger.shared.error("MotiSig swizzle: missing type encoding for \(NSStringFromSelector(selector)).")
                return
            }
            let block = makeInstallOnlyBlock(kind: kind)
            let didAdd = class_addMethod(cls, selector, imp_implementationWithBlock(block), typesForAdd)
            if !didAdd {
                Logger.shared.error("MotiSig swizzle: class_addMethod failed for \(NSStringFromSelector(selector)).")
            }
        }
    }

    private static func makeForwardingBlock(originalIMP: IMP, selector: Selector, kind: SwizzleKind) -> AnyObject {
        switch kind {
        case .apnsToken:
            let block: @convention(block) (AnyObject, UIApplication, Data) -> Void = { appDelegate, application, deviceToken in
                MotiSig.shared.ingestAPNsDeviceToken(deviceToken)
                typealias Fn = @convention(c) (AnyObject, Selector, UIApplication, Data) -> Void
                unsafeBitCast(originalIMP, to: Fn.self)(appDelegate, selector, application, deviceToken)
            }
            return block as AnyObject
        case .apnsTokenFail:
            let block: @convention(block) (AnyObject, UIApplication, Error) -> Void = { appDelegate, application, error in
                Logger.shared.error("APNs registration failed: \(error.localizedDescription)")
                typealias Fn = @convention(c) (AnyObject, Selector, UIApplication, Error) -> Void
                unsafeBitCast(originalIMP, to: Fn.self)(appDelegate, selector, application, error)
            }
            return block as AnyObject
        }
    }

    private static func makeInstallOnlyBlock(kind: SwizzleKind) -> AnyObject {
        switch kind {
        case .apnsToken:
            let block: @convention(block) (AnyObject, UIApplication, Data) -> Void = { _, _, deviceToken in
                MotiSig.shared.ingestAPNsDeviceToken(deviceToken)
            }
            return block as AnyObject
        case .apnsTokenFail:
            let block: @convention(block) (AnyObject, UIApplication, Error) -> Void = { _, _, error in
                Logger.shared.error("APNs registration failed: \(error.localizedDescription)")
            }
            return block as AnyObject
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
}

/// Hosts `@objc` method implementations whose IMPs are copied onto the app delegate class.
private final class MotiSigSwizzleTarget: NSObject {
    @objc func motiSig_application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {}

    @objc func motiSig_application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {}

    @objc func motiSig_application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
    }
}

#else

enum AppDelegateSwizzler {
    static func install() {}
}

#endif
