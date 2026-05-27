import Foundation

struct PendingClick: Codable, Equatable {
    let id: String
    let messageId: String
    let isForeground: Bool?
    var userId: String?
    let enqueuedAt: TimeInterval
    var attempts: Int
    var nextAttemptAt: TimeInterval
}

struct PendingClickEnqueue {
    let messageId: String
    let isForeground: Bool?
    let userId: String?
}

/// Persistent FIFO queue for click events awaiting delivery (UserDefaults-backed).
final class PendingClicksQueue {

    private static let storageKey = "ai.motisig.sdk.pendingClicks.v1"
    private static let maxEntries = 200
    private static let ttlSeconds: TimeInterval = 7 * 24 * 60 * 60

    private let defaults: UserDefaults
    private let writeQueue = DispatchQueue(label: "ai.motisig.sdk.pendingClicks.write")
    private var entries: [PendingClick] = []
    private var loaded = false

    init(defaults: UserDefaults = UserDefaults(suiteName: "ai.motisig.sdk") ?? .standard) {
        self.defaults = defaults
    }

    func load() {
        writeQueue.sync {
            guard !loaded else { return }
            let now = Date().timeIntervalSince1970
            if let data = defaults.data(forKey: Self.storageKey),
               let parsed = try? JSONDecoder().decode([PendingClick].self, from: data) {
                entries = Self.capEntries(Self.purgeStale(parsed, now: now))
            } else {
                entries = []
            }
            loaded = true
        }
    }

    @discardableResult
    func enqueue(_ input: PendingClickEnqueue) -> PendingClick {
        writeQueue.sync {
            ensureLoaded()
            let now = Date().timeIntervalSince1970
            let entry = PendingClick(
                id: UUID().uuidString,
                messageId: input.messageId,
                isForeground: input.isForeground,
                userId: input.userId,
                enqueuedAt: now,
                attempts: 0,
                nextAttemptAt: now
            )
            entries.append(entry)
            entries = Self.capEntries(Self.purgeStale(entries, now: now))
            persist()
            return entry
        }
    }

    func peekDue(now: TimeInterval) -> [PendingClick] {
        writeQueue.sync {
            ensureLoaded()
            return entries.filter { $0.nextAttemptAt <= now }
        }
    }

    func markSent(id: String) {
        writeQueue.sync {
            ensureLoaded()
            entries.removeAll { $0.id == id }
            persist()
        }
    }

    func recordFailure(id: String, nextAttemptAt: TimeInterval, attempts: Int) {
        writeQueue.sync {
            ensureLoaded()
            guard let idx = entries.firstIndex(where: { $0.id == id }) else { return }
            entries[idx].attempts = attempts
            entries[idx].nextAttemptAt = nextAttemptAt
            persist()
        }
    }

    func updateUserIdForPending(userId: String) {
        writeQueue.sync {
            ensureLoaded()
            var changed = false
            for i in entries.indices where entries[i].userId == nil {
                entries[i].userId = userId
                changed = true
            }
            if changed { persist() }
        }
    }

    func clearAll() {
        writeQueue.sync {
            entries = []
            loaded = true
            persist()
        }
    }

    func soonestRetryAt() -> TimeInterval? {
        writeQueue.sync {
            ensureLoaded()
            guard !entries.isEmpty else { return nil }
            return entries.map(\.nextAttemptAt).min()
        }
    }

    private func ensureLoaded() {
        if !loaded { load() }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(entries) {
            defaults.set(data, forKey: Self.storageKey)
        }
    }

    private static func purgeStale(_ entries: [PendingClick], now: TimeInterval) -> [PendingClick] {
        entries.filter { now - $0.enqueuedAt <= ttlSeconds }
    }

    private static func capEntries(_ entries: [PendingClick]) -> [PendingClick] {
        guard entries.count > maxEntries else { return entries }
        return Array(entries.suffix(maxEntries))
    }
}
