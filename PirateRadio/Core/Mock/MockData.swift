import Foundation
import SwiftUI

/// All mock data for demo mode — tracks, members, discovery sessions, and stats.
enum MockData {

    // MARK: - Album Art URLs (Spotify CDN, public, no auth)

    private static func artURL(_ id: String) -> URL? {
        URL(string: "https://i.scdn.co/image/\(id)")
    }

    // MARK: - Tracks (30)

    static let tracks: [Track] = [
        Track(id: "1", name: "Around the World", artist: "Daft Punk", albumName: "Homework",
              albumArtURL: artURL("ab67616d0000b2731d5cf960a92bb8b03e2e27b8"), durationMs: 428_000),
        Track(id: "2", name: "Midnight City", artist: "M83", albumName: "Hurry Up, We're Dreaming",
              albumArtURL: artURL("ab67616d0000b2739b9b36b0e22082b979f37b18"), durationMs: 244_000),
        Track(id: "3", name: "Nightcall", artist: "Kavinsky", albumName: "OutRun",
              albumArtURL: artURL("ab67616d0000b2736ef8b23ad6ce38e58fb4e58f"), durationMs: 258_000),
        Track(id: "4", name: "The Less I Know The Better", artist: "Tame Impala", albumName: "Currents",
              albumArtURL: artURL("ab67616d0000b27379e3a6148e34b5980a688c17"), durationMs: 218_000),
        Track(id: "5", name: "Never Be Like You", artist: "Flume", albumName: "Skin",
              albumArtURL: artURL("ab67616d0000b273e55e8c04aa5e8caa7f5e0786"), durationMs: 234_000),
        Track(id: "6", name: "Do I Wanna Know?", artist: "Arctic Monkeys", albumName: "AM",
              albumArtURL: artURL("ab67616d0000b2730c8ac1a1e13e22eba6273302"), durationMs: 272_000),
        Track(id: "7", name: "Feel Good Inc", artist: "Gorillaz", albumName: "Demon Days",
              albumArtURL: artURL("ab67616d0000b2730c8c97ebf1b6f2e02e513012"), durationMs: 222_000),
        Track(id: "8", name: "Electric Feel", artist: "MGMT", albumName: "Oracular Spectacular",
              albumArtURL: artURL("ab67616d0000b2738b32b139981e79f2ebe005eb"), durationMs: 229_000),
        Track(id: "9", name: "A Moment Apart", artist: "ODESZA", albumName: "A Moment Apart",
              albumArtURL: artURL("ab67616d0000b273e2e23bab3693b6f8e89ab8e6"), durationMs: 267_000),
        Track(id: "10", name: "Innerbloom", artist: "RUFUS DU SOL", albumName: "Bloom",
              albumArtURL: artURL("ab67616d0000b273c0b1e8ade8f62f9fe0ad5b3f"), durationMs: 578_000),
        Track(id: "11", name: "Blinding Lights", artist: "The Weeknd", albumName: "After Hours",
              albumArtURL: artURL("ab67616d0000b2738863bc11d2aa12b54f5aeb36"), durationMs: 200_000),
        Track(id: "12", name: "D.A.N.C.E.", artist: "Justice", albumName: "Cross",
              albumArtURL: artURL("ab67616d0000b2737fb8572cafcd7d1a3c8f5b37"), durationMs: 243_000),
        Track(id: "13", name: "Intro", artist: "The xx", albumName: "xx",
              albumArtURL: artURL("ab67616d0000b2737aff810a7e93c5367f8e9360"), durationMs: 128_000),
        Track(id: "14", name: "Kids", artist: "MGMT", albumName: "Oracular Spectacular",
              albumArtURL: artURL("ab67616d0000b2738b32b139981e79f2ebe005eb"), durationMs: 305_000),
        Track(id: "15", name: "Alive", artist: "Daft Punk", albumName: "Alive 2007",
              albumArtURL: artURL("ab67616d0000b2738e5226da2a63dd5c1e9fd8a1"), durationMs: 325_000),
        Track(id: "16", name: "Dissolve", artist: "Absofacto", albumName: "Thousand Peaces",
              albumArtURL: artURL("ab67616d0000b273c9da4d3f2a5e31be18a5c02c"), durationMs: 213_000),
        Track(id: "17", name: "Let It Happen", artist: "Tame Impala", albumName: "Currents",
              albumArtURL: artURL("ab67616d0000b27379e3a6148e34b5980a688c17"), durationMs: 468_000),
        Track(id: "18", name: "Redbone", artist: "Childish Gambino", albumName: "Awaken, My Love!",
              albumArtURL: artURL("ab67616d0000b2731e0cdd393c8e08a98fc05c0f"), durationMs: 327_000),
        Track(id: "19", name: "Tadow", artist: "Masego & FKJ", albumName: "Tadow",
              albumArtURL: artURL("ab67616d0000b27383ea67ceb2e2c37ab82c3d85"), durationMs: 315_000),
        Track(id: "20", name: "Levitating", artist: "Dua Lipa", albumName: "Future Nostalgia",
              albumArtURL: artURL("ab67616d0000b273d4daf28d55fe4a899eb43b2f"), durationMs: 203_000),
        Track(id: "21", name: "Sun Is Shining", artist: "Lost Frequencies", albumName: "Less Is More",
              albumArtURL: artURL("ab67616d0000b2734d3c03561c9d3e6b5e30a82e"), durationMs: 177_000),
        Track(id: "22", name: "On Melancholy Hill", artist: "Gorillaz", albumName: "Plastic Beach",
              albumArtURL: artURL("ab67616d0000b27300c01afc61e6a3fd7b9acaa3"), durationMs: 234_000),
        Track(id: "23", name: "Something About Us", artist: "Daft Punk", albumName: "Discovery",
              albumArtURL: artURL("ab67616d0000b2739c28e15e6db0f588bdb84e2e"), durationMs: 232_000),
        Track(id: "24", name: "Breathe", artist: "Telepopmusik", albumName: "Genetic World",
              albumArtURL: artURL("ab67616d0000b2730d8d2e254f54b24f4c0b2a79"), durationMs: 291_000),
        Track(id: "25", name: "Little Dark Age", artist: "MGMT", albumName: "Little Dark Age",
              albumArtURL: artURL("ab67616d0000b27360cc3dcc67c0c49c604fd9ab"), durationMs: 300_000),
        Track(id: "26", name: "Crystallize", artist: "Lindsey Stirling", albumName: "Lindsey Stirling",
              albumArtURL: artURL("ab67616d0000b273f6e5b39563a11c7f89c6ea7e"), durationMs: 258_000),
        Track(id: "27", name: "Voyager", artist: "Daft Punk", albumName: "Discovery",
              albumArtURL: artURL("ab67616d0000b2739c28e15e6db0f588bdb84e2e"), durationMs: 228_000),
        Track(id: "28", name: "Thinkin Bout You", artist: "Frank Ocean", albumName: "channel ORANGE",
              albumArtURL: artURL("ab67616d0000b273c68169083e5e0cdcdb8a3e1a"), durationMs: 198_000),
        Track(id: "29", name: "Tokyo Drift", artist: "Teriyaki Boyz", albumName: "Beef or Chicken",
              albumArtURL: artURL("ab67616d0000b273e7e79a7bfd2cb63afb4c0b3a"), durationMs: 213_000),
        Track(id: "30", name: "One More Time", artist: "Daft Punk", albumName: "Discovery",
              albumArtURL: artURL("ab67616d0000b2739c28e15e6db0f588bdb84e2e"), durationMs: 321_000),
    ]

