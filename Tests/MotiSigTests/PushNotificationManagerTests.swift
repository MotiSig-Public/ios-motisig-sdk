import Foundation
@testable import MotiSig
import XCTest

final class PushNotificationManagerTests: XCTestCase {

    func testExtractMessageId_topLevelMessageId() {
        let userInfo: [AnyHashable: Any] = ["messageId": "msg-top"]
        XCTAssertEqual(PushNotificationManager.extractMessageId(from: userInfo), "msg-top")
    }

    func testExtractMessageId_topLevelMessage_id() {
        let userInfo: [AnyHashable: Any] = ["message_id": "msg-snake"]
        XCTAssertEqual(PushNotificationManager.extractMessageId(from: userInfo), "msg-snake")
    }

    func testExtractMessageId_apsMessageId() {
        let userInfo: [AnyHashable: Any] = ["aps": ["messageId": "msg-aps"]]
        XCTAssertEqual(PushNotificationManager.extractMessageId(from: userInfo), "msg-aps")
    }

    func testExtractMessageId_prefersTopLevelOverAps() {
        let userInfo: [AnyHashable: Any] = [
            "messageId": "msg-top",
            "aps": ["messageId": "msg-aps"],
        ]
        XCTAssertEqual(PushNotificationManager.extractMessageId(from: userInfo), "msg-top")
    }

    func testExtractMessageId_motisigNestedMessageId() {
        let userInfo: [AnyHashable: Any] = [
            "_motisig": ["messageId": "msg-nested"],
        ]
        XCTAssertEqual(PushNotificationManager.extractMessageId(from: userInfo), "msg-nested")
    }

    func testExtractMessageId_prefersTopLevelOverMotisig() {
        let userInfo: [AnyHashable: Any] = [
            "messageId": "msg-top",
            "_motisig": ["messageId": "msg-nested"],
        ]
        XCTAssertEqual(PushNotificationManager.extractMessageId(from: userInfo), "msg-top")
    }

    func testExtractMessageId_missingReturnsNil() {
        let userInfo: [AnyHashable: Any] = ["title": "Hello"]
        XCTAssertNil(PushNotificationManager.extractMessageId(from: userInfo))
    }

    func testNotificationCorrelationKey_usesMessageIdWhenPresent() {
        let userInfo: [AnyHashable: Any] = ["messageId": "msg-1"]
        XCTAssertEqual(PushNotificationManager.notificationCorrelationKey(from: userInfo), "m:msg-1")
    }

    func testNotificationCorrelationKey_stableWithoutMessageId() {
        let userInfo: [AnyHashable: Any] = [
            "aps": ["alert": ["title": "Hi", "body": "There"]],
            "foo": "bar",
        ]
        let a = PushNotificationManager.notificationCorrelationKey(from: userInfo)
        let b = PushNotificationManager.notificationCorrelationKey(from: userInfo)
        XCTAssertEqual(a, b)
        XCTAssertTrue(a.hasPrefix("h:"))
    }
}
