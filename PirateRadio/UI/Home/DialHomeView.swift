import SwiftUI

/// The radio dial home screen. Previews station audio as you scrub the dial,
/// then tap to tune in. Voice clips work once tuned in.
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
                    onDetentSnap: { _ in
                        // Preview audio when the dial snaps to a station during drag
                        let snapped = snappedStation
                        sessionStore.previewStation(snapped)
                    },
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
            // Re-fetch stations and resume preview when returning from a session
            if oldValue != nil && newValue == nil {
                Task {
                    await sessionStore.fetchStations()
                    sessionStore.previewStation(sessionStore.previewingStation)
                }
            }
        }
    }

    // MARK: - Helpers

    /// The station closest to the current dial position.
    private var snappedStation: Station? {
        guard !sessionStore.stations.isEmpty else { return nil }
        var closest: Station?
        var closestDist = Double.infinity
        let fmMin = 88.0, fmMax = 108.0
        for station in sessionStore.stations {
            let stationValue = (station.frequency - fmMin) / (fmMax - fmMin)
            let dist = abs(dialValue - stationValue)
            if dist < closestDist && dist < 0.08 {
                closestDist = dist
                closest = station
            }
        }
        return closest
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

                Text("\(sessionStore.stations.count) stations on air — pick one")
                    .font(PirateTheme.body(14))
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
    }
}
