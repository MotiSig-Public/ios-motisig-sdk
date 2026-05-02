import Foundation
import XCTest

enum IntegrationTestCredentials {
    /// Values from `MOTISIG_SDK_KEY`, `MOTISIG_PROJECT_ID`, and `MOTISIG_BASE_URL` (same names as `MotiSig.initialize` reads from the environment).
    struct Values {
        let sdkKey: String
        let projectId: String
        let baseURL: URL
    }

    /// Throws `XCTSkip` when integration credentials are missing or invalid (strict: all three required).
    static func loadOrSkip() throws -> Values {
        let env = ProcessInfo.processInfo.environment
        let sdkKey = env["MOTISIG_SDK_KEY"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !sdkKey.isEmpty else {
            throw XCTSkip("Set MOTISIG_SDK_KEY to run integration tests.")
        }
        let projectId = env["MOTISIG_PROJECT_ID"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !projectId.isEmpty else {
            throw XCTSkip("Set MOTISIG_PROJECT_ID to run integration tests.")
        }
        let baseRaw = env["MOTISIG_BASE_URL"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !baseRaw.isEmpty, let baseURL = URL(string: baseRaw) else {
            throw XCTSkip("Set MOTISIG_BASE_URL to a valid URL to run integration tests.")
        }
        return Values(sdkKey: sdkKey, projectId: projectId, baseURL: baseURL)
    }
}
