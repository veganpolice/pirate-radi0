import Foundation

struct Track: Codable, Sendable, Identifiable, Equatable {
    let id: String          // Spotify track ID (base-62, 22 chars)
    let name: String
    let artist: String
    let albumName: String
    let albumArtURL: URL?
    let durationMs: Int

    var durationFormatted: String {
        let seconds = durationMs / 1000
        let mins = seconds / 60
        let secs = seconds % 60
        return String(format: "%d:%02d", mins, secs)
    }
}
