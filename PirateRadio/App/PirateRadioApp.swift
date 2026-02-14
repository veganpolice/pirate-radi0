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
                        sessionStore = SessionStore(authManager: authManager)
                    } else {
                        sessionStore = nil
                    }
                }
                .optionalEnvironment(sessionStore)
        }
    }
}

struct RootView: View {
    @Environment(SpotifyAuthManager.self) private var authManager

    var body: some View {
        Group {
            if authManager.isAuthenticated {
                SessionRootView()
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
                if sessionStore.session != nil {
                    CreateSessionView()
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
