import Foundation

/// A radio station on the dial, returned by GET /stations.
struct Station: Codable, Identifiable {
    let userId: String
    let displayName: String
    let frequency: Int          // MHz x 10 (e.g. 881 = 88.1 MHz)
    let currentTrack: Track?
    let trackCount: Int
    let listenerCount: Int
    let isLive: Bool
    let ownerConnected: Bool

    var id: String { userId }

    // FM band constants shared across dial and home screen
    static let fmMinInt = 881
    static let fmMaxInt = 1079
    static let fmMin = 88.1
    static let fmMax = 107.9
    static let snapThreshold = 0.08

    /// Display frequency as a Double (e.g. 88.1)
    var frequencyDisplay: Double {
        Double(frequency) / 10.0
    }

    /// Normalized dial position (0.0–1.0) for this station's frequency.
    var dialValue: Double {
        (frequencyDisplay - Self.fmMin) / (Self.fmMax - Self.fmMin)
    }

    /// Find the station nearest to a dial position, within snap threshold.
    static func snapped(from stations: [Station], at dialValue: Double) -> Station? {
        stations.min(by: { abs(dialValue - $0.dialValue) < abs(dialValue - $1.dialValue) })
            .flatMap { abs(dialValue - $0.dialValue) < snapThreshold ? $0 : nil }
    }
}
