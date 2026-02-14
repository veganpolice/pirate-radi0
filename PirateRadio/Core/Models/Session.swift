import Foundation
import SwiftUI

enum DJMode: String, Codable, CaseIterable, Sendable {
    case solo = "Solo DJ"
    case collaborative = "Collab Queue"
    case hotSeat = "Hot Seat"

    var icon: String {
        switch self {
        case .solo: "antenna.radiowaves.left.and.right"
        case .collaborative: "hand.thumbsup"
        case .hotSeat: "arrow.triangle.2.circlepath"
        }
    }

    var description: String {
        switch self {
        case .solo: "You control the music"
        case .collaborative: "Everyone votes on what plays next"
        case .hotSeat: "DJ rotates every few songs"
        }
    }
}

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
    var djMode: DJMode
    var hotSeatSongsPerDJ: Int
    var hotSeatSongsRemaining: Int

    struct Member: Codable, Sendable, Identifiable, Equatable {
        let id: UserID
        var displayName: String
        var isConnected: Bool
        var tracksAdded: Int
        var votesCast: Int
        var djTimeMinutes: Int
        var avatarColor: AvatarColor

        init(id: UserID, displayName: String, isConnected: Bool,
             tracksAdded: Int = 0, votesCast: Int = 0, djTimeMinutes: Int = 0,
             avatarColor: AvatarColor = .cyan) {
            self.id = id
            self.displayName = displayName
            self.isConnected = isConnected
            self.tracksAdded = tracksAdded
            self.votesCast = votesCast
            self.djTimeMinutes = djTimeMinutes
            self.avatarColor = avatarColor
        }
    }

    init(id: String, joinCode: String, creatorID: UserID, djUserID: UserID,
         members: [Member], queue: [Track], currentTrack: Track?, isPlaying: Bool,
         epoch: UInt64, djMode: DJMode = .solo, hotSeatSongsPerDJ: Int = 3,
         hotSeatSongsRemaining: Int = 3) {
        self.id = id
        self.joinCode = joinCode
        self.creatorID = creatorID
        self.djUserID = djUserID
        self.members = members
        self.queue = queue
        self.currentTrack = currentTrack
        self.isPlaying = isPlaying
        self.epoch = epoch
        self.djMode = djMode
        self.hotSeatSongsPerDJ = hotSeatSongsPerDJ
        self.hotSeatSongsRemaining = hotSeatSongsRemaining
    }
}

/// Codable-friendly color for member avatars.
enum AvatarColor: String, Codable, CaseIterable, Sendable {
    case cyan, magenta, amber, green, purple, pink, orange, blue

    var color: Color {
        switch self {
        case .cyan: PirateTheme.signal
        case .magenta: PirateTheme.broadcast
        case .amber: PirateTheme.flare
        case .green: Color(red: 0.2, green: 1, blue: 0.4)
        case .purple: Color(red: 0.6, green: 0.3, blue: 1)
        case .pink: Color(red: 1, green: 0.4, blue: 0.6)
        case .orange: Color(red: 1, green: 0.5, blue: 0.1)
        case .blue: Color(red: 0.3, green: 0.5, blue: 1)
        }
    }
}
