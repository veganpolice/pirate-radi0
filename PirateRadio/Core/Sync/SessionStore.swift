import Foundation

/// Single source of truth for the current session state.
/// ViewModels project slices of this store; the SyncEngine writes to it.
@Observable
@MainActor
final class SessionStore {
    // MARK: - State

    private(set) var session: Session?
    private(set) var connectionState: ConnectionState = .disconnected
    private(set) var syncStatus: SyncEngine.SyncStatus = .synced
    private(set) var isLoading = false
    private(set) var error: PirateRadioError?

    // MARK: - Dependencies

    private var syncEngine: SyncEngine?
    private let authManager: SpotifyAuthManager
    private let baseURL: URL

    // MARK: - Init

    init(authManager: SpotifyAuthManager, baseURL: URL = URL(string: "https://pirate-radio-sync.fly.dev")!) {
        self.authManager = authManager
        self.baseURL = baseURL
    }

    // MARK: - Actions

    func createSession() async {
        isLoading = true
        error = nil

        do {
            let backendToken = try await getBackendToken()
            let session = try await createSessionOnBackend(token: backendToken)
            self.session = session

            try await connectToSession(sessionID: session.id, token: backendToken)
        } catch {
            self.error = .sessionCreationFailed(underlying: error)
        }

        isLoading = false
    }

    func joinSession(code: String) async {
        isLoading = true
        error = nil

        do {
            let backendToken = try await getBackendToken()
            let sessionInfo = try await joinSessionOnBackend(code: code, token: backendToken)

            self.session = Session(
                id: sessionInfo.id,
                joinCode: sessionInfo.joinCode,
                creatorID: "",
                djUserID: sessionInfo.djUserId,
                members: [],
                queue: [],
                currentTrack: nil,
                isPlaying: false,
                epoch: 0
            )

            try await connectToSession(sessionID: sessionInfo.id, token: backendToken)
        } catch {
            self.error = .sessionNotFound
        }

        isLoading = false
    }

    func leaveSession() async {
        await syncEngine?.stop()
        syncEngine = nil
        session = nil
        connectionState = .disconnected
    }

    // MARK: - DJ Actions

    var isDJ: Bool {
        guard let session, let userID = authManager.userID else { return false }
        return session.djUserID == userID
    }

    func play(track: Track) async {
        guard isDJ else { return }
        do {
            try await syncEngine?.djPlay(track: track)
        } catch {
            self.error = .playbackFailed(underlying: error)
        }
    }

    func pause() async {
        guard isDJ else { return }
        try? await syncEngine?.djPause()
    }

    func resume() async {
        guard isDJ else { return }
        try? await syncEngine?.djResume()
    }

    func seek(to positionMs: Int) async {
        guard isDJ else { return }
        try? await syncEngine?.djSeek(to: positionMs)
    }

    // MARK: - Private

    private func connectToSession(sessionID: String, token: String) async throws {
        let transport = WebSocketTransport(baseURL: baseURL)
        let clock = KronosClock()
        let player = SpotifyPlayer()

        let engine = SyncEngine(musicSource: player, transport: transport, clock: clock)

        // Bridge SyncEngine updates to @Observable state
        await engine.setOnSessionUpdate { [weak self] update in
            Task { @MainActor in
                self?.handleUpdate(update)
            }
        }

        try await engine.start(sessionID: sessionID, token: token)
        self.syncEngine = engine
    }

    private func handleUpdate(_ update: SyncEngine.SessionUpdate) {
        switch update {
        case .connectionStateChanged(let state):
            connectionState = state
        case .syncStatus(let status):
            syncStatus = status
        case .playbackStateChanged(let isPlaying, _):
            session?.isPlaying = isPlaying
        case .memberJoined(let userID, let name):
            session?.members.append(Session.Member(id: userID, displayName: name, isConnected: true))
        case .memberLeft(let userID):
            session?.members.removeAll { $0.id == userID }
        case .queueUpdated:
            break // Queue updates handled separately
        case .trackChanged:
            break
        }
    }

    private func getBackendToken() async throws -> String {
        guard let userID = authManager.userID else {
            throw PirateRadioError.notAuthenticated
        }

        var request = URLRequest(url: baseURL.appendingPathComponent("auth"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = ["spotifyUserId": userID, "displayName": authManager.displayName ?? userID]
        request.httpBody = try JSONEncoder().encode(body)

        let (data, _) = try await URLSession.shared.data(for: request)
        let response = try JSONDecoder().decode(AuthResponse.self, from: data)
        return response.token
    }

    private func createSessionOnBackend(token: String) async throws -> Session {
        var request = URLRequest(url: baseURL.appendingPathComponent("sessions"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, _) = try await URLSession.shared.data(for: request)
        let response = try JSONDecoder().decode(CreateSessionResponse.self, from: data)

        return Session(
            id: response.id,
            joinCode: response.joinCode,
            creatorID: response.creatorId,
            djUserID: response.djUserId,
            members: [],
            queue: [],
            currentTrack: nil,
            isPlaying: false,
            epoch: 0
        )
    }

    private func joinSessionOnBackend(code: String, token: String) async throws -> JoinSessionResponse {
        var request = URLRequest(url: baseURL.appendingPathComponent("sessions/join"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = ["code": code]
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw PirateRadioError.sessionNotFound
        }

        return try JSONDecoder().decode(JoinSessionResponse.self, from: data)
    }
}

// MARK: - SyncEngine extension for callback setter

extension SyncEngine {
    func setOnSessionUpdate(_ handler: @escaping (SessionUpdate) -> Void) {
        self.onSessionUpdate = handler
    }
}

// MARK: - API Response Models

private struct AuthResponse: Codable {
    let token: String
}

private struct CreateSessionResponse: Codable {
    let id: String
    let joinCode: String
    let creatorId: String
    let djUserId: String
}

private struct JoinSessionResponse: Codable {
    let id: String
    let joinCode: String
    let djUserId: String
    let memberCount: Int
}
