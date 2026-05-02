import Foundation

enum NotificationReceivedTimeFormat {
    static func label(receivedAt: Date, now: Date) -> String {
        let ageMs = max(0, now.timeIntervalSince(receivedAt) * 1000)
        if ageMs < 60_000 {
            let secs = Int(ageMs / 1000)
            return secs < 1 ? "Just now" : "\(secs)s ago"
        }
        if ageMs < 3_600_000 {
            let mins = Int(ageMs / 60_000)
            let secs = Int((ageMs.truncatingRemainder(dividingBy: 60_000)) / 1000)
            return "\(mins)m \(secs)s ago"
        }
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .medium
        formatter.locale = .current
        return formatter.string(from: receivedAt)
    }
}
