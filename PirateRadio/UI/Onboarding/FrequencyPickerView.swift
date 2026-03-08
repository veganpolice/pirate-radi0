import SwiftUI

/// Dial-based frequency picker shown after first auth when user needs to claim a station.
/// Uses the same FrequencyDial component with odd-tenth FM detents (88.1, 88.3, ..., 107.9).
struct FrequencyPickerView: View {
    @Environment(SessionStore.self) private var sessionStore

    @State private var dialValue: Double = 0.5
    @State private var isClaiming = false
    @State private var errorMessage: String?

    /// Selected frequency as MHz x 10 integer (e.g. 881 = 88.1 FM).
    private var selectedFrequency: Int {
        let freq = Station.fmMin + dialValue * (Station.fmMax - Station.fmMin)
        // Snap to nearest odd tenth: 88.1, 88.3, 88.5, ...
        let tenths = Int((freq * 10).rounded())
        let lower = tenths % 2 == 1 ? tenths : tenths - 1
        let upper = lower + 2
        let snapped = (tenths - lower <= upper - tenths) ? lower : upper
        return max(Station.fmMinInt, min(Station.fmMaxInt, snapped))
    }

    private var frequencyDisplay: String {
        String(format: "%.1f FM", Double(selectedFrequency) / 10.0)
    }

    var body: some View {
        ZStack {
            PirateTheme.void.ignoresSafeArea()

            VStack(spacing: 32) {
                Spacer()

                Text("CLAIM YOUR FREQUENCY")
                    .font(PirateTheme.display(24))
                    .foregroundStyle(PirateTheme.broadcast)
                    .neonGlow(PirateTheme.broadcast, intensity: 0.6)

                Text("Pick a spot on the dial — this is your station")
                    .font(PirateTheme.body(14))
                    .foregroundStyle(.white.opacity(0.5))
                    .multilineTextAlignment(.center)

                // Big frequency display
                Text(frequencyDisplay)
                    .font(PirateTheme.display(48))
                    .foregroundStyle(PirateTheme.signal)
                    .neonGlow(PirateTheme.signal, intensity: 0.8)
                    .contentTransition(.numericText())
                    .animation(.easeOut(duration: 0.15), value: selectedFrequency)

                // Dial
                FrequencyDial(value: $dialValue, color: PirateTheme.broadcast)
                    .frame(width: 220, height: 220)

                Spacer()

                if let error = errorMessage {
                    Text(error)
                        .font(PirateTheme.body(13))
                        .foregroundStyle(PirateTheme.flare)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }

                // Claim button
                Button {
                    Task { await claim() }
                } label: {
                    HStack(spacing: 12) {
                        if isClaiming {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Image(systemName: "antenna.radiowaves.left.and.right")
                        }
                        Text("Lock It In")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(GloveButtonStyle(color: PirateTheme.broadcast))
                .padding(.horizontal, 24)
                .disabled(isClaiming)

                Spacer()
            }
        }
    }

    private func claim() async {
        isClaiming = true
        errorMessage = nil
        await sessionStore.claimFrequency(selectedFrequency)
        if sessionStore.needsFrequency {
            errorMessage = "That frequency is taken — try another!"
        }
        isClaiming = false
    }
}
