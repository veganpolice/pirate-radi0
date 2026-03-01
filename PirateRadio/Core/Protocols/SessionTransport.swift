import Foundation

/// Connection state for the transport layer.
enum ConnectionState: Sendable, Equatable {
    case disconnected
    case connecting
    case connected
    case reconnecting(attempt: Int)
    case resyncing
    case failed(String)
}

/// A message sent or received over the session transport.
/// All messages carry sequence numbers and epochs for ordering and staleness detection.
struct SyncMessage: Codable, Sendable {
    let id: UUID
    let type: SyncMessageType
    let sequenceNumber: UInt64
    let epoch: UInt64
    let timestamp: UInt64 // NTP timestamp

    enum SyncMessageType: Codable, Sendable {
        case playPrepare(trackID: String, prepareDeadline: UInt64)
        case playCommit(trackID: String, startAtNtp: UInt64, refSeq: UInt64)
        case pause(atNtp: UInt64)
        case resume(atNtp: UInt64)
        case seek(positionMs: Int, atNtp: UInt64)
        case skip
        case addToQueue(track: Track, nonce: String)
        case driftReport(trackID: String, positionMs: Int, ntpTimestamp: UInt64)
        case stateSync(SessionSnapshot)
        case queueUpdate([Track])
        case memberJoined(userID: UserID, displayName: String)
        case memberLeft(UserID)
    }
}

/// Snapshot of the full session state, used for reconnection and join-mid-song.
struct SessionSnapshot: Codable, Sendable {
    let trackID: String?
    let positionAtAnchor: Double // seconds
    let ntpAnchor: UInt64
    let playbackRate: Double // 1.0 = playing, 0.0 = paused
    let queue: [Track]
    let djUserID: UserID
    let epoch: UInt64
    let sequenceNumber: UInt64
    let members: [SnapshotMember]
    let currentTrack: Track? // Full track object for UI display

    struct SnapshotMember: Codable, Sendable {
        let userId: String
        let displayName: String
    }

    init(trackID: String?, positionAtAnchor: Double, ntpAnchor: UInt64,
         playbackRate: Double, queue: [Track], djUserID: UserID,
         epoch: UInt64, sequenceNumber: UInt64,
         members: [SnapshotMember] = [], currentTrack: Track? = nil) {
        self.trackID = trackID
        self.positionAtAnchor = positionAtAnchor
        self.ntpAnchor = ntpAnchor
        self.playbackRate = playbackRate
        self.queue = queue
        self.djUserID = djUserID
        self.epoch = epoch
        self.sequenceNumber = sequenceNumber
        self.members = members
        self.currentTrack = currentTrack
    }
}

typealias UserID = String
typealias SessionID = String

/// Abstracts the real-time transport layer for testability and future P2P support.
protocol SessionTransport: Sendable {
    func connect(to session: SessionID, token: String) async throws
    func disconnect() async
    func send(_ message: SyncMessage) async throws
    var incomingMessages: AsyncStream<SyncMessage> { get }
    var connectionState: AsyncStream<ConnectionState> { get }
}