    // MARK: - Members (8)

    static let members: [Session.Member] = [
        .init(id: "demo-user-1", displayName: "DJ Powder", isConnected: true,
              tracksAdded: 12, votesCast: 8, djTimeMinutes: 45, avatarColor: .magenta),
        .init(id: "demo-user-2", displayName: "Shredder", isConnected: true,
              tracksAdded: 8, votesCast: 24, djTimeMinutes: 15, avatarColor: .cyan),
        .init(id: "demo-user-3", displayName: "Avalanche", isConnected: true,
              tracksAdded: 3, votesCast: 38, djTimeMinutes: 0, avatarColor: .amber),
        .init(id: "demo-user-4", displayName: "Mogul Queen", isConnected: true,
              tracksAdded: 6, votesCast: 15, djTimeMinutes: 20, avatarColor: .green),
        .init(id: "demo-user-5", displayName: "Apres Amy", isConnected: true,
              tracksAdded: 2, votesCast: 31, djTimeMinutes: 10, avatarColor: .purple),
        .init(id: "demo-user-6", displayName: "Gondola Greg", isConnected: true,
              tracksAdded: 1, votesCast: 4, djTimeMinutes: 0, avatarColor: .pink),
        .init(id: "demo-user-7", displayName: "Fresh Tracks", isConnected: true,
              tracksAdded: 9, votesCast: 19, djTimeMinutes: 5, avatarColor: .orange),
        .init(id: "demo-user-8", displayName: "Black Diamond", isConnected: true,
              tracksAdded: 5, votesCast: 22, djTimeMinutes: 0, avatarColor: .blue),
    ]

