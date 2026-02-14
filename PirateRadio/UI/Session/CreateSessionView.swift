import SwiftUI

/// Session creation flow: pick DJ mode → show join code.
/// In demo mode, creates session immediately with selected mode.
struct CreateSessionView: View {
    @Environment(SessionStore.self) private var sessionStore

    @State private var selectedMode: DJMode = .solo
    @State private var showCode = false

    var body: some View {
        ZStack {
            PirateTheme.void.ignoresSafeArea()

            if showCode, let session = sessionStore.session {
                codeDisplay(session)
            } else {
                modeSelection
            }
        }
        .onAppear {
            // In demo mode, if session already exists, skip to code
            if sessionStore.session != nil {
                showCode = true
            }
        }
    }

    // MARK: - Mode Selection

    private var modeSelection: some View {
        VStack(spacing: 24) {
            Spacer()

            Text("START BROADCASTING")
                .font(PirateTheme.display(22))
                .foregroundStyle(PirateTheme.broadcast)
                .neonGlow(PirateTheme.broadcast, intensity: 0.5)

            DJModePicker(selectedMode: $selectedMode)
                .padding(.horizontal, 24)

            Button {
                createSession()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                    Text("Go Live")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(GloveButtonStyle(color: PirateTheme.broadcast))
            .padding(.horizontal, 24)

            Spacer()
        }
    }

    private func createSession() {
        if PirateRadioApp.demoMode {
            let session = MockData.demoSession(djMode: selectedMode)
            // Replace session in store via the demo approach
            sessionStore.changeDJMode(selectedMode)
            withAnimation(.spring(duration: 0.5)) {
                showCode = true
            }
        } else {
            Task { await sessionStore.createSession() }
            showCode = true
        }
    }

    // MARK: - Code Display

    private func codeDisplay(_ session: Session) -> some View {
        VStack(spacing: 32) {
            Spacer()

            Text("ON AIR")
                .font(PirateTheme.display(24))
                .foregroundStyle(PirateTheme.broadcast)
                .neonGlow(PirateTheme.broadcast, intensity: 0.8)

            Text("share this frequency")
                .font(PirateTheme.body(14))
                .foregroundStyle(.white.opacity(0.5))

            // DJ mode badge
            HStack(spacing: 8) {
                Image(systemName: session.djMode.icon)
                Text(session.djMode.rawValue)
            }
            .font(PirateTheme.body(13))
            .foregroundStyle(PirateTheme.broadcast.opacity(0.7))
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .background(
                Capsule().fill(PirateTheme.broadcast.opacity(0.1))
            )
            .overlay(Capsule().strokeBorder(PirateTheme.broadcast.opacity(0.3), lineWidth: 0.5))

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
