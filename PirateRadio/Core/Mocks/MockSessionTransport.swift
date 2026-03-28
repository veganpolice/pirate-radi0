import Foundation

/// A mock transport for testing the SyncEngine without a real WebSocket connection.
/// Captures outbound messages and allows injecting inbound messages.
actor MockSessionTransport: SessionTransport {
    // MARK: - Captured State

    private(set) var sentMessages: [SyncMessage] = []
    private(set) var sentVoiceClips: [(clipId: String, durationMs: Int, audioData: Data)] = []
    private(set) var isConnected = false
    private(set) var lastSessionID: SessionID?

    // MARK: - Streams

    let incomingMessages: AsyncStream<SyncMessage>
    private let messageContinuation: AsyncStream<SyncMessage>.Continuation

    let incomingVoiceClips: AsyncStream<IncomingVoiceClip>
    private let voiceClipContinuation: AsyncStream<IncomingVoiceClip>.Continuation

    let connectionState: AsyncStream<ConnectionState>
    private let stateContinuation: AsyncStream<ConnectionState>.Continuation

    init() {
        let (msgStream, msgCont) = AsyncStream.makeStream(of: SyncMessage.self, bufferingPolicy: .bufferingNewest(50))
        self.incomingMessages = msgStream
        self.messageContinuation = msgCont

        let (clipStream, clipCont) = AsyncStream.makeStream(of: IncomingVoiceClip.self, bufferingPolicy: .bufferingNewest(5))
        self.incomingVoiceClips = clipStream
        self.voiceClipContinuation = clipCont

        let (stateStream, stateCont) = AsyncStream.makeStream(of: ConnectionState.self, bufferingPolicy: .bufferingNewest(1))
        self.connectionState = stateStream
        self.stateContinuation = stateCont
    }

    // MARK: - SessionTransport

    func connect(to session: SessionID, token: String) async throws {
        lastSessionID = session
        isConnected = true
        stateContinuation.yield(.connected)
    }

    func disconnect() async {
        isConnected = false
        stateContinuation.yield(.disconnected)
    }

    func send(_ message: SyncMessage) async throws {
        sentMessages.append(message)
    }

    func sendVoiceClip(clipId: String, durationMs: Int, audioData: Data) async throws {
        sentVoiceClips.append((clipId: clipId, durationMs: durationMs, audioData: audioData))
    }

    // MARK: - Test Helpers

    /// Simulate receiving a message from the server.
    func inject(_ message: SyncMessage) {
        messageContinuation.yield(message)
    }

    /// Simulate a connection state change.
    func simulateConnectionState(_ state: ConnectionState) {
        stateContinuation.yield(state)
    }

    /// Simulate receiving a voice clip from another member.
    func injectVoiceClip(_ clip: IncomingVoiceClip) {
        voiceClipContinuation.yield(clip)
    }

    /// Clear captured messages.
    func reset() {
        sentMessages.removeAll()
        sentVoiceClips.removeAll()
    }
}
