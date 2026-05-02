import Foundation

enum IntegrationTestSupport {
    static func waitUntil(
        timeout: TimeInterval,
        pollInterval: UInt64 = 50_000_000,
        condition: @escaping () -> Bool
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(nanoseconds: pollInterval)
        }
        return false
    }

    static func sleepSeconds(_ seconds: TimeInterval) async {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }
}
