import Foundation
import SwiftUI

struct Session: Codable, Sendable, Identifiable, Equatable {
    let id: String              // Station ID (e.g. "station-88")
    var stationName: String     // e.g. "88.🏴‍☠️"
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
        var votesCast: Int
        var avatarColor: AvatarColor

        init(id: UserID, displayName: String, isConnected: Bool,
             tracksAdded: Int = 0, votesCast: Int = 0,
             avatarColor: AvatarColor = .cyan) {
            self.id = id
            self.displayName = displayName
            self.isConnected = isConnected
            self.tracksAdded = tracksAdded
            self.votesCast = votesCast
            self.avatarColor = avatarColor
        }
    }

    init(id: String, stationName: String = "",
         members: [Member], queue: [Track], currentTrack: Track?, isPlaying: Bool,
         epoch: UInt64) {
        self.id = id
        self.stationName = stationName
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
