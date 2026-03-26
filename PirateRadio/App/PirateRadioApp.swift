import SwiftUI

@main
struct PirateRadioApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var authManager = SpotifyAuthManager()
    @State private var sessionStore: SessionStore?

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(authManager)
                .preferredColorScheme(.dark)
                .onChange(of: authManager.isAuthenticated) { _, isAuth in
                    if isAuth {
                        sessionStore = sessionStore ?? SessionStore(authManager: authManager)
                    } else {
                        sessionStore = nil
                    }
                }
                .onAppear {
                    if authManager.isAuthenticated {
                        sessionStore = SessionStore(authManager: authManager)
                    }
                }
                .optionalEnvironment(sessionStore)
        }
    }
}

struct RootView: View {
    @Environment(SpotifyAuthManager.self) private var authManager
    @Environment(SessionStore.self) private var sessionStore: SessionStore?

    var body: some View {
        Group {
            if authManager.isAuthenticated, let sessionStore {
                SessionRootView()
                    .environment(sessionStore)
            } else if authManager.isAuthenticated {
                ProgressView("Loading…")
            } else {
                SpotifyAuthView()
            }
        }
        .animation(.easeInOut(duration: 0.3), value: authManager.isAuthenticated)
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
