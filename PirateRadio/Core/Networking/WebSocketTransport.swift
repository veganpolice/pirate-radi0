import Foundation

/// WebSocket-based implementation of SessionTransport.
/// Connects to the Pirate Radio backend using URLSessionWebSocketTask.
/// Handles reconnection with exponential backoff.
actor WebSocketTransport: SessionTransport {
    private let baseURL: URL
    private var webSocketTask: URLSessionWebSocketTask?
    private var sessionID: SessionID?
    private var token: String?

    private let messageContinuation: AsyncStream<SyncMessage>.Continuation
    let incomingMessages: AsyncStream<SyncMessage>

    private let stateContinuation: AsyncStream<ConnectionState>.Continuation
    let connectionState: AsyncStream<ConnectionState>

    private var reconnectAttempt = 0
    private var maxReconnectAttempts = 10
    private var isReconnecting = false
    private var shouldStayConnected = false
    private var lastSeenSeq: UInt64 = 0
    private var lastSeenEpoch: UInt64 = 0

    init(baseURL: URL) {
        self.baseURL = baseURL

        let (msgStream, msgCont) = AsyncStream.makeStream(of: SyncMessage.self, bufferingPolicy: .bufferingNewest(50))
        self.incomingMessages = msgStream
        self.messageContinuation = msgCont

        let (stateStream, stateCont) = AsyncStream.makeStream(of: ConnectionState.self, bufferingPolicy: .bufferingNewest(1))
        self.connectionState = stateStream
        self.stateContinuation = stateCont
    }

    // MARK: - SessionTransport

    func connect(to session: SessionID, token: String) async throws {
        self.sessionID = session
        self.token = token
        self.shouldStayConnected = true
        self.reconnectAttempt = 0

        try await establishConnection()
    }

    func disconnect() async {
        shouldStayConnected = false
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        stateContinuation.yield(.disconnected)
    }

    func send(_ message: SyncMessage) async throws {
        guard let task = webSocketTask else {
            throw PirateRadioError.notConnected
        }

        let data = try JSONEncoder().encode(message)
        try await task.send(.data(data))
    }

    // MARK: - Connection

    private func establishConnection() async throws {
        guard let sessionID, let token else {
            throw PirateRadioError.notAuthenticated
        }

        stateContinuation.yield(.connecting)

        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        components.scheme = baseURL.scheme == "https" ? "wss" : "ws"
        components.queryItems = [
            URLQueryItem(name: "token", value: token),
            URLQueryItem(name: "sessionId", value: sessionID),
        ]

        guard let wsURL = components.url else {
            throw PirateRadioError.sessionNotFound
        }

        let session = URLSession(configuration: .default)
        let task = session.webSocketTask(with: wsURL)
        self.webSocketTask = task
        task.resume()

        stateContinuation.yield(.connected)
        reconnectAttempt = 0

        startReceiving()
    }

    private func startReceiving() {
        guard let task = webSocketTask else { return }

        Task { [weak self] in
            while task.state == .running {
                do {
                    let message = try await task.receive()
                    await self?.handleReceivedMessage(message)
                } catch {
                    await self?.handleDisconnection(error: error)
                    break
                }
            }
        }
    }

    private func handleReceivedMessage(_ message: URLSessionWebSocketTask.Message) {
        let data: Data
        switch message {
        case .data(let d):
            data = d
        case .string(let s):
            guard let d = s.data(using: .utf8) else { return }
            data = d
        @unknown default:
            return
        }

        guard let syncMessage = try? JSONDecoder().decode(SyncMessage.self, from: data) else {
            return
        }

        // Track sequence numbers for reconnection
        if syncMessage.sequenceNumber > lastSeenSeq {
            lastSeenSeq = syncMessage.sequenceNumber
        }
        if syncMessage.epoch > lastSeenEpoch {
            lastSeenEpoch = syncMessage.epoch
        }

        messageContinuation.yield(syncMessage)
    }

    // MARK: - Reconnection

    private func handleDisconnection(error: Error) {
        guard shouldStayConnected, !isReconnecting else { return }

        webSocketTask = nil
        isReconnecting = true

        Task {
            while shouldStayConnected && reconnectAttempt < maxReconnectAttempts {
                reconnectAttempt += 1
                stateContinuation.yield(.reconnecting(attempt: reconnectAttempt))

                // Exponential backoff: 0.5s, 1s, 2s, 4s, 8s, cap at 15s
                let delay = min(0.5 * pow(2.0, Double(reconnectAttempt - 1)), 15.0)
                try? await Task.sleep(for: .seconds(delay))

                guard shouldStayConnected else { break }

                do {
                    try await establishConnection()
                    isReconnecting = false
                    stateContinuation.yield(.resyncing)
                    return
                } catch {
                    // Continue trying
                }
            }

            isReconnecting = false
            if shouldStayConnected {
                stateContinuation.yield(.failed("Unable to reconnect after \(maxReconnectAttempts) attempts"))
            }
        }
    }
}
