import SwiftUI

@main
struct PirateRadioApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var authManager: SpotifyAuthManager
    @State private var sessionStore: SessionStore?
    @State private var toastManager = ToastManager()
    @State private var mockTimerManager = MockTimerManager()

    /// Set to true to bypass Spotify auth and explore the UI with mock data.
    static let demoMode = true

    init() {
        let auth = SpotifyAuthManager()
        if Self.demoMode {
            auth.enableDemoMode()
            _authManager = State(initialValue: auth)
            _sessionStore = State(initialValue: SessionStore.demo())
        } else {
            _authManager = State(initialValue: auth)
            _sessionStore = State(initialValue: nil)
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.dark)
                .overlay { ToastOverlay() }
                .onChange(of: authManager.isAuthenticated) { _, isAuth in
                    guard !Self.demoMode else { return }
                    if isAuth {
                        sessionStore = SessionStore(authManager: authManager)
                    } else {
                        sessionStore = nil
                    }
                }
                .optionalEnvironment(sessionStore)
                .onAppear {
                    if Self.demoMode {
                        mockTimerManager.start()
                    }
                }
                .onChange(of: mockTimerManager.lastEvent) { _, event in
                    handleMockEvent(event)
                }
                .environment(authManager)
                .environment(toastManager)
                .environment(mockTimerManager)
        }
    }

    private func handleMockEvent(_ event: MockTimerManager.MockEvent?) {
        guard let event else { return }
        switch event {
        case .memberJoined(let name):
            toastManager.show(.memberJoined, message: "\(name) joined the session")
        case .memberLeft(let name):
            toastManager.show(.memberLeft, message: "\(name) left the session")
        case .songRequested(let track, let by):
            toastManager.show(.songRequest, message: "\(by) requested \"\(track)\"")
        case .voteCast(let track, let by, let isUp):
            toastManager.show(.voteCast, message: "\(by) \(isUp ? "upvoted" : "downvoted") \"\(track)\"")
        case .hotSeatRotation(let newDJ):
            toastManager.show(.djChanged, message: "\(newDJ) is now DJ!")
        case .signalLost:
            toastManager.show(.signalLost, message: "Signal lost!")
        case .signalReconnected:
            toastManager.show(.reconnected, message: "Back on air!")
        case .voiceClipReceived(let from):
            toastManager.show(.voiceClip, message: "Voice clip from \(from)")
        }
    }
}

struct RootView: View {
    @Environment(SpotifyAuthManager.self) private var authManager

    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    var body: some View {
        Group {
            if !hasCompletedOnboarding {
                OnboardingView {
                    withAnimation(.easeInOut(duration: 0.5)) {
                        hasCompletedOnboarding = true
                    }
                }
            } else if authManager.isAuthenticated {
                SessionRootView()
            } else {
                SpotifyAuthView()
            }
        }
        .animation(.easeInOut(duration: 0.3), value: authManager.isAuthenticated)
        .animation(.easeInOut(duration: 0.3), value: hasCompletedOnboarding)
    }
}

struct SessionRootView: View {
    @Environment(SessionStore.self) private var sessionStore

    var body: some View {
        NavigationStack {
            Group {
                if let session = sessionStore.session {
                    if session.currentTrack != nil {
                        NowPlayingView()
                    } else {
                        CreateSessionView()
                    }
                } else {
                    SessionLobbyView()
                }
            }
        }
    }
}

// MARK: - Optional Environment Helper

private extension View {
    @ViewBuilder
    func optionalEnvironment<T: AnyObject & Observable>(_ value: T?) -> some View {
        if let value {
            self.environment(value)
        } else {
            self
        }
    }
}
