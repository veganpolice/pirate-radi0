import SwiftUI

/// The radio dial home screen. Previews station audio as you scrub the dial,
/// shows a Join button when snapped to a station, and offers "Start Broadcasting".
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
                    onSnappedStationChanged: { station in
                        sessionStore.previewStation(station)
                    }
                )
                .padding(.horizontal, 24)

                // Join button — visible when previewing a station
                if let station = sessionStore.previewingStation {
                    Button {
                        sessionStore.tuneToStation(station)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "headphones")
                            Text("Join \(station.displayName)")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(GloveButtonStyle(color: PirateTheme.signal))
                    .padding(.horizontal, 24)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }

                // "My Broadcast" button
                Button {
                    Task { await startBroadcasting() }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                        Text("My Broadcast")
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
            .animation(.easeOut(duration: 0.2), value: sessionStore.previewingStation?.id)
        }
        .task {
            await sessionStore.autoTune()
            // Position dial at the auto-tuned station
            if let station = sessionStore.previewingStation {
                dialValue = dialPosition(for: station.frequency)
            }
        }
        .onChange(of: sessionStore.session) { oldValue, newValue in
            // Re-fetch stations and resume preview when returning from a session
            if oldValue != nil && newValue == nil {
                Task {
                    await sessionStore.fetchStations()
                    if let target = lastTunedStation() {
                        dialValue = dialPosition(for: target.frequency)
                        sessionStore.previewStation(target)
                    }
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

    // MARK: - Helpers

    /// Map FM frequency to 0–1 dial position.
    private func dialPosition(for frequency: Double) -> Double {
        (frequency - FrequencyDial.fmMin) / (FrequencyDial.fmMax - FrequencyDial.fmMin)
    }

    /// Find the last-tuned station from the current station list.
    private func lastTunedStation() -> Station? {
        let lastUserId = UserDefaults.standard.string(forKey: "lastTunedUserId")
        return sessionStore.stations.first(where: { $0.userId == lastUserId })
            ?? sessionStore.stations.first
    }

    // MARK: - Actions

    private func startBroadcasting() async {
        sessionStore.previewStation(nil)
        if sessionStore.session != nil {
            await sessionStore.leaveSession()
        }
        await sessionStore.createSession()
    }
}
