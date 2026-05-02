import Foundation

// MARK: - Optional fields for `POST /users` (Expo `RegisterUserPayload` parity)

/// Optional registration fields passed to ``MotiSig/setUser(id:register:completion:)``.
public struct RegisterUserExtras: @unchecked Sendable {
    public var firstName: String?
    public var lastName: String?
    public var email: String?
    public var tags: [String]?
    public var customAttributes: [String: Any]?

    public init(
        firstName: String? = nil,
        lastName: String? = nil,
        email: String? = nil,
        tags: [String]? = nil,
        customAttributes: [String: Any]? = nil
    ) {
        self.firstName = firstName
        self.lastName = lastName
        self.email = email
        self.tags = tags
        self.customAttributes = customAttributes
    }
}

// MARK: - Registration body sent to POST /users

struct RegisterUserBody: Encodable {
    let id: String
    let platform: String
    var timezone: String?
    var locale: String?
    var firstName: String?
    var lastName: String?
    var email: String?
    var tags: [String]?
    var customAttributes: [String: AnyCodable]?

    init(id: String, timezone: String?, locale: String?, extras: RegisterUserExtras?) {
        self.id = id
        self.platform = "ios"
        self.timezone = timezone
        self.locale = locale
        self.firstName = extras?.firstName
        self.lastName = extras?.lastName
        self.email = extras?.email
        self.tags = extras?.tags
        self.customAttributes = extras?.customAttributes?.mapValues { AnyCodable($0) }
    }
}

// MARK: - Update body sent to PATCH /users/{id}

struct UpdateUserBody: Encodable {
    var firstName: String?
    var lastName: String?
    var email: String?
    var timezone: String?
    var locale: String?
}

// MARK: - Tags body

struct TagsBody: Encodable {
    let tags: [String]
}

// MARK: - Attributes body

struct AttributesBody: Encodable {
    let attributes: [String: AnyCodable]
}

struct AttributeKeysBody: Encodable {
    let keys: [String]
}

// MARK: - Push subscription bodies (`/users/{id}/push-subscriptions`)

struct PushSubscriptionUpsertBody: Encodable {
    let devicePlatform: String
    let pushType: String
    let token: String
    var permission: String?
    var enabled: Bool?
}

struct PushSubscriptionPatchBody: Encodable {
    let devicePlatform: String
    let pushType: String
    let token: String
    var permission: String?
    var enabled: Bool?
}

struct PushSubscriptionRemoveBody: Encodable {
    let devicePlatform: String
    let pushType: String
    let token: String
}

// MARK: - Track click body

struct TrackClickBody: Encodable {
    let userId: String
    let messageId: String
    var isForeground: Bool?
}

// MARK: - Type-erased Codable wrapper for heterogeneous dictionaries

public struct AnyCodable: Encodable {
    private let value: Any

    public init(_ value: Any) {
        self.value = value
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case let v as Bool:   try container.encode(v)
        case let v as Int:    try container.encode(v)
        case let v as Double: try container.encode(v)
        case let v as String: try container.encode(v)
        case let v as Date:   try container.encode(v.timeIntervalSince1970)
        case let v as URL:    try container.encode(v.absoluteString)
        case let v as [Any]:
            try container.encode(v.map { AnyCodable($0) })
        case let v as [String: Any]:
            try container.encode(v.mapValues { AnyCodable($0) })
        default:
            try container.encodeNil()
        }
    }
}