    // MARK: - Discovery Sessions (8)

    struct DiscoverySession: Identifiable {
        let id = UUID().uuidString
        let crewName: String
        let frequency: String
        let memberCount: Int
        let nowPlaying: Track
        let distance: String
        let members: [Session.Member]
    }

    static let discoverySessions: [DiscoverySession] = [
        .init(crewName: "Summit Senders", frequency: "91.7 FM", memberCount: 4,
              nowPlaying: tracks[1], distance: "0.2 mi", members: Array(members.prefix(4))),
        .init(crewName: "Powder Hounds", frequency: "94.3 FM", memberCount: 7,
              nowPlaying: tracks[2], distance: "0.8 mi", members: Array(members.prefix(7))),
        .init(crewName: "Apres Crew", frequency: "98.1 FM", memberCount: 3,
              nowPlaying: tracks[7], distance: "1.5 mi", members: Array(members.prefix(3))),
        .init(crewName: "Gondola Gang", frequency: "101.5 FM", memberCount: 6,
              nowPlaying: tracks[9], distance: "0.4 mi", members: Array(members.prefix(6))),
        .init(crewName: "Black Run DJs", frequency: "104.9 FM", memberCount: 2,
              nowPlaying: tracks[5], distance: "2.1 mi", members: Array(members.prefix(2))),
        .init(crewName: "Lodge Rats", frequency: "107.3 FM", memberCount: 8,
              nowPlaying: tracks[6], distance: "0.1 mi", members: members),
        .init(crewName: "Terrain Park Crew", frequency: "110.7 FM", memberCount: 5,
              nowPlaying: tracks[0], distance: "1.8 mi", members: Array(members.prefix(5))),
        .init(crewName: "First Chair Club", frequency: "88.5 FM", memberCount: 3,
              nowPlaying: tracks[8], distance: "3.2 mi", members: Array(members.prefix(3))),
    ]

    // MARK: - Demo Queue (with votes for collab mode)

    static var demoQueue: [Track] {
        var q = Array(tracks[3...9])
        q[0].votes = 12; q[0].requestedBy = "Shredder"
        q[1].votes = 8;  q[1].requestedBy = "Avalanche"
        q[2].votes = 15; q[2].requestedBy = "Fresh Tracks"; q[2].isUpvotedByMe = true
        q[3].votes = 3;  q[3].requestedBy = "Mogul Queen"
        q[4].votes = -2; q[4].requestedBy = "Gondola Greg"; q[4].isDownvotedByMe = true
        q[5].votes = 7;  q[5].requestedBy = "Apres Amy"
        q[6].votes = 20; q[6].requestedBy = "Black Diamond"; q[6].isUpvotedByMe = true
        return q
    }

    // MARK: - Pending Requests (for DJ inbox)

    static var pendingRequests: [Track] {
        var reqs = Array(tracks[10...14])
        reqs[0].requestedBy = "Shredder"
        reqs[1].requestedBy = "Avalanche"
        reqs[2].requestedBy = "Mogul Queen"
        reqs[3].requestedBy = "Fresh Tracks"
        reqs[4].requestedBy = "Black Diamond"
        return reqs
    }

    // MARK: - Session Stats (for recap)

    struct SessionStats {
        let totalTimeMinutes: Int
        let tracksPlayed: Int
        let topTrack: Track
        let mostRequests: (name: String, count: Int)
        let topDJ: (name: String, minutes: Int)
        let voteMachine: (name: String, count: Int)
        let djLeaderboard: [(name: String, minutes: Int)]
    }

    static let sessionStats = SessionStats(
        totalTimeMinutes: 154,
        tracksPlayed: 47,
        topTrack: tracks[2],
        mostRequests: ("Shredder", 12),
        topDJ: ("DJ Powder", 75),
        voteMachine: ("Avalanche", 38),
        djLeaderboard: [
            ("DJ Powder", 75),
            ("Mogul Queen", 20),
            ("Shredder", 15),
            ("Apres Amy", 10),
            ("Fresh Tracks", 5),
        ]
    )

    // MARK: - Demo Session Factory

    static func demoSession(djMode: DJMode = .solo) -> Session {
        Session(
            id: UUID().uuidString,
            joinCode: "7734",
            creatorID: "demo-user-1",
            djUserID: "demo-user-1",
            members: Array(members.prefix(5)),
            queue: demoQueue,
            currentTrack: tracks[0],
            isPlaying: true,
            epoch: 1,
            djMode: djMode,
            hotSeatSongsPerDJ: 3,
            hotSeatSongsRemaining: 2
        )
    }
}
