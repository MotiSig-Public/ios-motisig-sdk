import Foundation

/// Request body for `POST /events`.
struct TriggerEventBody: Encodable {
    let userId: String
    let eventName: String
    /// Omitted from JSON when `nil` (synthesized `Encodable` uses `encodeIfPresent`).
    var eventData: [String: AnyCodable]?
}
