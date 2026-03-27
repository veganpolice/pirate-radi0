import Foundation

/// A live station on the dial, returned by GET /stations.
struct Station: Codable, Identifiable {
    let userId: String
    let displayName: String
    let frequency: Double
    let sessionId: String
    let currentTrack: Track?

    var id: String { userId }
}
