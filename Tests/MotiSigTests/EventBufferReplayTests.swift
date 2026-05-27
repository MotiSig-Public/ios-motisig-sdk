import Foundation
@testable import MotiSig
import XCTest

private final class RecordingListener: MotiSigNotificationListener {
    private(set) var notifications: [(MotiSigNotification, Bool)] = []

    func motiSig(didReceiveNotification notification: MotiSigNotification, inForeground: Bool) {
        notifications.append((notification, inForeground))
    }
}

@MainActor
final class EventBufferReplayTests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
        MotiSigTestBootstrap.skipPushPermissionAndRegistration = true
        _ = MotiSig.initialize(sdkKey: "test-key", projectId: "test-project", logLevel: .error)
    }

    override func tearDown() {
        MotiSig.shared.removeAllNotificationListeners()
        MotiSig.shared.reset()
        MotiSigTestBootstrap.skipPushPermissionAndRegistration = false
    }

    /// Mirrors cold start: notification arrives before the app registers a listener in `.onAppear`.
    func testAddNotificationListener_replaysBufferedColdStartNotification() {
        let sdk = MotiSig.shared
        let messageId = "cold-start-\(UUID().uuidString)"
        let payload = MotiSigNotification(
            messageId: messageId,
            title: "Cold Start",
            body: "Opened from push",
            userInfo: ["messageId": messageId]
        )

        sdk.deliverNotificationForTesting(payload, inForeground: false)

        let listener = RecordingListener()
        _ = sdk.addNotificationListener(listener)

        let expectation = expectation(description: "buffered notification replayed")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1)

        XCTAssertEqual(listener.notifications.count, 1)
        XCTAssertEqual(listener.notifications.first?.0.messageId, messageId)
        XCTAssertEqual(listener.notifications.first?.1, false)
    }
}
