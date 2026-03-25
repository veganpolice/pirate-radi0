import Foundation

/// A mock clock for testing that uses wall-clock time with a configurable offset.
/// In tests, use `advance(by:)` to simulate time progression without waiting.
final class MockClockProvider: ClockProvider, @unchecked Sendable {
    private var offset: Int64 = 0
    private(set) var resyncCount = 0

    var isSynced: Bool = true

    var estimatedOffset: Duration {
        .nanoseconds(Int64(offset) * 1_000_000) // ms → ns
    }

    func now() -> UInt64 {
        let wallClock = UInt64(Date().timeIntervalSince1970 * 1000)
        if offset >= 0 {
            return wallClock + UInt64(offset)
        } else {
            return wallClock - UInt64(-offset)
        }
    }

    func resync() async {
        resyncCount += 1
        isSynced = true
    }

    // MARK: - Test Helpers

    /// Advance the mock clock by the given number of milliseconds.
    func advance(by ms: Int64) {
        offset += ms
    }

    /// Set the offset directly (e.g., to simulate NTP drift).
    func setOffset(_ ms: Int64) {
        offset = ms
    }
}
