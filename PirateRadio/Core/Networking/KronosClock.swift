import Foundation
import Kronos

/// Production ClockProvider backed by Kronos NTP sync.
/// Achieves 10-50ms accuracy over cellular — well within the 300ms sync target.
final class KronosClock: ClockProvider, Sendable {
    init() {
        Clock.sync()
    }

    func now() -> UInt64 {
        let ntpDate = Clock.now ?? Date()
        return UInt64(ntpDate.timeIntervalSince1970 * 1000)
    }

    var estimatedOffset: Duration {
        // Kronos doesn't expose raw offset, but Clock.now adjusts Date() by it.
        // Compute the delta between NTP and system clock.
        guard let ntpNow = Clock.now else { return .zero }
        let systemNow = Date()
        let offsetSeconds = ntpNow.timeIntervalSince(systemNow)
        return .seconds(offsetSeconds)
    }

    var isSynced: Bool {
        Clock.now != nil
    }

    func resync() async {
        await withCheckedContinuation { continuation in
            Clock.sync(completion: { _, _ in
                continuation.resume()
            })
        }
    }
}
