import Foundation
import SwiftUI

struct Session: Codable, Sendable, Identifiable, Equatable {
    let id: String              // station owner userId
    let creatorID: UserID
    var djUserID: UserID?       // nil when owner not connected (autonomous playback)
    var members: [Member]
    var queue: [Track]
    var currentTrack: Track?
    var isPlaying: Bool
    var epoch: UInt64

    struct Member: Codable, Sendable, Identifiable, Equatable {
        let id: UserID
        var displayName: String
        var isConnected: Bool
        var tracksAdded: Int
        var avatarColor: AvatarColor

        init(id: UserID, displayName: String, isConnected: Bool,
             tracksAdded: Int = 0, avatarColor: AvatarColor = .cyan) {
            self.id = id
            self.displayName = displayName
            self.isConnected = isConnected
            self.tracksAdded = tracksAdded
            self.avatarColor = avatarColor
        }
    }

    init(id: String, creatorID: UserID, djUserID: UserID?,
         members: [Member], queue: [Track], currentTrack: Track?, isPlaying: Bool,
         epoch: UInt64) {
        self.id = id
        self.creatorID = creatorID
        self.djUserID = djUserID
        self.members = members
        self.queue = queue
        self.currentTrack = currentTrack
        self.isPlaying = isPlaying
        self.epoch = epoch
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
