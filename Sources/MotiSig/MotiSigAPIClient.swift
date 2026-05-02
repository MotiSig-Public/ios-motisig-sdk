import Foundation

/// Standalone typed REST client for MotiSig (parity with the Expo `MotiSigApi` / `createMotiSigApi` escape hatch).
/// Use when you need HTTP without the ``MotiSig`` singleton (e.g. background tooling); apps typically use ``MotiSig/shared`` instead.
public final class MotiSigAPIClient: @unchecked Sendable {
    private let http: HTTPClient

    public init(
        sdkKey: String,
        projectId: String,
        baseURL: URL? = nil,
        pingIntervalSeconds: Int = 60
    ) {
        let configuration = Configuration(
            sdkKey: sdkKey,
            projectId: projectId,
            baseURL: baseURL,
            logLevel: .error,
            pingIntervalSeconds: pingIntervalSeconds
        )
        self.http = HTTPClient(configuration: configuration)
    }

    public func getUser(userId: String) async throws -> MotiSigUser? {
        try await http.getUser(userId: userId)
    }

    public func trackClick(userId: String, messageId: String, isForeground: Bool? = nil) async throws {
        let body = TrackClickBody(userId: userId, messageId: messageId, isForeground: isForeground)
        try await http.request(.trackClick, body: body)
    }

    public func ping(userId: String) async throws {
        try await http.requestPingWithNetworkRetry(userId: userId)
    }
}
