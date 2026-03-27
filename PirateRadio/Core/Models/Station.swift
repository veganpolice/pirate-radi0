import Foundation

/// A public station on the radio dial, returned by GET /stations.
struct Station: Codable, Identifiable {
    let id: String          // e.g. "station-88"
    let name: String        // e.g. "88.🏴‍☠️"
    let frequency: Double   // e.g. 88.1
    let currentTrack: Track?
    let isPlaying: Bool
    let listenerCount: Int
    let queueLength: Int
}
