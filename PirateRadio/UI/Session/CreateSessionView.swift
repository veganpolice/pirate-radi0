import SwiftUI

/// Displays the 4-digit join code after creating a session.
/// Large, readable code with share functionality.
struct CreateSessionView: View {
    @Environment(SessionStore.self) private var sessionStore

    var body: some View {
        ZStack {
            PirateTheme.void.ignoresSafeArea()

            if let session = sessionStore.session {
                VStack(spacing: 32) {
                    Spacer()

                    Text("ON AIR")
                        .font(PirateTheme.display(24))
                        .foregroundStyle(PirateTheme.broadcast)
                        .neonGlow(PirateTheme.broadcast, intensity: 0.8)

                    Text("share this frequency")
                        .font(PirateTheme.body(14))
                        .foregroundStyle(.white.opacity(0.5))

                    // Large code display
                    HStack(spacing: 16) {
                        ForEach(Array(session.joinCode.enumerated()), id: \.offset) { _, char in
                            Text(String(char))
                                .font(PirateTheme.display(56))
                                .foregroundStyle(PirateTheme.broadcast)
                                .frame(width: 64, height: 80)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(PirateTheme.broadcast.opacity(0.1))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .strokeBorder(PirateTheme.broadcast, lineWidth: 1.5)
                                )
                                .neonGlow(PirateTheme.broadcast, intensity: 0.5)
                        }
                    }

                    // Member count
                    HStack(spacing: 8) {
                        Image(systemName: "person.2.fill")
                        Text("\(session.members.count) crew member\(session.members.count == 1 ? "" : "s")")
                    }
                    .font(PirateTheme.body(14))
                    .foregroundStyle(.white.opacity(0.6))

                    // Share button
                    ShareLink(
                        item: "Join my Pirate Radio session! Code: \(session.joinCode)",
                        subject: Text("Pirate Radio"),
                        message: Text("Tune in to my session with code \(session.joinCode)")
                    ) {
                        HStack(spacing: 12) {
                            Image(systemName: "square.and.arrow.up")
                            Text("Share Code")
                        }
                    }
                    .buttonStyle(GloveButtonStyle(color: PirateTheme.signal))

                    Spacer()

                    // Connection status
                    ConnectionStatusBadge(state: sessionStore.connectionState)
                        .padding(.bottom, 16)
                }
                .padding(.horizontal, 24)
            }
        }
    }
}

/// Small badge showing connection state.
struct ConnectionStatusBadge: View {
    let state: ConnectionState

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
                .font(PirateTheme.body(11))
                .foregroundStyle(.white.opacity(0.5))
        }
    }

    private var color: Color {
        switch state {
        case .connected: PirateTheme.signal
        case .connecting, .reconnecting, .resyncing: PirateTheme.flare
        case .disconnected, .failed: .red.opacity(0.8)
        }
    }

    private var label: String {
        switch state {
        case .connected: "connected"
        case .connecting: "connecting..."
        case .reconnecting(let attempt): "reconnecting (\(attempt))..."
        case .resyncing: "resyncing..."
        case .disconnected: "disconnected"
        case .failed(let reason): "failed: \(reason)"
        }
    }
}
