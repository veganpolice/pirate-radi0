import Foundation

struct Track: Codable, Sendable, Identifiable, Equatable {
    let id: String          // Spotify track ID (base-62, 22 chars)
    let name: String
    let artist: String
    let albumName: String
    let albumArtURL: URL?
    let durationMs: Int
    var votes: Int
    var requestedBy: String?
    var isUpvotedByMe: Bool
    var isDownvotedByMe: Bool

    init(id: String, name: String, artist: String, albumName: String,
         albumArtURL: URL?, durationMs: Int, votes: Int = 0,
         requestedBy: String? = nil, isUpvotedByMe: Bool = false,
         isDownvotedByMe: Bool = false) {
        self.id = id
        self.name = name
        self.artist = artist
        self.albumName = albumName
        self.albumArtURL = albumArtURL
        self.durationMs = durationMs
        self.votes = votes
        self.requestedBy = requestedBy
        self.isUpvotedByMe = isUpvotedByMe
        self.isDownvotedByMe = isDownvotedByMe
    }

    var durationFormatted: String {
        let seconds = durationMs / 1000
        let mins = seconds / 60
        let secs = seconds % 60
        return String(format: "%d:%02d", mins, secs)
    }
}
