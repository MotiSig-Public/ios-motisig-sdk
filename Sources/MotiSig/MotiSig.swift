import Foundation
import UserNotifications
#if canImport(UIKit) && !os(watchOS)
import UIKit
#endif

/// MotiSig SDK entry point. User-scoped HTTP mutations (`setUser`, tags, attributes, `updateUser`, `ping`, `triggerEvent`, push subscription upsert/patch/remove) run on an internal FIFO queue so effects match call order; each item uses user id (and token where applicable) captured at enqueue time, so work is not dropped if ``logout()`` clears storage before the request runs.
///
/// For HTTP-only tooling without singleton state, use ``MotiSigAPIClient`` with the same base URL and headers (`X-API-Key`, `X-Project-ID`) as the Expo `MotiSigHttpClient`.
public final class MotiSig {

    // MARK: - Singleton

    public private(set) static var shared: MotiSig = MotiSig()

    // MARK: - Public properties

    public var isInitialized: Bool { configuration != nil }

    public var currentUserId: String? {
        syncQueue.sync { storage.userId }
    }

    /// Foreground heartbeat interval from the active configuration (default **60**).
    internal var pingHeartbeatIntervalSeconds: Int {
        syncQueue.sync { configuration?.pingIntervalSeconds ?? 60 }
    }

    // MARK: - Private state

    private var configuration: Configuration?
    private var httpClient: HTTPClient?
    private let pushManager = PushNotificationManager()
    private let storage = Storage()
    private let syncQueue = DispatchQueue(label: "com.motisig.sdk.sync")
    private let mutationQueue = FIFOAsyncMutationQueue()
    private let eventBuffer = EventBuffer()
    private var listenerEntries: [UUID: ListenerBox] = [:]
    private var nextRegistrationSequence: UInt64 = 0
    private let listenerQueue = DispatchQueue(label: "com.motisig.sdk.listeners")

    /// Last `permission` / `enabled` successfully sent on push-subscription requests (used to avoid redundant PATCHes).
    private var lastSyncedPushPermission: String?
    private var lastSyncedPushEnabled: Bool?

    private var skipPermissionRequestStored = false
    private var skipNotificationListenersStored = false

    /// Fires when the APNs device token changes; arguments are `(newToken, previousToken)` (Expo `token_refresh` parity).
    public var onApnsTokenChange: ((String, String?) -> Void)?

    private let foregroundRequestLock = NSLock()
    private var foregroundRequestOrder: [String] = []
    private var foregroundRequestSet = Set<String>()
    private static let maxForegroundRequestIds = 10

    private init() {}

    // MARK: - Initialization

