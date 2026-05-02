import Foundation

/// Serializes async mutation work in FIFO order (one in-flight item at a time).
final class FIFOAsyncMutationQueue: @unchecked Sendable {

    private let gate = DispatchQueue(label: "com.motisig.sdk.mutation-queue")
    private var pending: [() async -> Void] = []
    private var isDraining = false

    func enqueue(_ work: @escaping () async -> Void) {
        let shouldStart = gate.sync { () -> Bool in
            pending.append(work)
            if isDraining {
                return false
            }
            isDraining = true
            return true
        }

        if shouldStart {
            Task {
                await self.drainUntilEmpty()
            }
        }
    }

    private func drainUntilEmpty() async {
        while true {
            let work: () async -> Void = {
                gate.sync {
                    precondition(!pending.isEmpty, "drain with empty pending while isDraining")
                    return pending.removeFirst()
                }
            }()

            await work()

            let shouldStop = gate.sync { () -> Bool in
                if pending.isEmpty {
                    isDraining = false
                    return true
                }
                return false
            }
            if shouldStop {
                return
            }
        }
    }
}
