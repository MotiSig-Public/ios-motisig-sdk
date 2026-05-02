import Foundation

enum HTTPMethod: String {
    case GET, POST, PATCH, DELETE
}

/// Percent-encodes a single path segment (Expo uses `encodeURIComponent` for user ids).
private func motisigPathEncode(_ segment: String) -> String {
    let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
    return segment.addingPercentEncoding(withAllowedCharacters: allowed) ?? segment
}

enum Endpoint {
    case registerUser
    case getUser(userId: String)
    case updateUser(userId: String)
    case addTags(userId: String)
    case removeTags(userId: String)
    case setAttributes(userId: String)
    case removeAttributes(userId: String)
    case upsertPushSubscription(userId: String)
    case patchPushSubscription(userId: String)
    case removePushSubscription(userId: String)
    case ping(userId: String)
    case trackClick
    case triggerEvent

    var path: String {
        switch self {
        case .registerUser:
            return "/users"
        case .getUser(let id):
            return "/users/\(motisigPathEncode(id))"
        case .updateUser(let id):
            return "/users/\(motisigPathEncode(id))"
        case .addTags(let id):
            return "/users/\(motisigPathEncode(id))/tags"
        case .removeTags(let id):
            return "/users/\(motisigPathEncode(id))/tags"
        case .setAttributes(let id):
            return "/users/\(motisigPathEncode(id))/attributes"
        case .removeAttributes(let id):
            return "/users/\(motisigPathEncode(id))/attributes"
        case .upsertPushSubscription(let id), .patchPushSubscription(let id), .removePushSubscription(let id):
            return "/users/\(motisigPathEncode(id))/push-subscriptions"
        case .ping(let id):
            return "/users/\(motisigPathEncode(id))/ping"
        case .trackClick:
            return "/track/click"
        case .triggerEvent:
            return "/events"
        }
    }

    var method: HTTPMethod {
        switch self {
        case .getUser:
            return .GET
        case .updateUser, .patchPushSubscription:
            return .PATCH
        case .removeTags, .removeAttributes, .removePushSubscription:
            return .DELETE
        default:
            return .POST
        }
    }

    func urlRequest(baseURL: URL, sdkKey: String, projectId: String, body: Data? = nil) -> URLRequest {
        let trimmed = path.hasPrefix("/") ? String(path.dropFirst()) : path
        let segments = trimmed.split(separator: "/").map(String.init)
        var url = baseURL
        for segment in segments {
            url.appendPathComponent(segment)
        }
        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.setValue(sdkKey, forHTTPHeaderField: "X-API-Key")
        request.setValue(projectId, forHTTPHeaderField: "X-Project-ID")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        return request
    }
}
