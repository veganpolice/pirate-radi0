import SwiftUI

/// Full-screen signal lost → reconnect animation overlay.
struct SignalLostOverlay: View {
    @Binding var isActive: Bool
    @Environment(ToastManager.self) private var toastManager

    @State private var staticIntensity: Double = 0
    @State private var textPulse = false
    @State private var showSearching = false
    @State private var showReconnected = false
    @State private var dimBackground = false

    var body: some View {
        if isActive {
            ZStack {
                // Dim background
                Color.black.opacity(dimBackground ? 0.7 : 0)
                    .ignoresSafeArea()

                // CRT static
                CRTStaticOverlay(intensity: staticIntensity)
                    .ignoresSafeArea()

                VStack(spacing: 24) {
                    if showReconnected {
                        Text("SIGNAL LOCKED")
                            .font(PirateTheme.display(28))
                            .foregroundStyle(PirateTheme.signal)
                            .neonGlow(PirateTheme.signal, intensity: 0.8)
                            .transition(.scale.combined(with: .opacity))
                    } else {
                        Image(systemName: "antenna.radiowaves.left.and.right.slash")
                            .font(.system(size: 48))
                            .foregroundStyle(PirateTheme.flare)
                            .opacity(textPulse ? 1.0 : 0.4)

                        Text("SIGNAL LOST")
                            .font(PirateTheme.display(32))
                            .foregroundStyle(PirateTheme.flare)
                            .neonGlow(PirateTheme.flare, intensity: textPulse ? 0.8 : 0.3)

                        if showSearching {
                            Text("Searching for signal...")
                                .font(PirateTheme.body(14))
                                .foregroundStyle(.white.opacity(0.5))
                                .transition(.opacity)
                        }
                    }
                }
            }
            .allowsHitTesting(true)
            .onAppear { startSequence() }
            .sensoryFeedback(.impact(weight: .heavy), trigger: isActive)
        }
    }

    private func startSequence() {
        // Phase 1: Static fades in
        withAnimation(.easeIn(duration: 0.5)) {
            staticIntensity = 0.8
            dimBackground = true
        }

        // Phase 2: Text pulses
        withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
            textPulse = true
        }

        // Phase 3: Show searching
        Task {
            try? await Task.sleep(for: .seconds(1))
            withAnimation(.easeIn(duration: 0.3)) {
                showSearching = true
            }

            // Phase 4: Reconnect after 3s
            try? await Task.sleep(for: .seconds(3))

            withAnimation(.easeOut(duration: 1)) {
                staticIntensity = 0
                textPulse = false
                showSearching = false
            }

            try? await Task.sleep(for: .seconds(0.3))

            withAnimation(.spring(duration: 0.5)) {
                showReconnected = true
            }

            try? await Task.sleep(for: .seconds(1.5))

            withAnimation(.easeOut(duration: 0.5)) {
                dimBackground = false
                showReconnected = false
                isActive = false
            }

            toastManager.show(.reconnected, message: "Back on air!")
        }
    }
}
