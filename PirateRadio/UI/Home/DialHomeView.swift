import SwiftUI

/// The radio dial home screen. Auto-tunes on appear, shows live stations
/// as notches on the dial, and offers a "Start Broadcasting" CTA.
struct DialHomeView: View {
    @Environment(SessionStore.self) private var sessionStore
    @Environment(ToastManager.self) private var toastManager

    @State private var dialValue: Double = 0.5

    var body: some View {
        ZStack {
            PirateTheme.void.ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer()

                // Tuning header
                tuningHeader

                // The dial with live station notches
                FrequencyDial(
                    value: $dialValue,
                    color: PirateTheme.signal,
                    stations: sessionStore.stations,
                    onTuneToStation: { station in
                        sessionStore.tuneToStation(station)
                    }
                )
                .padding(.horizontal, 24)

                // "Start Broadcasting" button
                Button {
                    Task { await startBroadcasting() }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                        Text("Start Broadcasting")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(GloveButtonStyle(color: PirateTheme.broadcast))
                .padding(.horizontal, 24)

                if let error = sessionStore.error {
                    Text(error.errorDescription ?? "Something went wrong")
                        .font(PirateTheme.body(13))
                        .foregroundStyle(PirateTheme.flare)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }

                Spacer()
            }
        }
        .task {
            await sessionStore.autoTune()
        }
        .onAppear {
            // Re-fetch stations when returning from NowPlayingView
            if !sessionStore.isAutoTuning {
                Task { await sessionStore.fetchStations() }
            }
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private var tuningHeader: some View {
        if sessionStore.isAutoTuning {
            HStack(spacing: 8) {
                ProgressView()
                    .tint(PirateTheme.signal)
                Text("Tuning in...")
                    .font(PirateTheme.body(16))
                    .foregroundStyle(PirateTheme.signal)
            }
        } else if sessionStore.stations.isEmpty {
            VStack(spacing: 8) {
                Text("PIRATE RADIO")
                    .font(PirateTheme.display(28))
                    .foregroundStyle(PirateTheme.signal)
                    .neonGlow(PirateTheme.signal, intensity: 0.5)

                Text("Nobody's on right now")
                    .font(PirateTheme.body(14))
                    .foregroundStyle(.white.opacity(0.5))
            }
        } else {
            VStack(spacing: 8) {
                Text("PIRATE RADIO")
                    .font(PirateTheme.display(28))
                    .foregroundStyle(PirateTheme.signal)
                    .neonGlow(PirateTheme.signal, intensity: 0.5)

                Text("\(sessionStore.stations.count) station\(sessionStore.stations.count == 1 ? "" : "s") live")
                    .font(PirateTheme.body(14))
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
    }

    // MARK: - Actions

    private func startBroadcasting() async {
        if sessionStore.session != nil {
            await sessionStore.leaveSession()
        }
        await sessionStore.createSession()
    }
}
