import Foundation
@testable import MotiSig
import XCTest

@MainActor
final class MotiSigUserLifecycleIntegrationTests: XCTestCase {

    private var credentials: IntegrationTestCredentials.Values!

    override func setUp() async throws {
        continueAfterFailure = false
        credentials = try IntegrationTestCredentials.loadOrSkip()
        MotiSigTestBootstrap.skipPushPermissionAndRegistration = true
        XCTAssertTrue(MotiSig.initialize(sdkKey: "", projectId: "", baseURL: nil, logLevel: .debug))
        XCTAssertTrue(MotiSig.shared.isInitialized)
    }

    override func tearDown() async throws {
        MotiSig.shared.removeAllNotificationListeners()
        MotiSig.shared.logout()
        MotiSigTestBootstrap.skipPushPermissionAndRegistration = false
        credentials = nil
    }

    func testUserLifecycle_setUser_update_tags_attributes_logout_setUserAgain() async throws {
        let sdk = MotiSig.shared
        let userId = UUID().uuidString

        // --- First setUser: SDK POST /users (new user, expect 2xx) ---
        sdk.setUser(id: userId)
        let okUser = await IntegrationTestSupport.waitUntil(timeout: 15) {
            sdk.currentUserId != nil
        }
        XCTAssertTrue(okUser, "currentUserId should be set after setUser")

        let activeUserId = try XCTUnwrap(sdk.currentUserId)
        print("[lifecycle] setUser completed: requested='\(userId)' active='\(activeUserId)'")

        let profile = try await sdk.getUser()
        XCTAssertNotNil(profile, "getUser should return a profile after registration")

        // --- Diagnostic: raw GET /users/{id} (not used by setUser; confirms user row exists) ---
        try await diagnosticGetUser(userId: activeUserId)

        // --- Update user fields ---
        sdk.updateUser(
            firstName: "Integration",
            lastName: "Test",
            email: "integration+\(userId.prefix(8))@example.com"
        )
        // await IntegrationTestSupport.sleepSeconds(1)

        // --- Tags ---
        sdk.addTags(["it_tag_a", "it_tag_b", "it_tag_c"])
        // await IntegrationTestSupport.sleepSeconds(1)
        sdk.removeTags(["it_tag_b"])
        // await IntegrationTestSupport.sleepSeconds(1)

        // --- Attributes ---
        sdk.setAttributes(["it_a": 1, "it_b": "x"])
        // await IntegrationTestSupport.sleepSeconds(1)
        sdk.setAttributes(["it_c": true])
        // await IntegrationTestSupport.sleepSeconds(1)
        sdk.removeAttributes(keys: ["it_a", "it_c"])
        // await IntegrationTestSupport.sleepSeconds(1)

        // --- Logout ---
        sdk.logout()
        let okLogout = await IntegrationTestSupport.waitUntil(timeout: 5) {
            sdk.currentUserId == nil
        }
        XCTAssertTrue(okLogout, "currentUserId should be nil after logout")

        // --- Second setUser: POST /users again; existing user should yield 409 (SDK treats as success) ---
        sdk.setUser(id: activeUserId)
        let okAgain = await IntegrationTestSupport.waitUntil(timeout: 15) {
            sdk.currentUserId != nil
        }
        XCTAssertTrue(okAgain, "currentUserId should be set after second setUser")
        XCTAssertEqual(sdk.currentUserId, activeUserId)

        try await diagnosticGetUser(userId: activeUserId)
    }

    // MARK: - Diagnostic helper

    /// Performs a raw GET /users/{id} and prints the URL, status code, and response body.
    /// Fails the test with a clear message if the request returns a non-200 status.
    private func diagnosticGetUser(userId: String) async throws {
        let creds = credentials!
        let endpoint = Endpoint.getUser(userId: userId)
        let request = endpoint.urlRequest(
            baseURL: creds.baseURL,
            sdkKey: creds.sdkKey,
            projectId: creds.projectId
        )

        print("[diagnostic] GET \(request.url?.absoluteString ?? "nil")")
        print("[diagnostic] Headers: X-API-Key=\(creds.sdkKey.prefix(8))... X-Project-ID=\(creds.projectId)")

        let (data, response) = try await URLSession.shared.data(for: request)
        let httpResponse = try XCTUnwrap(response as? HTTPURLResponse)
        let bodyString = String(data: data, encoding: .utf8) ?? "<non-utf8 \(data.count) bytes>"

        print("[diagnostic] Status: \(httpResponse.statusCode)")
        print("[diagnostic] Body: \(bodyString)")

        XCTAssertEqual(
            httpResponse.statusCode, 200,
            "GET /users/\(userId) returned \(httpResponse.statusCode): \(bodyString)"
        )
    }
}
