import Foundation

public enum MotiSigError: LocalizedError {
    case invalidConfiguration(String)
    case notInitialized
    case userNotSet
    case networkError(Error)
    case apiError(statusCode: Int, message: String?)
    case encodingError(Error)
    case decodingError(Error)

    public var errorDescription: String? {
        switch self {
        case .invalidConfiguration(let reason):
            return "MotiSig configuration error: \(reason)"
        case .notInitialized:
            return "MotiSig has not been initialized. Call MotiSig.initialize(...) and ensure it returns true (valid sdkKey and projectId)."
        case .userNotSet:
            return "No user has been set. Call MotiSig.shared.setUser(id:) first."
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .apiError(let statusCode, let message):
            return "API error (\(statusCode)): \(message ?? "Unknown error")"
        case .encodingError(let error):
            return "Encoding error: \(error.localizedDescription)"
        case .decodingError(let error):
            return "Decoding error: \(error.localizedDescription)"
        }
    }
}
