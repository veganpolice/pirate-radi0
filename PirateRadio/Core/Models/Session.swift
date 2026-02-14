import Foundation

struct Session: Codable, Sendable, Identifiable, Equatable {
    let id: String              // UUID v4
    let joinCode: String        // 4-digit numeric code
    let creatorID: UserID
    var djUserID: UserID
    var members: [Member]
    var queue: [Track]
    var currentTrack: Track?
    var isPlaying: Bool
    var epoch: UInt64

    struct Member: Codable, Sendable, Identifiable, Equatable {
        let id: UserID
        var displayName: String
        var isConnected: Bool
    }
}
