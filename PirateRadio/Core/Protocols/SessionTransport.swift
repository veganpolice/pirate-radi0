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
        case driftReport(trackID: String, positionMs: Int, ntpTimestamp: UInt64)
        case stateSync(SessionSnapshot)
        case queueUpdate([String]) // Track IDs
        case memberJoined(UserID)
        case memberLeft(UserID)
    }
}

/// Snapshot of the full session state, used for reconnection and join-mid-song.
struct SessionSnapshot: Codable, Sendable {
    let trackID: String?
    let positionAtAnchor: Double
    let ntpAnchor: UInt64
    let playbackRate: Double
    let queue: [String]
    let djUserID: UserID
    let epoch: UInt64
    let sequenceNumber: UInt64
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
