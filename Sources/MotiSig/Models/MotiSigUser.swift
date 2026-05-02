import Foundation

/// User profile returned by ``MotiSig/getUser()``; mirrors the Expo SDK’s `MotiSigUser` shape.
public struct MotiSigUser: Sendable, Equatable {
    public var id: String?
    public var projectId: String?
    public var platform: String?
    public var firstName: String?
    public var lastName: String?
    public var email: String?
    public var timezone: String?
    public var locale: String?
    public var lastSessionAt: String?
    public var accountCreatedAt: String?
    public var tags: [String]?
    public var customAttributes: [String: String]?

    public init(
        id: String? = nil,
        projectId: String? = nil,
        platform: String? = nil,
        firstName: String? = nil,
        lastName: String? = nil,
        email: String? = nil,
        timezone: String? = nil,
        locale: String? = nil,
        lastSessionAt: String? = nil,
        accountCreatedAt: String? = nil,
        tags: [String]? = nil,
        customAttributes: [String: String]? = nil
    ) {
        self.id = id
        self.projectId = projectId
        self.platform = platform
        self.firstName = firstName
        self.lastName = lastName
        self.email = email
        self.timezone = timezone
        self.locale = locale
        self.lastSessionAt = lastSessionAt
        self.accountCreatedAt = accountCreatedAt
        self.tags = tags
        self.customAttributes = customAttributes
    }
}

extension MotiSigUser {
    init?(jsonValue: JSONValue) {
        if case .null = jsonValue { return nil }
        guard case .object(let dict) = jsonValue else { return nil }
        func str(_ key: String) -> String? {
            guard let v = dict[key] else { return nil }
            if case .string(let s) = v { return s }
            if case .number(let n) = v { return String(n) }
            if case .bool(let b) = v { return b ? "true" : "false" }
            return nil
        }
        func stringArray(_ key: String) -> [String]? {
            guard let v = dict[key], case .array(let arr) = v else { return nil }
            let strings = arr.compactMap { item -> String? in
                if case .string(let s) = item { return s }
                if case .number(let n) = item { return String(n) }
                return nil
            }
            return strings.isEmpty ? nil : strings
        }
        func flatAttributes(_ key: String) -> [String: String]? {
            guard let v = dict[key], case .object(let obj) = v else { return nil }
            var out: [String: String] = [:]
            for (k, val) in obj {
                switch val {
                case .string(let s): out[k] = s
                case .number(let n): out[k] = String(n)
                case .bool(let b): out[k] = b ? "true" : "false"
                default: break
                }
            }
            return out.isEmpty ? nil : out
        }
        self.init(
            id: str("id"),
            projectId: str("projectId"),
            platform: str("platform"),
            firstName: str("firstName"),
            lastName: str("lastName"),
            email: str("email"),
            timezone: str("timezone"),
            locale: str("locale"),
            lastSessionAt: str("lastSessionAt"),
            accountCreatedAt: str("accountCreatedAt"),
            tags: stringArray("tags"),
            customAttributes: flatAttributes("customAttributes")
        )
    }
}
