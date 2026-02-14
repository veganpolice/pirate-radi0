import Foundation

/// Abstracts NTP clock synchronization for testability.
/// In production, backed by Kronos. In tests, returns deterministic values.
protocol ClockProvider: Sendable {
    /// Returns the current NTP-synchronized time in milliseconds since epoch.
    func now() -> UInt64

    /// Estimated offset between device clock and NTP time.
    var estimatedOffset: Duration { get }

    /// Whether clock sync has completed at least once.
    var isSynced: Bool { get }

    /// Force a fresh clock sync (e.g., after network change).
    func resync() async
}
