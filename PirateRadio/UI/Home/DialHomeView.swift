import SwiftUI

/// The radio dial home screen. Auto-tunes on appear, shows live stations
/// as notches on the dial. Tap a station to tune in.
struct DialHomeView: View {
    @Environment(SessionStore.self) private var sessionStore

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
        .onChange(of: sessionStore.session) { oldValue, newValue in
            // Re-fetch stations when returning from a session
            if oldValue != nil && newValue == nil {
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
        } else {
            VStack(spacing: 8) {
                Text("PIRATE RADIO")
                    .font(PirateTheme.display(28))
                    .foregroundStyle(PirateTheme.signal)
                    .neonGlow(PirateTheme.signal, intensity: 0.5)

                Text("5 stations on air — pick one")
                    .font(PirateTheme.body(14))
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
    }
}
