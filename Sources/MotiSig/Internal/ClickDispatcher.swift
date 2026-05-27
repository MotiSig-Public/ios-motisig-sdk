import Foundation

struct ClickRetryOptions {
    var maxAttempts: Int = 50
    var baseDelaySeconds: TimeInterval = 1
    var maxDelaySeconds: TimeInterval = 30
}

/// Drains a persistent click queue with deduplication and exponential backoff retry.
final class ClickDispatcher {

    private let queue = PendingClicksQueue()
    private let dedupe = ClickDedupeStore()
    private let httpClientProvider: () -> HTTPClient?
    private let userIdProvider: () -> String?
    private let retryOptions: ClickRetryOptions

    private let drainQueue = DispatchQueue(label: "ai.motisig.sdk.clickDispatcher.drain")
    private var disposed = false
    private var drainRunning = false
    private var retryWorkItem: DispatchWorkItem?

    init(
        httpClientProvider: @escaping () -> HTTPClient?,
        userIdProvider: @escaping () -> String?,
        retryOptions: ClickRetryOptions = ClickRetryOptions()
    ) {
        self.httpClientProvider = httpClientProvider
        self.userIdProvider = userIdProvider
        self.retryOptions = retryOptions
    }

    func start() {
        queue.load()
        dedupe.load()
        kick()
    }

    func kick() {
        guard !disposed else { return }
        drainQueue.async { [weak self] in
            self?.runDrain()
        }
    }

    func enqueueClick(messageId: String, isForeground: Bool?, userId: String?) {
        guard !disposed else { return }
        let trimmed = messageId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if dedupe.has(trimmed) { return }
        queue.enqueue(PendingClickEnqueue(messageId: trimmed, isForeground: isForeground, userId: userId))
        kick()
    }

    func onUserSet(userId: String) {
        guard !disposed else { return }
        queue.updateUserIdForPending(userId: userId)
        kick()
    }

    func clearAll() {
        queue.clearAll()
        dedupe.clear()
        cancelRetryTimer()
    }

    func dispose() {
        disposed = true
        cancelRetryTimer()
    }

    private func cancelRetryTimer() {
        retryWorkItem?.cancel()
        retryWorkItem = nil
    }

    private func scheduleRetryTimer() {
        cancelRetryTimer()
        guard !disposed else { return }
        guard let at = queue.soonestRetryAt() else { return }
        let delay = max(0, at - Date().timeIntervalSince1970)
        let item = DispatchWorkItem { [weak self] in
            self?.kick()
        }
        retryWorkItem = item
        drainQueue.asyncAfter(deadline: .now() + delay, execute: item)
    }

    private func runDrain() {
        guard !disposed, !drainRunning else { return }
        drainRunning = true
        Task { [weak self] in
            guard let self else { return }
            defer {
                self.drainQueue.async {
                    self.drainRunning = false
                    self.scheduleRetryTimer()
                }
            }
            while !self.disposed {
                let progressed = await self.drainDueBatch()
                if !progressed { break }
            }
        }
    }

    /// @return true if any entry was processed or dropped
    private func drainDueBatch() async -> Bool {
        guard let client = httpClientProvider() else { return false }

        let now = Date().timeIntervalSince1970
        let due = queue.peekDue(now: now)
        guard !due.isEmpty else { return false }

        var acted = false
        for entry in due {
            if disposed { break }

            if dedupe.has(entry.messageId) {
                queue.markSent(id: entry.id)
                acted = true
                continue
            }

            let userId = entry.userId ?? userIdProvider()
            guard let userId else { continue }

            let body = TrackClickBody(
                userId: userId,
                messageId: entry.messageId,
                isForeground: entry.isForeground
            )

            do {
                try await client.request(.trackClick, body: body)
                queue.markSent(id: entry.id)
                dedupe.add(entry.messageId)
                Logger.shared.debug("Click tracked for message \(entry.messageId)")
                acted = true
            } catch {
                let status = Self.statusCode(from: error)
                if Self.isNonRetryableClientError(status) {
                    Logger.shared.error("click dropped (non-retryable) messageId=\(entry.messageId) status=\(status)")
                    queue.markSent(id: entry.id)
                    acted = true
                    continue
                }
                if !Self.isRetryableStatus(status) {
                    Logger.shared.error("click dropped (unexpected status) messageId=\(entry.messageId) status=\(status)")
                    queue.markSent(id: entry.id)
                    acted = true
                    continue
                }

                let attempts = entry.attempts + 1
                if attempts >= retryOptions.maxAttempts {
                    Logger.shared.error("click dropped (max attempts) messageId=\(entry.messageId) attempts=\(attempts)")
                    queue.markSent(id: entry.id)
                    acted = true
                    continue
                }

                let backoff = Self.backoffSeconds(
                    attempts: attempts,
                    base: retryOptions.baseDelaySeconds,
                    maxDelay: retryOptions.maxDelaySeconds
                )
                let nextAttemptAt = now + backoff
                queue.recordFailure(id: entry.id, nextAttemptAt: nextAttemptAt, attempts: attempts)
                Logger.shared.debug("click retry scheduled messageId=\(entry.messageId) attempts=\(attempts) backoff=\(backoff)s")
                acted = true
            }
        }

        return acted
    }

    private static func statusCode(from error: Error) -> Int {
        if let err = error as? MotiSigError, case .apiError(let code, _) = err {
            return code
        }
        if error is MotiSigError {
            return 0
        }
        return 0
    }

    private static func isRetryableStatus(_ status: Int) -> Bool {
        if status == 0 || status == 408 || status == 429 { return true }
        if status >= 500 && status < 600 { return true }
        return false
    }

    private static func isNonRetryableClientError(_ status: Int) -> Bool {
        status >= 400 && status < 500 && !isRetryableStatus(status)
    }

    private static func backoffSeconds(attempts: Int, base: TimeInterval, maxDelay: TimeInterval) -> TimeInterval {
        let exponent = min(maxDelay, base * pow(2, Double(Swift.max(0, attempts - 1))))
        let jitter = exponent * 0.2 * (Double.random(in: -1...1))
        return Swift.max(0, exponent + jitter)
    }
}
