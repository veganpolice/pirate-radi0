import SwiftUI

@main
struct PirateRadioApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var authManager = SpotifyAuthManager()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(authManager)
                .preferredColorScheme(.dark)
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

/// Placeholder until Session feature is built in Phase 2
struct SessionRootView: View {
    @Environment(SpotifyAuthManager.self) private var authManager

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Text("PIRATE RADIO")
                    .font(.custom("Menlo", size: 28, relativeTo: .title))
                    .foregroundStyle(PirateTheme.signal)
                    .shadow(color: PirateTheme.signal.opacity(0.6), radius: 8)

                Text("Logged in as \(authManager.displayName ?? "Unknown")")
                    .foregroundStyle(.white.opacity(0.7))

                Text("Phase 2: Sessions coming soon")
                    .foregroundStyle(.white.opacity(0.4))

                Button("Sign Out") {
                    Task { await authManager.signOut() }
                }
                .buttonStyle(GloveButtonStyle(color: PirateTheme.flare))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(PirateTheme.void)
        }
    }
}
