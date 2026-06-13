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