    /// Configure the SDK. Call once at app launch. Installs push permission flow, APNs swizzling, and notification interception.
    ///
    /// - Parameters:
    ///   - sdkKey: Project SDK key. If empty, reads `MOTISIG_SDK_KEY` from `ProcessInfo.processInfo.environment`.
    ///   - projectId: Project identifier sent as `X-Project-ID`. If empty, reads `MOTISIG_PROJECT_ID` from the environment.
    ///   - baseURL: API base URL (typically `…/client`). If `nil`, reads `MOTISIG_BASE_URL` from the environment; if unset or invalid, uses `Configuration.defaultBaseURL`.
    ///   - logLevel: Minimum log level for the SDK logger.
    ///   - pingIntervalSeconds: Foreground heartbeat ping interval in seconds (default **60**; invalid or non-positive values use **60**, max **86400**).
    ///   - skipPermissionRequest: When `true`, does not show the system notification permission prompt; still registers for remote notifications (Expo parity).
    ///   - skipNotificationListeners: When `true`, does not install the `UNUserNotificationCenter` delegate proxy (no MotiSig notification callbacks or automatic click tracking from pushes).
    /// - Returns: `false` if `sdkKey` or `projectId` could not be resolved; otherwise `true`. Subsequent calls return `true` immediately if already initialized.
    @discardableResult
    public static func initialize(
        sdkKey: String = "",
        projectId: String = "",
        baseURL: URL? = nil,
        logLevel: LogLevel = .error,
        pingIntervalSeconds: Int = 60,
        skipPermissionRequest: Bool = false,
        skipNotificationListeners: Bool = false
    ) -> Bool {
        let already = shared.syncQueue.sync { shared.configuration != nil }
        if already {
            Logger.shared.debug("MotiSig.initialize called again; already initialized.")
            return true
        }

        let env = ProcessInfo.processInfo.environment

        let resolvedSdkKey: String = {
            let trimmed = sdkKey.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
            let fromEnv = env["MOTISIG_SDK_KEY"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return fromEnv
        }()

        guard !resolvedSdkKey.isEmpty else {
            Logger.shared.error("SDK key must not be empty (pass `sdkKey` or set MOTISIG_SDK_KEY).")
            return false
        }

        let resolvedProjectId: String = {
            let trimmed = projectId.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
            return env["MOTISIG_PROJECT_ID"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }()

        guard !resolvedProjectId.isEmpty else {
            Logger.shared.error("projectId must not be empty (pass `projectId` or set MOTISIG_PROJECT_ID).")
            return false
        }

        let resolvedBaseURL: URL? = {
            if let baseURL { return baseURL }
            let raw = env["MOTISIG_BASE_URL"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !raw.isEmpty else { return nil }
            return URL(string: raw)
        }()

        let config = Configuration(
            sdkKey: resolvedSdkKey,
            projectId: resolvedProjectId,
            baseURL: resolvedBaseURL,
            logLevel: logLevel,
            pingIntervalSeconds: pingIntervalSeconds
        )
        Logger.shared.level = logLevel

        shared.syncQueue.sync {
            shared.skipPermissionRequestStored = skipPermissionRequest
            shared.skipNotificationListenersStored = skipNotificationListeners
            shared.configuration = config
            shared.httpClient = HTTPClient(configuration: config)
        }

        if !MotiSigTestBootstrap.skipPushPermissionAndRegistration {
            DispatchQueue.main.async {
                if !shared.syncQueue.sync(execute: { shared.skipNotificationListenersStored }) {
                    NotificationCenterProxy.shared.install()
                }
                AppDelegateSwizzler.install()
            }
        }

        if !shared.syncQueue.sync(execute: { shared.skipNotificationListenersStored }) {
            shared.pushManager.startPermissionMonitoring { status in
                MotiSig.shared.syncPushSubscriptionPermission(for: status)
            }
        }

        if !MotiSigTestBootstrap.skipPushPermissionAndRegistration {
            if shared.syncQueue.sync(execute: { shared.skipPermissionRequestStored }) {
                Task {
                    await shared.pushManager.registerForRemoteNotificationsOnly()
                }
            } else {
                Task {
                    do {
                        _ = try await shared.pushManager.requestPermissionThenRegisterForRemote()
                    } catch {
                        Logger.shared.error("Push permission request failed: \(error.localizedDescription)")
                    }
                }
            }
            shared.autoRegisterTokenIfNeeded()
        }

        #if canImport(UIKit) && !os(watchOS)
        ForegroundPingMonitor.installIfNeeded()
        #endif

        Logger.shared.info("MotiSig initialized (base: \(config.baseURL.absoluteString))")
        return true
    }

    /// Clears local SDK state without calling server logout (Expo `reset` parity). Call before re-``initialize`` with new credentials.
    public func reset() {
        removeAllNotificationListeners()
        #if canImport(UIKit) && !os(watchOS)
        ForegroundPingMonitor.uninstall()
        #endif
        foregroundRequestLock.lock()
        foregroundRequestOrder.removeAll(keepingCapacity: false)
        foregroundRequestSet.removeAll(keepingCapacity: false)
        foregroundRequestLock.unlock()
        syncQueue.sync {
            storage.clear()
            lastSyncedPushPermission = nil
            lastSyncedPushEnabled = nil
            configuration = nil
            httpClient = nil
            skipPermissionRequestStored = false
            skipNotificationListenersStored = false
        }
        onApnsTokenChange = nil
        Logger.shared.info("MotiSig reset (local only; no server logout)")
    }

    // MARK: - User management

    /// Ensures the user exists on the server by registering (`POST /users`). If the server returns **409**, the user already exists and no extra request is needed. Then registers the current APNs token when available.
    public func setUser(
        id: String,
        register: RegisterUserExtras? = nil,
        completion: ((Result<Void, Error>) -> Void)? = nil
    ) {
        mutationQueue.enqueue { [weak self] in
            guard let self else {
                Logger.shared.error("setUser aborted: MotiSig instance was deallocated.")
                Self.invokeCompletion(completion, .failure(MotiSigError.notInitialized))
                return
            }
            guard let client = self.client else {
                Logger.shared.error("setUser aborted: SDK not initialized (no HTTP client).")
                Self.invokeCompletion(completion, .failure(MotiSigError.notInitialized))
                return
            }
            Logger.shared.info("setUser started for id: \(id)")
            do {
                let body = RegisterUserBody(
                    id: id,
                    timezone: TimeZone.current.identifier,
                    locale: Locale.current.identifier,
                    extras: register
                )
                do {
                    let response = try await client.request(
                        .registerUser,
                        body: body,
                        responseType: RegisterUserResponse.self
                    )
                    Logger.shared.info("User registered: \(response.userId)")
                } catch let err as MotiSigError {
                    if case .apiError(let code, _) = err, code == 409 {
                        Logger.shared.debug("User already exists (register conflict): \(id)")
                    } else {
                        throw err
                    }
                }

                self.syncQueue.sync { self.storage.userId = id }
                Logger.shared.info("setUser completed; user id persisted: \(id)")
                self.autoRegisterTokenIfNeeded()
                Self.invokeCompletion(completion, .success(()))
            } catch {
                if let err = error as? MotiSigError {
                    Logger.shared.error("setUser failed: \(err.errorDescription ?? String(describing: err))")
                } else {
                    Logger.shared.error("setUser failed: \(error.localizedDescription)")
                }
                Self.invokeCompletion(completion, .failure(error))
            }
        }
    }

    /// Fetches the current user from the server (`GET /users/{id}`). Returns `nil` when the user is not found (**404**).
    public func getUser() async throws -> MotiSigUser? {
        guard let client = client else { throw MotiSigError.notInitialized }
        let userId = syncQueue.sync { storage.userId }
        guard let userId else { throw MotiSigError.userNotSet }
        return try await client.getUser(userId: userId)
    }

    /// Records a notification open or in-app action (`POST /track/click`).
    public func trackClick(
        messageId: String,
        isForeground: Bool? = nil,
        completion: ((Result<Void, Error>) -> Void)? = nil
    ) {
        let userIdForTask = syncQueue.sync { storage.userId }
        guard let userIdForTask else {
            Self.invokeCompletion(completion, .failure(MotiSigError.userNotSet))
            return
        }
        mutationQueue.enqueue { [weak self] in
            guard let self, let client = self.client else {
                Self.invokeCompletion(completion, .failure(MotiSigError.notInitialized))
                return
            }
            let body = TrackClickBody(userId: userIdForTask, messageId: messageId, isForeground: isForeground)
            do {
                try await client.request(.trackClick, body: body)
                Logger.shared.debug("trackClick sent for message \(messageId)")
                Self.invokeCompletion(completion, .success(()))
            } catch {
                Logger.shared.error("trackClick failed: \(error)")
                Self.invokeCompletion(completion, .failure(error))
            }
        }
    }

    /// Update mutable user fields.
    public func updateUser(
        firstName: String? = nil,
        lastName: String? = nil,
        email: String? = nil,
        completion: ((Result<Void, Error>) -> Void)? = nil
    ) {
        let body = UpdateUserBody(
            firstName: firstName,
            lastName: lastName,
            email: email,
            timezone: TimeZone.current.identifier,
            locale: Locale.current.identifier
        )

        let userIdForTask = syncQueue.sync { storage.userId }
        guard let userIdForTask else {
            Self.invokeCompletion(completion, .failure(MotiSigError.userNotSet))
            return
        }

        mutationQueue.enqueue { [weak self] in
            guard let self, let client = self.client else {
                Self.invokeCompletion(completion, .failure(MotiSigError.notInitialized))
                return
            }
            do {
                try await client.request(.updateUser(userId: userIdForTask), body: body)
                Logger.shared.info("User updated")
                Self.invokeCompletion(completion, .success(()))
            } catch {
                Logger.shared.error("Failed to update user: \(error)")
                Self.invokeCompletion(completion, .failure(error))
            }
        }
    }

    /// Remove the current user and clear stored state.
    ///
    /// Queued mutations may still complete afterward using user ids captured at enqueue time; push-subscription remove uses id and token captured here before storage is cleared.
    public func logout() {
        let removePushSnapshot: (userId: String, token: String)? = syncQueue.sync {
            guard let token = storage.apnsToken, let userId = storage.userId else { return nil }
            return (userId, token)
        }
        if let removePushSnapshot {
            let userId = removePushSnapshot.userId
            let token = removePushSnapshot.token
            mutationQueue.enqueue { [weak self] in
                guard let client = self?.client else { return }
                let body = PushSubscriptionRemoveBody(devicePlatform: "ios", pushType: "apns", token: token)
                try? await client.request(.removePushSubscription(userId: userId), body: body)
            }
        }
        listenerQueue.sync {
            self.listenerEntries.removeAll(keepingCapacity: false)
            self.eventBuffer.clear()
        }
        syncQueue.sync {
            storage.clear()
            lastSyncedPushPermission = nil
            lastSyncedPushEnabled = nil
        }
        Logger.shared.info("User logged out")
    }

    /// Customer preference for server-side push for this device (independent of OS notification permission).
    public var isNotificationEnabled: Bool {
        syncQueue.sync { storage.pushSubscriptionCustomerEnabled }
    }

    /// Customer-controlled flag for whether this device’s push subscription is enabled on the server (independent of OS permission).
    public func setNotificationEnabled(
        _ enabled: Bool,
        completion: ((Result<Void, Error>) -> Void)? = nil
    ) {
        syncQueue.sync { storage.pushSubscriptionCustomerEnabled = enabled }
        let userId = syncQueue.sync { storage.userId }
        let token = syncQueue.sync { storage.apnsToken }
        guard let userId, let token else {
            Self.invokeCompletion(completion, .failure(MotiSigError.userNotSet))
            return
        }

        mutationQueue.enqueue { [weak self] in
            guard let self, let client = self.client else {
                Self.invokeCompletion(completion, .failure(MotiSigError.notInitialized))
                return
            }
            let authStatus = await self.pushManager.currentAuthorizationStatus()
            let permStr = Self.apiPermissionString(for: authStatus)
            let enabledNow = self.syncQueue.sync { self.storage.pushSubscriptionCustomerEnabled }
            let body = PushSubscriptionPatchBody(
                devicePlatform: "ios",
                pushType: "apns",
                token: token,
                permission: permStr,
                enabled: enabledNow
            )
            do {
                try await client.request(.patchPushSubscription(userId: userId), body: body)
                self.syncQueue.sync {
                    self.lastSyncedPushPermission = permStr
                    self.lastSyncedPushEnabled = enabledNow
                }
                Logger.shared.info("Push subscription enabled flag updated: \(enabledNow)")
                Self.invokeCompletion(completion, .success(()))
            } catch {
                Logger.shared.error("Failed to patch push subscription enabled: \(error)")
                Self.invokeCompletion(completion, .failure(error))
            }
        }
    }

    // MARK: - Notification listeners

    /// Registers a weak listener for push notification events.
    /// - Parameters:
    ///   - listener: Object receiving callbacks; retained weakly by the SDK.
    ///   - order: Sort priority for delivery among listeners. `nil` behaves like `0`; same order uses registration FIFO (lower `order` values are notified first).
    /// - Returns: A subscription; call ``MotiSigNotificationSubscription/remove()`` to unregister.
    @discardableResult
    public func addNotificationListener(
        _ listener: MotiSigNotificationListener,
        order: Int? = nil
    ) -> MotiSigNotificationSubscription {
        let subscriptionId = UUID()
        let sortOrder = order ?? 0

        let pendingReplay: [(MotiSigNotification, Bool)] = listenerQueue.sync {
            self.nextRegistrationSequence += 1
            let seq = self.nextRegistrationSequence
            self.listenerEntries[subscriptionId] = ListenerBox(
                listener: listener,
                sortOrder: sortOrder,
                registrationSequence: seq
            )
            return self.eventBuffer.drain()
        }

        if !pendingReplay.isEmpty {
            DispatchQueue.main.async {
                for (notification, inForeground) in pendingReplay {
                    listener.motiSig(didReceiveNotification: notification, inForeground: inForeground)
                }
            }
        }

        return MotiSigNotificationSubscription(motiSig: self, subscriptionId: subscriptionId)
    }

    /// Removes all notification listeners and clears any buffered events.
    public func removeAllNotificationListeners() {
        listenerQueue.sync {
            self.listenerEntries.removeAll(keepingCapacity: false)
            self.eventBuffer.clear()
        }
    }

    /// Returns notifications still present in the system Notification Center (`UNUserNotificationCenter.getDeliveredNotifications`).
    ///
    /// This mirrors the OS “delivered” list, not strictly “only while the app was inactive.” Entries can overlap with
    /// ``MotiSigNotificationListener`` callbacks until the user dismisses them from Notification Center. Merge using
    /// ``MotiSigNotification/requestIdentifier`` (and/or ``MotiSigNotification/messageId``) to avoid duplicate UI rows.
    ///
    /// On watchOS this returns an empty array.
    public func fetchDeliveredNotifications() async -> [MotiSigDeliveredNotification] {
        #if os(watchOS)
        return []
        #else
        await withCheckedContinuation { continuation in
            UNUserNotificationCenter.current().getDeliveredNotifications { notifications in
                let mapped = notifications.map { MotiSigDeliveredNotification(notification: $0) }
                continuation.resume(returning: mapped)
            }
        }
        #endif
    }

    func removeNotificationSubscription(id: UUID) {
        listenerQueue.sync {
            _ = self.listenerEntries.removeValue(forKey: id)
        }
    }

    // MARK: - Tags

    public func addTags(_ tags: [String], completion: ((Result<Void, Error>) -> Void)? = nil) {
        let body = TagsBody(tags: tags)
        let userIdForTask = syncQueue.sync { storage.userId }
        guard let userIdForTask else {
            Self.invokeCompletion(completion, .failure(MotiSigError.userNotSet))
            return
        }

        mutationQueue.enqueue { [weak self] in
            guard let self, let client = self.client else {
                Self.invokeCompletion(completion, .failure(MotiSigError.notInitialized))
                return
            }
            do {
                try await client.request(.addTags(userId: userIdForTask), body: body)
                Logger.shared.debug("Tags added: \(tags)")
                Self.invokeCompletion(completion, .success(()))
            } catch {
                Logger.shared.error("Failed to add tags: \(error)")
                Self.invokeCompletion(completion, .failure(error))
            }
        }
    }

    public func removeTags(_ tags: [String], completion: ((Result<Void, Error>) -> Void)? = nil) {
        let body = TagsBody(tags: tags)
        let userIdForTask = syncQueue.sync { storage.userId }
        guard let userIdForTask else {
            Self.invokeCompletion(completion, .failure(MotiSigError.userNotSet))
            return
        }

        mutationQueue.enqueue { [weak self] in
            guard let self, let client = self.client else {
                Self.invokeCompletion(completion, .failure(MotiSigError.notInitialized))
                return
            }
            do {
                try await client.request(.removeTags(userId: userIdForTask), body: body)
                Logger.shared.debug("Tags removed: \(tags)")
                Self.invokeCompletion(completion, .success(()))
            } catch {
                Logger.shared.error("Failed to remove tags: \(error)")
                Self.invokeCompletion(completion, .failure(error))
            }
        }
    }

    // MARK: - Attributes

    public func setAttributes(_ attributes: [String: Any], completion: ((Result<Void, Error>) -> Void)? = nil) {
        let body = AttributesBody(attributes: attributes.mapValues { AnyCodable($0) })
        let userIdForTask = syncQueue.sync { storage.userId }
        guard let userIdForTask else {
            Self.invokeCompletion(completion, .failure(MotiSigError.userNotSet))
            return
        }

        mutationQueue.enqueue { [weak self] in
            guard let self, let client = self.client else {
                Self.invokeCompletion(completion, .failure(MotiSigError.notInitialized))
                return
            }
            do {
                try await client.request(.setAttributes(userId: userIdForTask), body: body)
                Logger.shared.debug("Attributes set")
                Self.invokeCompletion(completion, .success(()))
            } catch {
                Logger.shared.error("Failed to set attributes: \(error)")
                Self.invokeCompletion(completion, .failure(error))
            }
        }
    }

    /// Expo `addOrUpdateAttributes` naming; same as ``setAttributes(_:completion:)``.
    public func addOrUpdateAttributes(_ attributes: [String: Any], completion: ((Result<Void, Error>) -> Void)? = nil) {
        setAttributes(attributes, completion: completion)
    }

    public func removeAttributes(keys: [String], completion: ((Result<Void, Error>) -> Void)? = nil) {
        let body = AttributeKeysBody(keys: keys)
        let userIdForTask = syncQueue.sync { storage.userId }
        guard let userIdForTask else {
            Self.invokeCompletion(completion, .failure(MotiSigError.userNotSet))
            return
        }

        mutationQueue.enqueue { [weak self] in
            guard let self, let client = self.client else {
                Self.invokeCompletion(completion, .failure(MotiSigError.notInitialized))
                return
            }
            do {
                try await client.request(.removeAttributes(userId: userIdForTask), body: body)
                Logger.shared.debug("Attributes removed: \(keys)")
                Self.invokeCompletion(completion, .success(()))
            } catch {
                Logger.shared.error("Failed to remove attributes: \(error)")
                Self.invokeCompletion(completion, .failure(error))
            }
        }
    }

    // MARK: - Ping (heartbeat)

    public func ping(completion: ((Result<Void, Error>) -> Void)? = nil) {
        let userIdForTask = syncQueue.sync { storage.userId }
        guard let userIdForTask else {
            Self.invokeCompletion(completion, .failure(MotiSigError.userNotSet))
            return
        }

        mutationQueue.enqueue { [weak self] in
            guard let self, let client = self.client else {
                Self.invokeCompletion(completion, .failure(MotiSigError.notInitialized))
                return
            }
            do {
                try await client.requestPingWithNetworkRetry(userId: userIdForTask)
                Logger.shared.debug("Ping sent")
                Self.invokeCompletion(completion, .success(()))
            } catch {
                Logger.shared.error("Ping failed: \(error)")
                Self.invokeCompletion(completion, .failure(error))
            }
        }
    }

    // MARK: - Events

    /// Sends a named analytics/automation event for the current user (`POST /events`).
    /// - Parameters:
    ///   - eventName: Server-defined event name.
    ///   - data: Optional JSON-serializable payload; omitted from the request when `nil`.
    ///   - completion: Called on the Swift concurrency cooperative thread pool with the server `message` on success.
    public func triggerEvent(
        eventName: String,
        data: [String: Any]? = nil,
        completion: ((Result<String, Error>) -> Void)? = nil
    ) {
        let userIdForTask = syncQueue.sync { storage.userId }
        guard let userIdForTask else {
            completion?(.failure(MotiSigError.userNotSet))
            return
        }

        let eventDataSnapshot = data.map { $0.mapValues { AnyCodable($0) } }

        mutationQueue.enqueue { [weak self] in
            guard let self else {
                completion?(.failure(MotiSigError.notInitialized))
                return
            }
            guard let client = self.client else {
                completion?(.failure(MotiSigError.notInitialized))
                return
            }

            let body = TriggerEventBody(
                userId: userIdForTask,
                eventName: eventName,
                eventData: eventDataSnapshot
            )

            do {
                let response = try await client.request(
                    .triggerEvent,
                    body: body,
                    responseType: TriggerEventResponse.self
                )
                Logger.shared.debug("Trigger event: \(response.message)")
                completion?(.success(response.message))
            } catch {
                Logger.shared.error("Trigger event failed: \(error)")
                completion?(.failure(error))
            }
        }
    }

    // MARK: - Internal (push + notification plumbing)

    func ingestAPNsDeviceToken(_ deviceToken: Data) {
        let token = PushNotificationManager.tokenString(from: deviceToken)
        Logger.shared.info("APNs token received: \(token.prefix(8))...")

        let (previousToken, didChange): (String?, Bool) = syncQueue.sync {
            let old = storage.apnsToken
            storage.apnsToken = token
            let changed = (old != token)
            return (old, changed)
        }

        if didChange, let handler = onApnsTokenChange {
            DispatchQueue.main.async {
                handler(token, previousToken)
            }
        }

        guard let userId = currentUserId else {
            Logger.shared.debug("Token stored; will register when setUser completes.")
            return
        }
        registerOrUpdatePushSubscription(token: token, previousToken: previousToken, userId: userId)
    }

    /// Foreground presentation (`willPresent`); respects `suppressForeground` (Expo parity).
    func deliverWillPresent(notification: UNNotification) {
        guard !syncQueue.sync(execute: { skipNotificationListenersStored }) else { return }
        let userInfo = notification.request.content.userInfo
        if PushNotificationManager.shouldSuppressForeground(from: userInfo) {
            return
        }
        let requestId = notification.request.identifier
        recordForegroundRequestIdentifier(requestId)
        let event = PushNotificationManager.motiSigNotification(from: notification, wasForeground: false)
        trackClickIfPossible(userInfo: userInfo, isForeground: true)
        dispatchToListenersOrBuffer(event, inForeground: true)
    }

    /// User opened a notification (`didReceive`).
    func deliverDidOpen(response: UNNotificationResponse) {
        guard !syncQueue.sync(execute: { skipNotificationListenersStored }) else { return }
        let notification = response.notification
        let userInfo = notification.request.content.userInfo
        let requestId = notification.request.identifier
        let wasFg = takeWasForeground(forRequestIdentifier: requestId)
        let event = PushNotificationManager.motiSigNotification(from: notification, wasForeground: wasFg)
        trackClickIfPossible(userInfo: userInfo, isForeground: wasFg)
        #if canImport(UIKit) && !os(watchOS)
        let inForeground = UIApplication.shared.applicationState == .active
        #else
        let inForeground = false
        #endif
        dispatchToListenersOrBuffer(event, inForeground: inForeground)
    }

    private func recordForegroundRequestIdentifier(_ requestIdentifier: String) {
        guard !requestIdentifier.isEmpty else { return }
        foregroundRequestLock.lock()
        defer { foregroundRequestLock.unlock() }
        foregroundRequestOrder.append(requestIdentifier)
        foregroundRequestSet.insert(requestIdentifier)
        while foregroundRequestOrder.count > Self.maxForegroundRequestIds {
            let removed = foregroundRequestOrder.removeFirst()
            foregroundRequestSet.remove(removed)
        }
    }

    private func takeWasForeground(forRequestIdentifier requestIdentifier: String) -> Bool {
        guard !requestIdentifier.isEmpty else { return false }
        foregroundRequestLock.lock()
        defer { foregroundRequestLock.unlock() }
        guard foregroundRequestSet.contains(requestIdentifier) else { return false }
        foregroundRequestSet.remove(requestIdentifier)
        if let idx = foregroundRequestOrder.firstIndex(of: requestIdentifier) {
            foregroundRequestOrder.remove(at: idx)
        }
        return true
    }

    /// Delivers a notification to registered listeners (and the event buffer if none). For integration tests only.
    internal func deliverNotificationForTesting(_ notification: MotiSigNotification, inForeground: Bool) {
        dispatchToListenersOrBuffer(notification, inForeground: inForeground)
    }

    private func syncPushSubscriptionPermission(for status: UNAuthorizationStatus) {
        let permStr = Self.apiPermissionString(for: status)
        let (userId, token, shouldPatch): (String?, String?, Bool) = syncQueue.sync {
            guard let u = storage.userId, let t = storage.apnsToken else { return (nil, nil, false) }
            if lastSyncedPushPermission == permStr { return (u, t, false) }
            if lastSyncedPushPermission == nil { return (u, t, false) }
            return (u, t, true)
        }
        guard shouldPatch, let userId, let token else { return }

        mutationQueue.enqueue { [weak self] in
            guard let self, let client = self.client else { return }
            let enabled = self.syncQueue.sync { self.storage.pushSubscriptionCustomerEnabled }
            let body = PushSubscriptionPatchBody(
                devicePlatform: "ios",
                pushType: "apns",
                token: token,
                permission: permStr,
                enabled: enabled
            )
            do {
                try await client.request(.patchPushSubscription(userId: userId), body: body)
                self.syncQueue.sync {
                    self.lastSyncedPushPermission = permStr
                    self.lastSyncedPushEnabled = enabled
                }
                Logger.shared.debug("Push subscription permission synced: \(permStr)")
            } catch {
                Logger.shared.error("Failed to patch push subscription permission: \(error)")
            }
        }
    }

    private static func apiPermissionString(for status: UNAuthorizationStatus) -> String {
        switch status {
        case .authorized, .provisional, .ephemeral:
            return "granted"
        case .denied:
            return "declined"
        case .notDetermined:
            return "unknown"
        @unknown default:
            return "unknown"
        }
    }

    // MARK: - Private helpers

    private var client: HTTPClient? {
        syncQueue.sync {
            guard let c = httpClient else {
                Logger.shared.error("MotiSig is not initialized.")
                return nil
            }
            return c
        }
    }

    private func registerOrUpdatePushSubscription(token: String, previousToken: String?, userId: String) {
        mutationQueue.enqueue { [weak self] in
            guard let self, let client = self.client else { return }
            if let prev = previousToken, prev != token {
                let removeBody = PushSubscriptionRemoveBody(devicePlatform: "ios", pushType: "apns", token: prev)
                do {
                    try await client.request(.removePushSubscription(userId: userId), body: removeBody)
                } catch {
                    Logger.shared.debug("Remove old push subscription (best effort): \(error)")
                }
            }
            let authStatus = await self.pushManager.currentAuthorizationStatus()
            let permStr = Self.apiPermissionString(for: authStatus)
            let enabled = self.syncQueue.sync { self.storage.pushSubscriptionCustomerEnabled }
            let upsert = PushSubscriptionUpsertBody(
                devicePlatform: "ios",
                pushType: "apns",
                token: token,
                permission: permStr,
                enabled: enabled
            )
            do {
                try await client.request(.upsertPushSubscription(userId: userId), body: upsert)
                Logger.shared.info("Push subscription upserted for user \(userId)")
                self.syncQueue.sync {
                    self.lastSyncedPushPermission = permStr
                    self.lastSyncedPushEnabled = enabled
                }
            } catch {
                Logger.shared.error("Failed to upsert push subscription: \(error)")
            }
        }
    }

    private func autoRegisterTokenIfNeeded() {
        guard let token = syncQueue.sync(execute: { storage.apnsToken }),
              let userId = currentUserId else { return }
        registerOrUpdatePushSubscription(token: token, previousToken: nil, userId: userId)
    }

    private func trackClickIfPossible(userInfo: [AnyHashable: Any], isForeground: Bool) {
        guard let messageId = PushNotificationManager.extractMessageId(from: userInfo) else {
            Logger.shared.debug("No messageId in payload; skipping click tracking.")
            return
        }
        guard let userId = currentUserId else {
            Logger.shared.debug("No user set; skipping click tracking.")
            return
        }

        let body = TrackClickBody(userId: userId, messageId: messageId, isForeground: isForeground)
        Task { [weak self] in
            guard let client = self?.client else { return }
            do {
                try await client.request(.trackClick, body: body)
                Logger.shared.debug("Click tracked for message \(messageId)")
            } catch {
                Logger.shared.error("Failed to track click: \(error)")
            }
        }
    }

    private func dispatchToListenersOrBuffer(_ notification: MotiSigNotification, inForeground: Bool) {
        listenerQueue.async { [weak self] in
            guard let self else { return }

            let snapshot = self.listenerEntries
            var deadIds: [UUID] = []
            var pairs: [(MotiSigNotificationListener, Int, UInt64)] = []
            for (id, box) in snapshot {
                guard let listener = box.listener else {
                    deadIds.append(id)
                    continue
                }
                pairs.append((listener, box.sortOrder, box.registrationSequence))
            }
            for id in deadIds {
                self.listenerEntries.removeValue(forKey: id)
            }

            if pairs.isEmpty {
                self.eventBuffer.enqueue(notification, inForeground: inForeground)
                return
            }

            pairs.sort { a, b in
                if a.1 != b.1 { return a.1 < b.1 }
                return a.2 < b.2
            }

            let listeners = pairs.map { $0.0 }
            DispatchQueue.main.async {
                for listener in listeners {
                    listener.motiSig(didReceiveNotification: notification, inForeground: inForeground)
                }
            }
        }
    }

    private static func invokeCompletion(_ completion: ((Result<Void, Error>) -> Void)?, _ result: Result<Void, Error>) {
        guard let completion else { return }
        DispatchQueue.main.async {
            completion(result)
        }
    }
}

// MARK: - Listener registry

private final class ListenerBox {
    weak var listener: MotiSigNotificationListener?
    let sortOrder: Int
    let registrationSequence: UInt64

    init(listener: MotiSigNotificationListener, sortOrder: Int, registrationSequence: UInt64) {
        self.listener = listener
        self.sortOrder = sortOrder
        self.registrationSequence = registrationSequence
    }
}
