import Foundation

/// In-memory FIFO buffer for notification events when no listeners are registered.
final class EventBuffer {
    private let syncQueue = DispatchQueue(label: "com.motisig.sdk.eventBuffer")
    private var events: [(MotiSigNotification, Bool)] = []
    private let maxEvents: Int

    init(maxEvents: Int = 50) {
        self.maxEvents = max(1, maxEvents)
    }

    func enqueue(_ notification: MotiSigNotification, inForeground: Bool) {
        syncQueue.sync {
            events.append((notification, inForeground))
            while events.count > maxEvents {
                events.removeFirst()
            }
        }
    }

    /// Returns buffered events and clears the buffer.
    func drain() -> [(MotiSigNotification, Bool)] {
        syncQueue.sync {
            let copy = events
            events.removeAll(keepingCapacity: false)
            return copy
        }
    }

    func clear() {
        syncQueue.sync {
            events.removeAll(keepingCapacity: false)
        }
    }
}
