import Foundation

/// Ring buffer of recently delivered click `messageId`s to suppress duplicate enqueues.
final class ClickDedupeStore {

    private static let storageKey = "ai.motisig.sdk.clickDedupe.v1"
    private static let maxIds = 100

    private let defaults: UserDefaults
    private let syncQueue = DispatchQueue(label: "ai.motisig.sdk.clickDedupe")
    private var ids: [String] = []
    private var loaded = false

    init(defaults: UserDefaults = UserDefaults(suiteName: "ai.motisig.sdk") ?? .standard) {
        self.defaults = defaults
    }

    func load() {
        syncQueue.sync {
            guard !loaded else { return }
            if let data = defaults.data(forKey: Self.storageKey),
               let parsed = try? JSONDecoder().decode([String].self, from: data) {
                ids = Array(parsed.suffix(Self.maxIds))
            } else {
                ids = []
            }
            loaded = true
        }
    }

    func has(_ messageId: String) -> Bool {
        syncQueue.sync {
            ensureLoaded()
            return ids.contains(messageId)
        }
    }

    func add(_ messageId: String) {
        syncQueue.sync {
            ensureLoaded()
            guard !ids.contains(messageId) else { return }
            ids.append(messageId)
            if ids.count > Self.maxIds {
                ids = Array(ids.suffix(Self.maxIds))
            }
            if let data = try? JSONEncoder().encode(ids) {
                defaults.set(data, forKey: Self.storageKey)
            }
        }
    }

    func clear() {
        syncQueue.sync {
            ids = []
            loaded = true
            if let data = try? JSONEncoder().encode(ids) {
                defaults.set(data, forKey: Self.storageKey)
            }
        }
    }

    private func ensureLoaded() {
        if !loaded { load() }
    }
}
