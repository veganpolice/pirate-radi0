import Foundation

/// A timestamped, sequenced command for the sync protocol.
/// Every command carries an epoch and sequence number to prevent stale/duplicate execution.
struct SyncCommand: Codable, Sendable, Identifiable {
    let id: UUID
    let type: CommandType
    let executionTime: UInt64       // NTP timestamp in ms
    let issuedBy: UserID
    let sequenceNumber: UInt64      // Monotonic per session
    let epoch: UInt64               // Mode/authority epoch

    enum CommandType: Codable, Sendable {
        case play(trackID: String, startPosition: Double)
        case pause
        case resume
        case seek(to: Double)
        case skip
        case addToQueue(trackID: String, nonce: String)
        case removeFromQueue(trackID: String)
    }
}

/// An NTP-anchored position that never goes stale in transit.
/// Receivers compute the current position from the anchor regardless of when the message arrives.
struct NTPAnchoredPosition: Codable, Sendable {
    let trackID: String
    let positionAtAnchor: Double    // seconds
    let ntpAnchor: UInt64           // NTP timestamp in ms
    let playbackRate: Double        // 0.0 = paused, 1.0 = normal

    func positionAt(ntpTime: UInt64) -> Double {
        let elapsed = Double(ntpTime - ntpAnchor) / 1000.0
        return positionAtAnchor + (elapsed * playbackRate)
    }
}
