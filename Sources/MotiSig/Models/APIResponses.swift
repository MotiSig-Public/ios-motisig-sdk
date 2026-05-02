import Foundation

struct RegisterUserResponse: Decodable {
    let success: Bool
    let userId: String
}

struct SuccessResponse: Decodable {
    let success: Bool
}

struct TriggerEventResponse: Decodable {
    let success: Bool
    let message: String
}

struct ErrorResponseBody: Decodable {
    let error: String
}

/// Response from `GET /users/{id}`. Decodes any JSON shape under `user` (OpenAPI leaves it untyped).
struct UserResponse: Decodable {
    let user: JSONValue?

    private enum CodingKeys: String, CodingKey {
        case user
    }
}

enum JSONValue: Decodable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let single = try decoder.singleValueContainer()
        if single.decodeNil() {
            self = .null
            return
        }
        if let b = try? single.decode(Bool.self) {
            self = .bool(b)
            return
        }
        if let i = try? single.decode(Int.self) {
            self = .number(Double(i))
            return
        }
        if let d = try? single.decode(Double.self) {
            self = .number(d)
            return
        }
        if let s = try? single.decode(String.self) {
            self = .string(s)
            return
        }

        if var unkeyed = try? decoder.unkeyedContainer() {
            var arr: [JSONValue] = []
            while !unkeyed.isAtEnd {
                arr.append(try unkeyed.decode(JSONValue.self))
            }
            self = .array(arr)
            return
        }

        let keyed = try decoder.container(keyedBy: DynamicCodingKey.self)
        var obj: [String: JSONValue] = [:]
        for key in keyed.allKeys {
            obj[key.stringValue] = try keyed.decode(JSONValue.self, forKey: key)
        }
        self = .object(obj)
    }

    private struct DynamicCodingKey: CodingKey {
        var stringValue: String
        init?(stringValue: String) {
            self.stringValue = stringValue
        }
        var intValue: Int?
        init?(intValue: Int) { nil }
    }
}
