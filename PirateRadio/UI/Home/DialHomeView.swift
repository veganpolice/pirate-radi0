import SwiftUI

/// The radio dial home screen. Previews station audio as you scrub the dial,
/// then tap "Tune In" to join.
struct DialHomeView: View {
    @Environment(SessionStore.self) private var sessionStore

    @State private var selectedStationIndex: Int = 0

    /// The station the dial is currently pointing at.
    private var selectedStation: Station? {
        guard !sessionStore.stations.isEmpty else { return nil }
        let idx = min(max(selectedStationIndex, 0), sessionStore.stations.count - 1)
        return sessionStore.stations[idx]
    }

    var body: some View {
        ZStack {
            PirateTheme.void.ignoresSafeArea()

            VStack(spacing: 20) {
                Spacer()

                // Tuning header
                tuningHeader

                // The dial — snaps between station detents only
                FrequencyDial(
                    color: PirateTheme.signal,
                    stations: sessionStore.stations,
                    selectedIndex: $selectedStationIndex
                )
                .padding(.horizontal, 24)

                // "Tune In" button — always visible when a station is selected
                if let station = selectedStation {
                    tuneInButton(station: station)
                        .padding(.horizontal, 32)
                }

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
            // Position dial at the auto-tuned station
            if let station = sessionStore.previewingStation,
               let idx = sessionStore.stations.firstIndex(where: { $0.id == station.id }) {
                selectedStationIndex = idx
            }
        }
        .onChange(of: selectedStationIndex) { _, _ in
            // Preview audio when the dial snaps to a different station
            sessionStore.previewStation(selectedStation)
        }
        .onChange(of: sessionStore.session) { oldValue, newValue in
            // Re-fetch stations and resume preview when returning from a session
            if oldValue != nil && newValue == nil {
                Task {
                    await sessionStore.fetchStations()
                    // Restore last-tuned station index and preview
                    if let lastId = UserDefaults.standard.string(forKey: "lastTunedStationId"),
                       let idx = sessionStore.stations.firstIndex(where: { $0.id == lastId }) {
                        selectedStationIndex = idx
                    }
                    sessionStore.previewStation(selectedStation)
                }
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

                if !sessionStore.stations.isEmpty {
                    Text("\(sessionStore.stations.count) stations on air")
                        .font(PirateTheme.body(14))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
        }
    }

    private func tuneInButton(station: Station) -> some View {
        Button {
            sessionStore.tuneToStation(station)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                Text("Tune In")
                    .font(PirateTheme.display(18))
            }
            .foregroundStyle(PirateTheme.void)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(PirateTheme.signal)
            )
            .neonGlow(PirateTheme.signal, intensity: 0.4)
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: sessionStore.isLoading)
        .disabled(sessionStore.isLoading)
    }
}
