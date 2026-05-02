import XCTest
@testable import MotiSig

final class FIFOAsyncMutationQueueTests: XCTestCase {

    func test_enqueue_runsWorkInFIFOOrder() async {
        let queue = FIFOAsyncMutationQueue()
        actor OrderLog {
            private var values: [Int] = []
            func append(_ value: Int) { values.append(value) }
            var count: Int { values.count }
            var snapshot: [Int] { values }
        }
        let log = OrderLog()

        for i in 0..<8 {
            let value = i
            queue.enqueue {
                try? await Task.sleep(nanoseconds: 5_000_000)
                await log.append(value)
            }
        }

        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            let count = await log.count
            if count == 8 { break }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }

        let finalOrder = await log.snapshot
        XCTAssertEqual(finalOrder, Array(0..<8), "Work should complete in strict enqueue order")
    }
}
