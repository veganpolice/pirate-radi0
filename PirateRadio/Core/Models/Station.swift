import Foundation

/// A live station on the dial, returned by GET /stations.
struct Station: Codable, Identifiable {
    let userId: String
    let displayName: String
    let frequency: Double
    let sessionId: String
    let currentTrack: Track?

    var id: String { userId }

    // FM band constants shared across dial and home screen
    static let fmMin = 88.0
    static let fmMax = 108.0
    static let snapThreshold = 0.08

    /// Normalized dial position (0.0–1.0) for this station's frequency.
    var dialValue: Double {
        (frequency - Self.fmMin) / (Self.fmMax - Self.fmMin)
    }

    /// Find the station nearest to a dial position, within snap threshold.
    static func snapped(from stations: [Station], at dialValue: Double) -> Station? {
        stations.min(by: { abs(dialValue - $0.dialValue) < abs(dialValue - $1.dialValue) })
            .flatMap { abs(dialValue - $0.dialValue) < snapThreshold ? $0 : nil }
    }
}
