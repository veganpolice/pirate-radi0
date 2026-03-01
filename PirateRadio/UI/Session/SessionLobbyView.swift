import SwiftUI

/// Main screen after auth — create, join, or discover a session.
struct SessionLobbyView: View {
    @Environment(SpotifyAuthManager.self) private var authManager
    @Environment(SessionStore.self) private var sessionStore

    @State private var showJoinSheet = false
    @State private var showDiscovery = false

    var body: some View {
        ZStack {
            PirateTheme.void.ignoresSafeArea()

            VStack(spacing: 32) {
                Spacer()

                // Header
                VStack(spacing: 8) {
                    Text("PIRATE RADIO")
                        .font(PirateTheme.display(28))
                        .foregroundStyle(PirateTheme.signal)
                        .neonGlow(PirateTheme.signal, intensity: 0.5)

                    if let name = authManager.displayName {
                        Text("ahoy, \(name)")
                            .font(PirateTheme.body(14))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }

                Spacer()

                // Actions
                VStack(spacing: 16) {
                    Button {
                        if PirateRadioApp.demoMode {
                            // In demo mode, clear currentTrack so CreateSessionView shows
                            sessionStore.clearCurrentTrack()
                        } else {
                            Task { await sessionStore.createSession() }
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "antenna.radiowaves.left.and.right")
                            Text("Start Broadcasting")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(GloveButtonStyle(color: PirateTheme.broadcast))

                    Button {
                        showJoinSheet = true
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "radio")
                            Text("Tune In")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(GloveButtonStyle(color: PirateTheme.signal))

                    // Discover button
                    Button {
                        showDiscovery = true
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "dot.radiowaves.left.and.right")
                            Text("Discover Crews")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(GloveButtonStyle(color: PirateTheme.flare))
                }
                .padding(.horizontal, 24)

                if let error = sessionStore.error {
                    Text(error.errorDescription ?? "Something went wrong")
                        .font(PirateTheme.body(13))
                        .foregroundStyle(PirateTheme.flare)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }

                Spacer()

                // Sign out
                Button("Sign Out") {
                    Task { await authManager.signOut() }
                }
                .font(PirateTheme.body(13))
                .foregroundStyle(.white.opacity(0.4))
                .padding(.bottom, 24)
            }
        }
        .sheet(isPresented: $showJoinSheet) {
            JoinSessionView()
        }
        .sheet(isPresented: $showDiscovery) {
            DiscoveryView()
        }
    }
}
