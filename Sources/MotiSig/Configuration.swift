import Foundation

public enum LogLevel: Int, Comparable {
    case none = 0
    case error = 1
    case info = 2
    case debug = 3

    public static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public struct Configuration {
    public let sdkKey: String
    public let projectId: String
    public let baseURL: URL
    public let logLevel: LogLevel
    /// Foreground heartbeat ping interval in seconds (clamped to 1…86400; invalid uses 60).
    public let pingIntervalSeconds: Int

    // Replace with your production URL before publishing.
    static let defaultBaseURL = URL(string: "https://api.motisig.ai/client")!

    public init(
        sdkKey: String,
        projectId: String,
        baseURL: URL? = nil,
        logLevel: LogLevel = .error,
        pingIntervalSeconds: Int = 60
    ) {
        let trimmedKey = sdkKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedProject = projectId.trimmingCharacters(in: .whitespacesAndNewlines)
        precondition(!trimmedKey.isEmpty, "sdkKey must not be empty")
        precondition(!trimmedProject.isEmpty, "projectId must not be empty")
        self.sdkKey = trimmedKey
        self.projectId = trimmedProject
        self.baseURL = baseURL ?? Self.defaultBaseURL
        self.logLevel = logLevel
        self.pingIntervalSeconds = Self.normalizedPingIntervalSeconds(pingIntervalSeconds)
    }

    /// Returns a value in `1...86400`, or **60** if `value` is not positive.
    public static func normalizedPingIntervalSeconds(_ value: Int) -> Int {
        if value <= 0 { return 60 }
        return min(value, 86400)
    }
}
