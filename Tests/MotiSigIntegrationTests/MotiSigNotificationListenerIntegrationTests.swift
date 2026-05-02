import Foundation
@testable import MotiSig
import XCTest

private final class RecordingListener: MotiSigNotificationListener {
    private(set) var receivedCount = 0

    func motiSig(didReceiveNotification notification: MotiSigNotification, inForeground: Bool) {
        receivedCount += 1
    }
}

@MainActor
final class MotiSigNotificationListenerIntegrationTests: XCTestCase {

    override func setUp() async throws {
        continueAfterFailure = false
        _ = try IntegrationTestCredentials.loadOrSkip()
        MotiSigTestBootstrap.skipPushPermissionAndRegistration = true
        XCTAssertTrue(MotiSig.initialize(sdkKey: "", projectId: "", baseURL: nil, logLevel: .debug))
        XCTAssertTrue(MotiSig.shared.isInitialized)
    }

    override func tearDown() async throws {
        MotiSig.shared.removeAllNotificationListeners()
        MotiSig.shared.logout()
        MotiSigTestBootstrap.skipPushPermissionAndRegistration = false
    }

    func testNotificationListener_receivesSimulatedNotification_thenLogout() async throws {
        let sdk = MotiSig.shared
        let userId = UUID().uuidString.lowercased()

        // setUser: register-first POST /users
        sdk.setUser(id: userId)
        let userOk = await IntegrationTestSupport.waitUntil(timeout: 15) {
            sdk.currentUserId != nil
        }
        XCTAssertTrue(userOk, "currentUserId should be set after setUser")

        let listener = RecordingListener()
        _ = sdk.addNotificationListener(listener)

        let payload = MotiSigNotification(
            messageId: "it-msg-\(UUID().uuidString)",
            title: "Integration",
            body: "Simulated push",
            userInfo: ["messageId": "it-msg-placeholder"]
        )
        sdk.deliverNotificationForTesting(payload, inForeground: true)

        let delivered = await IntegrationTestSupport.waitUntil(timeout: 5) {
            listener.receivedCount > 0
        }
        XCTAssertTrue(delivered, "Listener should receive the simulated notification")
        XCTAssertEqual(listener.receivedCount, 1)

        sdk.logout()
        let loggedOut = await IntegrationTestSupport.waitUntil(timeout: 5) {
            sdk.currentUserId == nil
        }
        XCTAssertTrue(loggedOut, "currentUserId should be nil after logout")
    }
}
